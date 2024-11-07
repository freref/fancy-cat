const std = @import("std");
const vaxis = @import("vaxis");
const fzwatch = @import("fzwatch");
const config = @import("config");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

pub const panic = vaxis.panic_handler;

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    file_changed,
};

pub const FileReader = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    current_page_number: u16,
    path: []const u8,
    ctx: [*c]c.fz_context,
    doc: [*c]c.fz_document,
    temp_doc: ?[*c]c.fz_document,
    total_pages: u16,
    current_page: ?vaxis.Image,
    watcher: ?fzwatch.Watcher,
    thread: ?std.Thread,

    pub fn init(allocator: std.mem.Allocator, args: [][]const u8) !FileReader {
        const ctx = c.fz_new_context(null, null, c.FZ_STORE_UNLIMITED) orelse {
            std.debug.print("Failed to create mupdf context\n", .{});
            return error.FailedToCreateContext;
        };
        errdefer c.fz_drop_context(ctx);
        c.fz_register_document_handlers(ctx);
        // XXX figure out errors instead of ignoring them lol
        c.fz_set_error_callback(ctx, null, null);
        c.fz_set_warning_callback(ctx, null, null);

        const path = args[1];
        const doc = c.fz_open_document(ctx, path.ptr) orelse {
            const err_msg = c.fz_caught_message(ctx);
            std.debug.print("Failed to open document: {s}\n", .{err_msg});
            return error.FailedToOpenDocument;
        };
        errdefer c.fz_drop_document(ctx, doc);

        const total_pages = @as(u16, @intCast(c.fz_count_pages(ctx, doc)));
        const current_page_number = blk: {
            if (args.len == 3) {
                const page = try std.fmt.parseInt(u16, args[2], 10);
                if (page < 1 or page > total_pages) {
                    const stderr = std.io.getStdErr().writer();
                    try stderr.writeAll("Invalid page number\n");
                    return error.InvalidPageNumber;
                }
                break :blk page - 1;
            }
            break :blk 0;
        };

        var watcher: ?fzwatch.Watcher = null;
        if (config.FileMonitor.enabled) {
            watcher = try fzwatch.Watcher.init(allocator);
            if (watcher) |*w| try w.addFile(path);
        }

        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .current_page_number = current_page_number,
            .path = path,
            .ctx = ctx,
            .doc = doc,
            .total_pages = total_pages,
            .watcher = watcher,
            .current_page = null,
            .temp_doc = null,
            .mouse = null,
            .thread = null,
        };
    }

    pub fn deinit(self: *FileReader) void {
        if (self.watcher) |*w| w.deinit();
        if (self.current_page) |img| self.vx.freeImage(self.tty.anyWriter(), img.id);
        if (self.temp_doc) |doc| c.fz_drop_document(self.ctx, doc);
        c.fz_drop_document(self.ctx, self.doc);
        c.fz_drop_context(self.ctx);
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

    fn watcherThread(watcher: *fzwatch.Watcher) !void {
        try watcher.start(.{ .latency = config.FileMonitor.latency });
    }

    pub fn run(self: *FileReader) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();
        try loop.start();
        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 1 * std.time.ns_per_s);
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        if (config.FileMonitor.enabled) {
            if (self.watcher) |*w| {
                w.setCallback(callback, &loop);
                self.thread = try std.Thread.spawn(.{}, watcherThread, .{w});
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

    fn handleKeyStroke(self: *FileReader, key: vaxis.Key) !void {
        if (key.matches(config.KeyMap.quit.key, config.KeyMap.quit.modifiers)) {
            self.should_quit = true;
        } else if (key.matches(config.KeyMap.next.key, config.KeyMap.next.modifiers)) {
            if (self.current_page_number < self.total_pages - 1) {
                self.current_page_number += 1;
                if (self.current_page) |img| {
                    self.vx.freeImage(self.tty.anyWriter(), img.id);
                    self.current_page = null;
                }
            }
        } else if (key.matches(config.KeyMap.prev.key, config.KeyMap.prev.modifiers)) {
            if (self.current_page_number > 0) {
                self.current_page_number -= 1;
                if (self.current_page) |img| {
                    self.vx.freeImage(self.tty.anyWriter(), img.id);
                    self.current_page = null;
                }
            }
        }
    }

    pub fn update(self: *FileReader, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                try self.handleKeyStroke(key);
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            .file_changed => {
                self.temp_doc = c.fz_open_document(self.ctx, self.path.ptr) orelse {
                    std.debug.print("Failed to reload document\n", .{});
                    return;
                };
                // XXX check if this can be done more efficient rather than check on every file change
                // probably check if file attribute has changed
                self.total_pages = @as(u16, @intCast(c.fz_count_pages(self.ctx, self.temp_doc.?)));
            },
        }
    }

    pub fn draw(self: *FileReader) !void {
        const win = self.vx.window();
        win.clear();

        if (self.temp_doc) |doc| {
            self.doc = doc;
            self.temp_doc = null;
            self.current_page = null;
        }

        if (self.current_page == null) {
            var ctm = c.fz_scale(1.5, 1.5);
            ctm = c.fz_pre_translate(ctm, 0, 0);
            ctm = c.fz_pre_rotate(ctm, 0);

            const pix = c.fz_new_pixmap_from_page_number(
                self.ctx,
                self.doc,
                self.current_page_number,
                ctm,
                c.fz_device_rgb(self.ctx),
                0,
            ) orelse return error.PixmapCreationFailed;
            defer c.fz_drop_pixmap(self.ctx, pix);

            const width = c.fz_pixmap_width(self.ctx, pix);
            const height = c.fz_pixmap_height(self.ctx, pix);
            const samples = c.fz_pixmap_samples(self.ctx, pix);

            var img = try vaxis.zigimg.Image.fromRawPixels(
                self.allocator,
                @intCast(width),
                @intCast(height),
                samples[0..@intCast(width * height * 3)],
                .rgb24,
            );
            defer img.deinit();

            self.current_page = try self.vx.transmitImage(
                self.allocator,
                self.tty.anyWriter(),
                &img,
                .rgb,
            );
        }

        if (self.current_page) |img| {
            const dims = try img.cellSize(win);
            const center = vaxis.widgets.alignment.center(win, dims.cols, dims.rows);
            try img.draw(center, .{ .scale = .contain });
        }
    }
};
