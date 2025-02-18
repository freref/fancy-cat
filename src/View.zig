const Self = @This();
const std = @import("std");
const vaxis = @import("vaxis");
const fzwatch = @import("fzwatch");
const Config = @import("config/Config.zig");
const PdfHandler = @import("PdfHandler.zig");

pub const panic = vaxis.panic_handler;

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    file_changed,
};

allocator: std.mem.Allocator,
should_quit: bool,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
mouse: ?vaxis.Mouse,
pdf_handler: PdfHandler,
page_info_text: []u8,
current_page: ?vaxis.Image,
watcher: ?fzwatch.Watcher,
thread: ?std.Thread,
reload: bool,
config: Config,

pub fn init(allocator: std.mem.Allocator, args: [][]const u8) !Self {
    const path = args[1];
    const initial_page = if (args.len == 3)
        try std.fmt.parseInt(u16, args[2], 10)
    else
        null;

    const config = try Config.init(allocator);

    var pdf_handler = try PdfHandler.init(allocator, path, initial_page, config);
    errdefer pdf_handler.deinit();

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
        .pdf_handler = pdf_handler,
        .page_info_text = &[_]u8{},
        .current_page = null,
        .watcher = watcher,
        .mouse = null,
        .thread = null,
        .reload = false,
        .config = config,
    };
}

pub fn deinit(self: *Self) void {
    if (self.watcher) |*w| {
        w.stop();
        if (self.thread) |thread| thread.join();
        w.deinit();
    }
    if (self.page_info_text.len > 0) self.allocator.free(self.page_info_text);
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

fn watcherThread(self: *Self, watcher: *fzwatch.Watcher) !void {
    try watcher.start(.{ .latency = self.config.file_monitor.latency });
}

pub fn run(self: *Self) !void {
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

fn resetCurrentPage(self: *Self) void {
    if (self.current_page) |img| {
        self.vx.freeImage(self.tty.anyWriter(), img.id);
        self.current_page = null;
    }
}

fn handleKeyStroke(self: *Self, key: vaxis.Key) !void {
    const km = self.config.key_map;
    // non reload keys
    if (key.matches(km.quit.key, km.quit.modifiers)) {
        self.should_quit = true;
        return;
    }

    // reload keys
    if (key.matches(km.next.key, km.next.modifiers)) {
        if (self.pdf_handler.changePage(1)) {
            self.resetCurrentPage();
            self.pdf_handler.resetZoomAndScroll();
        }
    } else if (key.matches(km.prev.key, km.prev.modifiers)) {
        if (self.pdf_handler.changePage(-1)) {
            self.resetCurrentPage();
            self.pdf_handler.resetZoomAndScroll();
        }
    } else if (key.matches(km.zoom_in.key, km.zoom_in.modifiers)) {
        self.pdf_handler.adjustZoom(true);
    } else if (key.matches(km.zoom_out.key, km.zoom_out.modifiers)) {
        self.pdf_handler.adjustZoom(false);
    } else if (key.matches(km.scroll_up.key, km.scroll_up.modifiers)) {
        self.pdf_handler.scroll(.Up);
    } else if (key.matches(km.scroll_down.key, km.scroll_down.modifiers)) {
        self.pdf_handler.scroll(.Down);
    } else if (key.matches(km.scroll_left.key, km.scroll_left.modifiers)) {
        self.pdf_handler.scroll(.Left);
    } else if (key.matches(km.scroll_right.key, km.scroll_right.modifiers)) {
        self.pdf_handler.scroll(.Right);
    } else if (key.matches(km.colorize.key, km.colorize.modifiers)) {
        self.pdf_handler.toggleColor();
    }

    self.reload = true;
}

pub fn update(self: *Self, event: Event) !void {
    switch (event) {
        .key_press => |key| try self.handleKeyStroke(key),
        .mouse => |mouse| self.mouse = mouse,
        .winsize => |ws| {
            try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
            self.pdf_handler.resetZoomAndScroll();
            self.reload = true;
        },
        .file_changed => {
            try self.pdf_handler.reloadDocument();
            self.reload = true;
        },
    }
}

pub fn drawCurrentPage(self: *Self, win: vaxis.Window) !void {
    self.pdf_handler.commitReload();
    if (self.current_page == null or self.reload) {
        const winsize = try vaxis.Tty.getWinsize(self.tty.fd);
        const encoded_image = try self.pdf_handler.renderPage(
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
        &.{.{ .text = self.pdf_handler.path, .style = self.config.status_bar.style }},
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
        .{ .col_offset = @intCast(win.width - self.page_info_text.len - 1) },
    );
}

pub fn draw(self: *Self) !void {
    const win = self.vx.window();
    win.clear();

    try self.drawCurrentPage(win);
    if (self.config.status_bar.enabled) {
        try self.drawStatusBar(win);
    }
}
