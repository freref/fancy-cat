const std = @import("std");
const vaxis = @import("vaxis");
const ViewMode = @import("modes/ViewMode.zig");
const CommandMode = @import("modes/CommandMode.zig");
const fzwatch = @import("fzwatch");
const Config = @import("config/Config.zig");
const DocumentHandler = @import("handlers/DocumentHandler.zig");
const Cache = @import("./Cache.zig");
const ReloadIndicatorTimer = @import("services/ReloadIndicatorTimer.zig");
const History = @import("services/History.zig");
const Tmux = @import("graphics/Tmux.zig");
const Ticker = @import("graphics/Ticker.zig");

pub const panic = vaxis.panic_handler;

pub const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    file_changed,
    reload_done: usize,
    graphics_response: struct { id: u32, ok: bool },
    graphics_tick,
};

pub const ModeType = enum { view, command };
pub const Mode = union(ModeType) { view: ViewMode, command: CommandMode };
pub const ReloadIndicatorState = enum { idle, reload, watching };

pub const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    document_handler: DocumentHandler,
    page_info_text: []u8,
    current_page: ?vaxis.Image,
    watcher: ?fzwatch.Watcher,
    watcher_thread: ?std.Thread,
    config: *Config,
    current_mode: Mode,
    history: History,
    reload_page: bool,
    cache: Cache,
    should_check_cache: bool,
    reload_indicator_timer: ReloadIndicatorTimer,
    current_reload_indicator_state: ReloadIndicatorState,
    reload_indicator_active: bool,
    buf: []u8,
    tmux_graphics: ?Tmux,
    image_changed: bool = false,
    graphics_visible: bool = true,
    pending_resize: ?vaxis.Winsize = null,
    resize_at: i64 = 0,
    retired_image: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator, args: [][:0]u8) !Self {
        const path = args[1];
        const initial_page = if (args.len == 3)
            try std.fmt.parseInt(u16, args[2], 10)
        else
            null;

        const config = try allocator.create(Config);
        errdefer allocator.destroy(config);
        config.* = Config.init(allocator);
        errdefer config.deinit();

        var document_handler = try DocumentHandler.init(allocator, path, initial_page, config);
        errdefer document_handler.deinit();

        var watcher: ?fzwatch.Watcher = null;
        if (config.file_monitor.enabled) {
            watcher = try fzwatch.Watcher.init(allocator);
            if (watcher) |*w| try w.addFile(path);
        }

        const vx = try vaxis.init(allocator, .{});
        const buf = try allocator.alloc(u8, 4096);
        const tty = try vaxis.Tty.init(buf);
        const reload_indicator_timer = ReloadIndicatorTimer.init(config);
        const history = History.init(allocator, config);

        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .should_quit = false,
            .tty = tty,
            .vx = vx,
            .document_handler = document_handler,
            .page_info_text = &[_]u8{},
            .current_page = null,
            .watcher = watcher,
            .mouse = null,
            .watcher_thread = null,
            .config = config,
            .current_mode = undefined,
            .history = history,
            .reload_page = true,
            .cache = Cache.init(allocator, config, vx, &tty),
            .should_check_cache = config.cache.enabled,
            .reload_indicator_timer = reload_indicator_timer,
            .current_reload_indicator_state = .idle,
            .reload_indicator_active = false,
            .buf = buf,
            .tmux_graphics = if (std.posix.getenv("TMUX") != null) Tmux.init(allocator) else null,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.current_mode) {
            .command => |*state| state.deinit(),
            .view => {},
        }
        if (self.watcher) |*w| {
            w.stop();
            if (self.watcher_thread) |thread| thread.join();
            w.deinit();
        }

        if (self.page_info_text.len > 0) self.allocator.free(self.page_info_text);

        self.reload_indicator_timer.deinit();
        self.history.deinit();
        if (self.tmux_graphics != null) {
            if (self.retired_image) |image_id| Tmux.freeImage(self.tty.writer(), image_id);
            if (self.current_page) |image| Tmux.freeImage(self.tty.writer(), image.id);
        }
        self.cache.deinit();
        self.document_handler.deinit();
        if (self.config.general.progress_bar) self.tty.writer().writeAll("\x1b]9;4;0;0\x07") catch {};
        self.vx.deinit(self.allocator, self.tty.writer());
        if (self.tmux_graphics) |*graphics| graphics.deinit();
        self.tty.deinit();
        self.config.deinit();
        self.allocator.destroy(self.config);
        self.arena.deinit();
        self.allocator.free(self.buf);
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
        self.current_mode = .{ .view = ViewMode.init(self) };

        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };

        try loop.init();
        try loop.start();
        defer loop.stop();
        try self.vx.enterAltScreen(self.tty.writer());
        try self.vx.queryTerminal(self.tty.writer(), 1 * std.time.ns_per_s);
        if (self.tmux_graphics) |*graphics| try graphics.probe(&self.vx, self.tty.writer());
        try self.vx.setMouseMode(self.tty.writer(), true);
        var ticker: Ticker = .{ .loop = &loop };
        if (self.tmux_graphics != null) ticker.thread = try std.Thread.spawn(.{}, Ticker.run, .{&ticker});
        defer ticker.deinit();

        if (self.config.file_monitor.enabled) {
            if (self.watcher) |*w| {
                w.setCallback(callback, &loop);
                self.watcher_thread = try std.Thread.spawn(.{}, watcherWorker, .{ self, w });
                self.current_reload_indicator_state = .watching;
                if (self.config.file_monitor.reload_indicator_duration > 0) {
                    var need_reload_indicator = self.config.general.progress_bar;
                    if (!need_reload_indicator and self.config.status_bar.enabled) {
                        for (self.config.status_bar.items) |item| {
                            if (item == .reload_aware) {
                                need_reload_indicator = true;
                                break;
                            }
                        }
                    }
                    if (need_reload_indicator) {
                        try self.reload_indicator_timer.start(&loop);
                        self.reload_indicator_active = true;
                    }
                }
            }
        }

        while (!self.should_quit) {
            loop.pollEvent();

            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            if (self.should_quit) break;
            if (self.pending_resize) |geometry| {
                // Keep the old tmux grid while a drag is in progress. The ticker
                // wakes us after the last resize without blocking input.
                if (std.time.milliTimestamp() - self.resize_at < 150) continue;
                try self.vx.resize(self.allocator, self.tty.writer(), geometry);
                self.pending_resize = null;
                self.cache.clear();
                self.reload_page = true;
            }
            if (self.tmux_graphics != null and !self.graphics_visible) continue;
            self.draw() catch |err| {
                if (self.tmux_graphics != null and (err == error.GraphicsTransmissionFailed or err == error.GraphicsPlacementFailed)) {
                    self.reload_page = true;
                    continue; // focus/redraw can temporarily route replies elsewhere
                }
                return err;
            };

            var buffered = self.tty.writer();
            try self.vx.render(buffered);
            try buffered.flush();
            if (self.retired_image) |image_id| {
                // New placeholder cells are now delivered; deleting the old
                // image before this point produces a visible blank frame.
                Tmux.freeImage(buffered, image_id);
                try buffered.flush();
                self.retired_image = null;
            }
            if (self.tmux_graphics != null and self.image_changed) {
                Tmux.refresh(self.allocator);
                self.image_changed = false;
                std.Thread.sleep(100 * std.time.ns_per_ms);
            }

            _ = self.arena.reset(.retain_capacity); // clear key actions from heap
        }
    }

    pub fn changeMode(self: *Self, new_state: ModeType) void {
        switch (self.current_mode) {
            .command => |*state| state.deinit(),
            .view => {},
        }

        switch (new_state) {
            .view => self.current_mode = .{ .view = ViewMode.init(self) },
            .command => self.current_mode = .{ .command = CommandMode.init(self) },
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
            self.should_quit = true;
            return;
        }

        try switch (self.current_mode) {
            .view => |*state| state.handleKeyStroke(key, km),
            .command => |*state| state.handleKeyStroke(key, km),
        };
    }

    pub fn update(self: *Self, event: Event) !void {
        switch (event) {
            .key_press => |key| try self.handleKeyStroke(key),
            .mouse => |mouse| self.mouse = mouse,
            .graphics_response => {},
            .graphics_tick => {
                const output = std.process.Child.run(.{ .allocator = self.allocator, .argv = &.{ "tmux", "display-message", "-p", "-t", std.posix.getenv("TMUX_PANE") orelse "", "#{window_active} #{session_attached} #{pane_active}" } }) catch return;
                defer self.allocator.free(output.stdout);
                defer self.allocator.free(output.stderr);
                const visible = std.mem.startsWith(u8, output.stdout, "1 ") and !std.mem.startsWith(u8, output.stdout, "1 0") and std.mem.endsWith(u8, std.mem.trim(u8, output.stdout, "\r\n"), " 1");
                if (visible and !self.graphics_visible) {
                    // A client may have detached/re-attached or a hidden PDF may
                    // have changed. Re-send; don't assume its image store survived.
                    self.reload_page = true;
                    self.vx.queueRefresh();
                }
                self.graphics_visible = visible;
            },
            .winsize => |ws| {
                var geometry = ws;
                if (self.tmux_graphics != null and (geometry.x_pixel == 0 or geometry.y_pixel == 0)) {
                    var cell_w: u16 = 8;
                    var cell_h: u16 = 16;
                    const result = std.process.Child.run(.{ .allocator = self.allocator, .argv = &.{ "tmux", "display-message", "-p", "#{client_cell_width} #{client_cell_height}" } }) catch null;
                    if (result) |output| {
                        defer self.allocator.free(output.stdout);
                        defer self.allocator.free(output.stderr);
                        var parts = std.mem.tokenizeAny(u8, output.stdout, " \r\n");
                        if (parts.next()) |part| cell_w = std.fmt.parseInt(u16, part, 10) catch 8;
                        if (parts.next()) |part| cell_h = std.fmt.parseInt(u16, part, 10) catch 16;
                    }
                    geometry.x_pixel = geometry.cols *| @max(cell_w, 1);
                    geometry.y_pixel = geometry.rows *| @max(cell_h, 1);
                }
                if (self.tmux_graphics != null and self.current_page != null) {
                    self.pending_resize = geometry;
                    self.resize_at = std.time.milliTimestamp();
                } else {
                    try self.vx.resize(self.allocator, self.tty.writer(), geometry);
                    self.cache.clear();
                    self.reload_page = true;
                }
            },
            .file_changed => {
                try self.document_handler.reloadDocument();
                self.cache.clear();
                self.reload_page = true;
                if (self.reload_indicator_active) {
                    if (self.config.general.progress_bar) try self.tty.writer().print("\x1b]9;4;1;100\x07", .{});
                    self.current_reload_indicator_state = .reload;
                    self.reload_indicator_timer.notifyChange();
                }
            },
            .reload_done => {
                if (self.config.general.progress_bar) try self.tty.writer().print("\x1b]9;4;0;0\x07", .{});
                self.current_reload_indicator_state = .watching;
            },
        }
    }

    pub fn getPage(
        self: *Self,
        page_number: u16,
        window_width: u32,
        window_height: u32,
    ) !vaxis.Image {
        const cache_key = Cache.Key{
            .colorize = self.config.general.colorize,
            .page = page_number,
            .width_mode = self.document_handler.getWidthMode(),

            // Scale zoom and position as integers with three digits of precision for use in key
            .zoom = @as(u32, @intFromFloat(self.document_handler.getActiveZoom() * 1000.0)),
            .x_offset = @as(i32, @intFromFloat(self.document_handler.getXOffset() * 1000.0)),
            .y_offset = @as(i32, @intFromFloat(self.document_handler.getYOffset() * 1000.0)),
        };

        if (self.should_check_cache and self.tmux_graphics == null) {
            if (self.cache.get(cache_key)) |cached| {
                self.should_check_cache = false;
                return cached.image;
            }
        }

        const encoded_image = try self.document_handler.renderPage(
            page_number,
            window_width,
            window_height,
        );
        defer self.allocator.free(encoded_image.base64);

        if (self.tmux_graphics) |*graphics| {
            const image = try graphics.transmit(&self.vx, self.tty.writer(), encoded_image.base64, encoded_image.width, encoded_image.height);
            if (self.retired_image) |old_id| Tmux.freeImage(self.tty.writer(), old_id);
            if (self.current_page) |old| self.retired_image = old.id;
            return image;
        }

        const image = try self.vx.transmitPreEncodedImage(
            self.tty.writer(),
            encoded_image.base64,
            encoded_image.width,
            encoded_image.height,
            .rgb,
        );

        if (self.should_check_cache) {
            _ = try self.cache.put(cache_key, .{ .image = image });
            self.should_check_cache = false;
        }

        return image;
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
            } else {
                y_pix -|= 1 * pix_per_row;
            }

            self.current_page = try self.getPage(
                self.document_handler.getCurrentPageNumber(),
                x_pix,
                y_pix,
            );

            self.reload_page = false;
            self.image_changed = true;
        }

        if (self.current_page) |img| {
            const dims = try img.cellSize(win);
            const cols = if (self.tmux_graphics != null) @min(dims.cols, @min(win.width, 297)) else @min(dims.cols, win.width);
            const reserved_rows: u16 = if (self.config.status_bar.enabled) 2 else 1;
            const rows = if (self.tmux_graphics != null) @min(dims.rows, @min(win.height -| reserved_rows, 297)) else @min(dims.rows, win.height);
            const x_off = (win.width -| cols) / 2;
            var y_off = (win.height -| rows) / 2;
            if (self.config.status_bar.enabled) {
                y_off -|= 1; // room for status bar
            }
            const center = win.child(.{
                .x_off = x_off,
                .y_off = y_off,
                .width = cols,
                .height = rows,
            });
            if (self.tmux_graphics) |*graphics| {
                if (cols == 0 or rows == 0) return;
                if (self.image_changed) try graphics.place(&self.vx, self.tty.writer(), img, cols, rows);
                try graphics.draw(center, img.id);
            } else try img.draw(center, .{ .scale = .contain });
        }
    }

    pub fn drawStatusBar(self: *Self, win: vaxis.Window) !void {
        const arena = self.arena.allocator();
        defer _ = self.arena.reset(.retain_capacity);

        const status_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height -| 2,
            .width = win.width,
            .height = 1,
        });

        // Expand all items into styled sub-items
        var expanded_items = std.array_list.Managed(Config.StatusBar.StyledItem).init(arena);
        defer expanded_items.deinit();

        for (self.config.status_bar.items) |item| {
            switch (item) {
                .styled => |styled| {
                    try expandPlaceholders(&expanded_items, styled);
                },
                .mode_aware => |mode_aware| {
                    switch (self.current_mode) {
                        .view => try expandPlaceholders(&expanded_items, mode_aware.view),
                        .command => try expandPlaceholders(&expanded_items, mode_aware.command),
                    }
                },
                .reload_aware => |reload_aware| {
                    switch (self.current_reload_indicator_state) {
                        .idle => try expandPlaceholders(&expanded_items, reload_aware.idle),
                        .reload => try expandPlaceholders(&expanded_items, reload_aware.reload),
                        .watching => try expandPlaceholders(&expanded_items, reload_aware.watching),
                    }
                },
            }
        }

        const items = expanded_items.items;

        // Find the separator
        var separator_index: usize = items.len;
        for (items, 0..) |item, i| {
            if (std.mem.eql(u8, item.text, Config.StatusBar.SEPARATOR)) {
                separator_index = i;
                break;
            }
        }

        if (separator_index < items.len) {
            status_bar.fill(vaxis.Cell{ .style = items[separator_index].style });
        } else {
            status_bar.fill(vaxis.Cell{ .style = self.config.status_bar.style });
        }

        // Left side
        var left_col: usize = 0;
        for (0..separator_index) |i| {
            try self.drawStatusText(status_bar, items[i], &left_col, true, arena);
        }

        // Right side
        if (separator_index < items.len - 1) {
            var right_col: usize = win.width;
            for (0..(items.len - separator_index - 1)) |j| {
                try self.drawStatusText(status_bar, items[items.len - 1 - j], &right_col, false, arena);
            }
        }
    }

    fn expandPlaceholders(list: *std.array_list.Managed(Config.StatusBar.StyledItem), styled_text: Config.StatusBar.StyledItem) !void {
        const text = styled_text.text;
        var last_index: usize = 0;

        while (last_index < text.len) {
            const open = std.mem.indexOfScalarPos(u8, text, last_index, '<') orelse {
                if (last_index < text.len) {
                    try list.append(.{ .text = text[last_index..], .style = styled_text.style });
                }
                break;
            };

            if (open > last_index) {
                try list.append(.{ .text = text[last_index..open], .style = styled_text.style });
            }

            const close = std.mem.indexOfScalarPos(u8, text, open, '>') orelse {
                try list.append(.{ .text = text[open..], .style = styled_text.style });
                break;
            };

            try list.append(.{ .text = text[open .. close + 1], .style = styled_text.style });

            last_index = close + 1;
        }
    }

    fn drawStatusText(self: *Self, status_bar: vaxis.Window, item: Config.StatusBar.StyledItem, col_offset: *usize, left_aligned: bool, allocator: std.mem.Allocator) !void {
        var text = item.text;

        if (std.mem.eql(u8, text, Config.StatusBar.PATH)) {
            const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
            defer allocator.free(cwd);

            const full_path = try std.fs.cwd().realpathAlloc(allocator, self.document_handler.getPath());
            defer allocator.free(full_path);

            if (std.mem.startsWith(u8, full_path, cwd)) {
                var path = full_path[cwd.len..];
                if (path.len > 0 and path[0] == '/') path = path[1..];
                text = try std.fmt.allocPrint(allocator, "{s}", .{path}); // trim cwd
            } else if (std.posix.getenv("HOME")) |home| {
                if (std.mem.startsWith(u8, full_path, home)) {
                    var path = full_path[home.len..];
                    if (path.len > 0 and path[0] == '/') path = path[1..];
                    text = try std.fmt.allocPrint(allocator, "~/{s}", .{path});
                } else {
                    text = try std.fmt.allocPrint(allocator, "{s}", .{full_path});
                }
            } else {
                text = try std.fmt.allocPrint(allocator, "{s}", .{full_path});
            }
        } else if (std.mem.eql(u8, text, Config.StatusBar.PAGE)) {
            text = try std.fmt.allocPrint(allocator, "{}", .{self.document_handler.getCurrentPageNumber() + 1});
        } else if (std.mem.eql(u8, text, Config.StatusBar.TOTAL_PAGES)) {
            text = try std.fmt.allocPrint(allocator, "{}", .{self.document_handler.getTotalPages()});
        } else if (std.mem.eql(u8, text, Config.StatusBar.SEPARATOR)) {
            text = "";
        }

        const width = vaxis.gwidth.gwidth(text, .wcwidth);

        if (!left_aligned) col_offset.* -= width;

        _ = status_bar.print(
            &.{.{ .text = text, .style = item.style }},
            .{ .col_offset = @intCast(col_offset.*) },
        );

        if (left_aligned) col_offset.* += width;
    }

    pub fn draw(self: *Self) !void {
        const win = self.vx.window();
        win.clear();

        try self.drawCurrentPage(win);

        if (self.config.status_bar.enabled) {
            try self.drawStatusBar(win);
        }

        if (self.current_mode == .command) {
            self.current_mode.command.drawCommandBar(win);
        }
    }

    pub fn toggleFullScreen(self: *Self) void {
        self.config.status_bar.enabled = !self.config.status_bar.enabled;
    }
};
