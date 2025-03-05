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
    should_rerender,
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
    render_thread: ?std.Thread,
    mutex: std.Thread.Mutex,
    terminal_mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    signal_render: bool,
    render_page_number: u16,
    window_width: u32,
    window_height: u32,
    config: *Config,
    current_state: State,
    reload_page: bool,
    cache: Cache,
    should_check_cache: bool,
    loop: ?vaxis.Loop(Event),

    pub fn init(allocator: std.mem.Allocator, args: [][:0]u8) !Self {
        const path = args[1];
        const initial_page = if (args.len == 3)
            try std.fmt.parseInt(u16, args[2], 10)
        else
            null;

        const config = try allocator.create(Config);
        errdefer allocator.destroy(config);
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
            .render_thread = null,
            .mutex = std.Thread.Mutex{},
            .terminal_mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
            .signal_render = false,
            .window_width = 0,
            .window_height = 0,
            .render_page_number = 0,
            .config = config,
            .current_state = undefined,
            .reload_page = true,
            .cache = Cache.init(allocator, config),
            .should_check_cache = config.cache.enabled,
            .loop = null,
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
        if (self.render_thread) |thread| thread.join();

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

    fn renderWorker(self: *Self) !void {
        while (!self.should_quit) {
            self.mutex.lock();

            while (!self.signal_render and !self.should_quit) {
                self.condition.wait(&self.mutex);
            }

            self.signal_render = false;

            self.mutex.unlock();

            const encoded_image = try self.pdf_handler.renderPage(
                self.render_page_number,
                self.window_width,
                self.window_height,
            );
            defer self.allocator.free(encoded_image.base64);

            self.terminal_mutex.lock();

            const img = try self.vx.transmitPreEncodedImage(
                self.tty.anyWriter(),
                encoded_image.base64,
                encoded_image.width,
                encoded_image.height,
                .rgb,
            );

            self.terminal_mutex.unlock();

            self.mutex.lock();

            if (self.render_page_number == self.pdf_handler.current_page_number) {
                self.current_page = img;
                if (self.loop) |*loop| loop.postEvent(.should_rerender);
            }

            if (!self.config.cache.enabled) return;

            _ = try self.cache.put(.{
                .colorize = self.config.general.colorize,
                .page = self.render_page_number,
            }, .{ .image = img });

            self.mutex.unlock();
        }
    }

    pub fn run(self: *Self) !void {
        self.current_state = .{ .view = ViewState.init(self) };

        self.loop = vaxis.Loop(Event){ .tty = &self.tty, .vaxis = &self.vx };

        if (self.loop) |*loop| {
            try loop.init();
            try loop.start();
            defer loop.stop();
            try self.vx.enterAltScreen(self.tty.anyWriter());
            try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
            try self.vx.setMouseMode(self.tty.anyWriter(), true);

            self.render_thread = try std.Thread.spawn(.{}, renderWorker, .{self});

            if (self.config.file_monitor.enabled) {
                if (self.watcher) |*w| {
                    w.setCallback(callback, &self.loop);
                    self.watcher_thread = try std.Thread.spawn(.{}, watcherWorker, .{ self, w });
                }
            }

            while (!self.should_quit) {
                loop.pollEvent();

                while (loop.tryEvent()) |event| {
                    try self.update(event);
                }

                try self.draw();

                self.terminal_mutex.lock();
                defer self.terminal_mutex.unlock();
                var buffered = self.tty.bufferedWriter();
                try self.vx.render(buffered.writer().any());
                try buffered.flush();
            }
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
        self.should_check_cache = self.config.cache.enabled;
        self.reload_page = true;
    }

    pub fn handleKeyStroke(self: *Self, key: vaxis.Key) !void {
        const km = self.config.key_map;

        // Global keybindings
        if (key.matches(km.quit.codepoint, km.quit.mods)) {
            self.quit();
            return;
        }

        try switch (self.current_state) {
            .view => |*state| state.handleKeyStroke(key, km),
            .command => |*state| state.handleKeyStroke(key, km),
        };
    }

    pub fn quit(self: *Self) void {
        self.mutex.lock();
        self.should_quit = true;
        self.condition.signal();
        self.mutex.unlock();
    }

    pub fn update(self: *Self, event: Event) !void {
        switch (event) {
            .key_press => |key| try self.handleKeyStroke(key),
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
                self.pdf_handler.default_zoom = 0;
                self.pdf_handler.resetZoomAndScroll();
                self.cache.clear();
                self.reload_page = true;
            },
            .file_changed => {
                try self.pdf_handler.reloadDocument();
                // we could remove the current page from the cache here
                self.reload_page = true;
            },
            .should_rerender => {},
        }
    }

    // TODO make this func interchangeable with other file formats
    // (no pdf specific logic in context)
    pub fn getCurrentPage(
        self: *Self,
        window_width: u32,
        window_height: u32,
    ) !void {
        if (self.should_check_cache) {
            if (self.cache.get(.{
                .colorize = self.config.general.colorize,
                .page = self.pdf_handler.current_page_number,
            })) |cached| {
                // Once we get the cached image we don't need to check the cache anymore because
                // The only actions a user can take is zoom or scrolling, but we don't cache those
                // Or go to the next page, at which point we set check_cache to true again
                self.should_check_cache = false;
                self.current_page = cached.image;
                return;
            }
        }

        self.mutex.lock();
        self.render_page_number = self.pdf_handler.current_page_number;
        self.window_width = window_width;
        self.window_height = window_height;

        self.signal_render = true;
        self.condition.signal();
        self.mutex.unlock();

        self.should_check_cache = false;
    }

    pub fn drawCurrentPage(self: *Self, win: vaxis.Window) !void {
        if (self.reload_page) {
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
            self.terminal_mutex.lock();
            self.terminal_mutex.unlock();
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
