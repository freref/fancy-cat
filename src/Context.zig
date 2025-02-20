const std = @import("std");
const vaxis = @import("vaxis");
const ViewState = @import("state/ViewState.zig");
const CommandState = @import("state/CommandState.zig");
const fzwatch = @import("fzwatch");
const Config = @import("config/Config.zig");
const PdfHelper = @import("./helpers/PdfHelper.zig");

pub const panic = vaxis.panic_handler;

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    file_changed,
};

pub const StateType = enum {
    view,
    command,
};

pub const State = union(StateType) {
    view: ViewState,
    command: CommandState,
};

pub const Context = struct {
    const Self = @This();

    pub const KeyAction = struct {
        codepoint: u21,
        mods: vaxis.Key.Modifiers,
        handler: *const fn (*Context) void,
    };

    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    pdf_helper: PdfHelper,
    page_info_text: []u8,
    current_page: ?vaxis.Image,
    watcher: ?fzwatch.Watcher,
    thread: ?std.Thread,
    reload: bool,
    config: Config,
    current_state: State,

    pub fn init(allocator: std.mem.Allocator, args: [][]const u8) !Self {
        const path = args[1];
        const initial_page = if (args.len == 3)
            try std.fmt.parseInt(u16, args[2], 10)
        else
            null;

        const config = try Config.init(allocator);

        var pdf_helper = try PdfHelper.init(allocator, path, initial_page, config);
        errdefer pdf_helper.deinit();

        var watcher: ?fzwatch.Watcher = null;
        if (config.file_monitor.enabled) {
            watcher = try fzwatch.Watcher.init(allocator);
            if (watcher) |*w| try w.addFile(path);
        }

        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .pdf_helper = pdf_helper,
            .page_info_text = &[_]u8{},
            .current_page = null,
            .watcher = watcher,
            .mouse = null,
            .thread = null,
            .reload = false,
            .config = config,
            .current_state = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.current_state) {
            .command => |*state| state.deinit(),
            .view => {},
        }
        if (self.watcher) |*w| {
            w.stop();
            if (self.thread) |thread| thread.join();
            w.deinit();
        }
        if (self.page_info_text.len > 0) self.allocator.free(self.page_info_text);
        self.pdf_helper.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    fn callback(context: ?*anyopaque, event: fzwatch.Event) void {
        switch (event) {
            .modified => {
                const loop = @as(*vaxis.Loop(Event), @ptrCast(@alignCast(context.?)));
                loop.postEvent(Event.file_changed);
            },
        }
    }

    fn watcherThread(self: *Self, watcher: *fzwatch.Watcher) !void {
        try watcher.start(.{ .latency = self.config.file_monitor.latency });
    }

    pub fn run(self: *Self) !void {
        self.current_state = .{ .view = ViewState.init(self) };

        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };

        try loop.init();
        try loop.start();
        defer loop.stop();
        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        if (self.config.file_monitor.enabled) {
            if (self.watcher) |*w| {
                w.setCallback(callback, &loop);
                self.thread = try std.Thread.spawn(.{}, watcherThread, .{ self, w });
            }
        }

        while (!self.should_quit) {
            loop.pollEvent();

            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            try self.draw();

            var buffered = self.tty.bufferedWriter();
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
        }
    }

    pub fn changeState(self: *Self, new_state: StateType) void {
        switch (self.current_state) {
            .command => |*state| state.deinit(),
            .view => {},
        }

        switch (new_state) {
            .view => self.current_state = .{ .view = ViewState.init(self) },
            .command => self.current_state = .{ .command = CommandState.init(self) },
        }
    }

    pub fn resetCurrentPage(self: *Self) void {
        if (self.current_page) |img| {
            self.vx.freeImage(self.tty.anyWriter(), img.id);
            self.current_page = null;
        }
    }

    pub fn handleKeyStroke(self: *Self, key: vaxis.Key) !void {
        const km = self.config.key_map;

        // Global keybindings
        if (key.matches(km.quit.codepoint, km.quit.mods)) {
            self.should_quit = true;
            return;
        }

        try switch (self.current_state) {
            .view => |*state| state.handleKeyStroke(key, km),
            .command => |*state| state.handleKeyStroke(key, km),
        };

        self.reload = true;
    }

    pub fn update(self: *Self, event: Event) !void {
        switch (event) {
            .key_press => |key| try self.handleKeyStroke(key),
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
                self.pdf_helper.resetZoomAndScroll();
                self.reload = true;
            },
            .file_changed => {
                try self.pdf_helper.reloadDocument();
                self.reload = true;
            },
        }
    }

    pub fn drawCurrentPage(self: *Self, win: vaxis.Window) !void {
        self.pdf_helper.commitReload();
        if (self.current_page == null or self.reload) {
            const winsize = try vaxis.Tty.getWinsize(self.tty.fd);
            const encoded_image = try self.pdf_helper.renderPage(
                self.allocator,
                winsize.x_pixel,
                winsize.y_pixel,
            );
            defer self.allocator.free(encoded_image.base64);

            self.current_page = try self.vx.transmitPreEncodedImage(
                self.tty.anyWriter(),
                encoded_image.base64,
                encoded_image.width,
                encoded_image.height,
                .rgb,
            );

            self.reload = false;
        }

        if (self.current_page) |img| {
            const dims = try img.cellSize(win);
            const center = vaxis.widgets.alignment.center(win, dims.cols, dims.rows);
            try img.draw(center, .{ .scale = .contain });
        }
    }

    pub fn drawStatusBar(self: *Self, win: vaxis.Window) !void {
        const status_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - 2,
            .width = win.width,
            .height = 1,
        });

        status_bar.fill(vaxis.Cell{ .style = self.config.status_bar.style });

        _ = status_bar.print(
            &.{.{ .text = self.pdf_helper.path, .style = self.config.status_bar.style }},
            .{ .col_offset = 1 },
        );

        if (self.page_info_text.len > 0) {
            self.allocator.free(self.page_info_text);
        }

        self.page_info_text = try std.fmt.allocPrint(
            self.allocator,
            "{d}:{d}",
            .{ self.pdf_helper.current_page_number + 1, self.pdf_helper.total_pages },
        );

        _ = status_bar.print(
            &.{.{ .text = self.page_info_text, .style = self.config.status_bar.style }},
            .{ .col_offset = @intCast(win.width - self.page_info_text.len - 1) },
        );

        if (self.current_state == .command) self.current_state.command.drawCommandBar(win);
    }

    pub fn draw(self: *Self) !void {
        const win = self.vx.window();
        win.clear();

        try self.drawCurrentPage(win);
        if (self.config.status_bar.enabled) {
            try self.drawStatusBar(win);
        }
    }

    pub fn executeCommand(self: *Self, cmd: []u8) bool {
        const cmd_str = std.mem.trim(u8, cmd, " ");
        if (std.fmt.parseInt(u16, cmd_str, 10)) |page_num| {
            self.pdf_helper.goToPage(page_num);
            return true;
        } else |_| {
            return false;
        }
    }
};
