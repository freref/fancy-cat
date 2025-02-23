const std = @import("std");
const vaxis = @import("vaxis");
const ViewState = @import("states/ViewState.zig");
const CommandState = @import("states/CommandState.zig");
const fzwatch = @import("fzwatch");
const Config = @import("config/Config.zig");
const PdfHandler = @import("./PdfHandler.zig");
const Cache = @import("./Cache.zig");

pub const panic = vaxis.panic_handler;

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    file_changed,
};

pub const StateType = enum { view, command };
pub const State = union(StateType) { view: ViewState, command: CommandState };

pub const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    pdf_handler: PdfHandler,
    page_info_text: []u8,
    current_page: ?vaxis.Image,
    watcher: ?fzwatch.Watcher,
    watcher_thread: ?std.Thread,
    config: *Config,
    current_state: State,
    reload_page: bool,
    cache: Cache,
    check_cache: bool,

    pub fn init(allocator: std.mem.Allocator, args: [][:0]u8) !Self {
        const path = args[1];
        const initial_page = if (args.len == 3)
            try std.fmt.parseInt(u16, args[2], 10)
        else
            null;

        const config = try allocator.create(Config);
        config.* = try Config.init(allocator);

        var pdf_handler = try PdfHandler.init(allocator, path, initial_page, config);
        errdefer pdf_handler.deinit();

        var watcher: ?fzwatch.Watcher = null;
        if (config.file_monitor.enabled) {
            watcher = try fzwatch.Watcher.init(allocator);
            if (watcher) |*w| try w.addFile(path);
        }

        const vx = try vaxis.init(allocator, .{});
        const tty = try vaxis.Tty.init();

        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = tty,
            .vx = vx,
            .pdf_handler = pdf_handler,
            .page_info_text = &[_]u8{},
            .current_page = null,
            .watcher = watcher,
            .mouse = null,
            .watcher_thread = null,
            .config = config,
            .current_state = undefined,
            .reload_page = false,
            .cache = Cache.init(allocator, config),
            .check_cache = true,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.current_state) {
            .command => |*state| state.deinit(),
            .view => {},
        }
        if (self.watcher) |*w| {
            w.stop();
            if (self.watcher_thread) |thread| thread.join();
            w.deinit();
        }

        if (self.page_info_text.len > 0) self.allocator.free(self.page_info_text);

        self.allocator.destroy(self.config);
        self.cache.deinit();
        self.pdf_handler.deinit();
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

    fn watcherWorker(self: *Self, watcher: *fzwatch.Watcher) !void {
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
                self.watcher_thread = try std.Thread.spawn(.{}, watcherWorker, .{ self, w });
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
        self.current_page = null;
        self.pdf_handler.resetZoomAndScroll();
        self.check_cache = true;
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
    }

    pub fn update(self: *Self, event: Event) !void {
        switch (event) {
            .key_press => |key| try self.handleKeyStroke(key),
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
                self.pdf_handler.resetZoomAndScroll();
                self.cache.clear();
                self.reload_page = true;
            },
            .file_changed => {
                try self.pdf_handler.reloadDocument();
                self.reload_page = true;
            },
        }
    }

    pub fn getCurrentPage(
        self: *Self,
        window_width: u32,
        window_height: u32,
    ) !void {
        // TODO make this interchangeable with other file formats (no pdf specific logic in context)
        const shouldCheckCache = self.config.cache.enabled and
            self.pdf_handler.zoom == 0 and
            self.pdf_handler.x_offset == 0 and
            self.pdf_handler.y_offset == 0 and
            self.check_cache;

        if (shouldCheckCache) {
            if (self.cache.get(.{
                .colorize = self.config.general.colorize,
                .page = self.pdf_handler.current_page_number,
            })) |cached| {
                // Once we get the cached image we don't need to check the cache anymore because
                // The only actions a user can take is zoom or scrolling, but we don't cache those
                // Or go to the next page, at which point we set check_cache to true again
                self.check_cache = false;
                self.current_page = cached.image;
                return;
            }
        }

        const image = try self.pdf_handler.renderPage(
            self.pdf_handler.current_page_number,
            window_width,
            window_height,
        );
        defer self.allocator.free(image.base64);

        self.current_page = try self.vx.transmitPreEncodedImage(
            self.tty.anyWriter(),
            image.base64,
            image.width,
            image.height,
            .rgb,
        );

        if (!self.config.cache.enabled) return;

        if (self.current_page) |img| {
            _ = try self.cache.put(.{
                .colorize = self.config.general.colorize,
                .page = self.pdf_handler.current_page_number,
            }, .{ .image = img });
        }
    }

    pub fn drawCurrentPage(self: *Self, win: vaxis.Window) !void {
        self.pdf_handler.commitReload();
        if (self.current_page == null or self.reload_page) {
            const winsize = try vaxis.Tty.getWinsize(self.tty.fd);
            const pix_per_col = try std.math.divCeil(u16, win.screen.width_pix, win.screen.width);
            const pix_per_row = try std.math.divCeil(u16, win.screen.height_pix, win.screen.height);
            const x_pix = winsize.cols * pix_per_col;
            var y_pix = winsize.rows * pix_per_row;
            if (self.config.status_bar.enabled) {
                y_pix -|= 2 * pix_per_row;
            }

            try self.getCurrentPage(x_pix, y_pix);

            self.reload_page = false;
        }

        if (self.current_page) |img| {
            const dims = try img.cellSize(win);
            const x_off = (win.width - dims.cols) / 2;
            var y_off = (win.height - dims.rows) / 2;
            if (self.config.status_bar.enabled) {
                y_off -|= 1; // room for status bar
            }
            const center = win.child(.{
                .x_off = x_off,
                .y_off = y_off,
                .width = dims.cols,
                .height = dims.rows,
            });
            try img.draw(center, .{ .scale = .contain });
        }
    }

    pub fn drawStatusBar(self: *Self, win: vaxis.Window) !void {
        const status_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height -| 2,
            .width = win.width,
            .height = 1,
        });
        status_bar.fill(vaxis.Cell{ .style = self.config.status_bar.style });
        const mode_text = switch (self.current_state) {
            .view => "VIS",
            .command => "CMD",
        };
        _ = status_bar.print(
            &.{
                .{ .text = mode_text, .style = self.config.status_bar.style },
                .{ .text = "   ", .style = self.config.status_bar.style },
                .{ .text = self.pdf_handler.path, .style = self.config.status_bar.style },
            },
            .{ .col_offset = 1 },
        );
        if (self.page_info_text.len > 0) {
            self.allocator.free(self.page_info_text);
        }
        self.page_info_text = try std.fmt.allocPrint(
            self.allocator,
            "{d}:{d}",
            .{ self.pdf_handler.current_page_number + 1, self.pdf_handler.total_pages },
        );
        _ = status_bar.print(
            &.{.{ .text = self.page_info_text, .style = self.config.status_bar.style }},
            .{ .col_offset = @intCast(win.width -| self.page_info_text.len -| 1) },
        );
    }

    pub fn draw(self: *Self) !void {
        const win = self.vx.window();
        win.clear();

        try self.drawCurrentPage(win);

        if (self.config.status_bar.enabled) {
            try self.drawStatusBar(win);
        }

        if (self.current_state == .command) {
            self.current_state.command.drawCommandBar(win);
        }
    }
};
