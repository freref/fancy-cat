const Self = @This();
const std = @import("std");
const fastb64z = @import("fastb64z");
const vaxis = @import("vaxis");
const Config = @import("./config/Config.zig");
const Cache = @import("./Cache.zig");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

pub const EncodedImage = struct { base64: []const u8, width: u16, height: u16 };
pub const PdfError = error{ FailedToCreateContext, FailedToOpenDocument, InvalidPageNumber };
pub const ScrollDirection = enum { Up, Down, Left, Right };

allocator: std.mem.Allocator,
ctx: [*c]c.fz_context,
doc: [*c]c.fz_document,
temp_doc: ?[*c]c.fz_document,
total_pages: u16,
current_page_number: u16,
path: []const u8,
zoom: f32,
y_offset: f32,
x_offset: f32,
y_center: f32,
x_center: f32,
config: *Config,

pub fn init(
    allocator: std.mem.Allocator,
    path: []const u8,
    initial_page: ?u16,
    config: *Config,
) !Self {
    const ctx = c.fz_new_context(null, null, c.FZ_STORE_UNLIMITED) orelse {
        std.debug.print("Failed to create mupdf context\n", .{});
        return PdfError.FailedToCreateContext;
    };
    errdefer c.fz_drop_context(ctx);

    c.fz_register_document_handlers(ctx);
    c.fz_set_error_callback(ctx, null, null);
    c.fz_set_warning_callback(ctx, null, null);

    const doc = c.fz_open_document(ctx, path.ptr) orelse {
        const err_msg = c.fz_caught_message(ctx);
        std.debug.print("Failed to open document: {s}\n", .{err_msg});
        return PdfError.FailedToOpenDocument;
    };
    errdefer c.fz_drop_document(ctx, doc);

    const total_pages = @as(u16, @intCast(c.fz_count_pages(ctx, doc)));
    const current_page_number = if (initial_page) |page| blk: {
        if (page < 1 or page > total_pages) {
            return PdfError.InvalidPageNumber;
        }
        break :blk page - 1;
    } else 0;

    return .{
        .allocator = allocator,
        .ctx = ctx,
        .doc = doc,
        .temp_doc = null,
        .total_pages = total_pages,
        .current_page_number = current_page_number,
        .path = path,
        .zoom = 0,
        .y_offset = 0,
        .x_offset = 0,
        .y_center = 0,
        .x_center = 0,
        .config = config,
    };
}

pub fn deinit(self: *Self) void {
    if (self.temp_doc) |doc| c.fz_drop_document(self.ctx, doc);
    c.fz_drop_document(self.ctx, self.doc);
    c.fz_drop_context(self.ctx);
}

pub fn reloadDocument(self: *Self) !void {
    if (self.temp_doc) |doc| {
        c.fz_drop_document(self.ctx, doc);
        self.temp_doc = null;
    }

    self.temp_doc = c.fz_open_document(self.ctx, self.path.ptr) orelse {
        std.debug.print("Failed to reload document\n", .{});
        return PdfError.FailedToOpenDocument;
    };

    self.total_pages = @as(u16, @intCast(c.fz_count_pages(self.ctx, self.temp_doc.?)));
    if (self.current_page_number >= self.total_pages) {
        self.current_page_number = self.total_pages - 1;
    }
}

pub fn commitReload(self: *Self) void {
    if (self.temp_doc) |doc| {
        c.fz_drop_document(self.ctx, self.doc);
        self.doc = doc;
        self.temp_doc = null;
    }
}

pub fn renderPage(
    self: *Self,
    page_number: u16,
    window_width: u32,
    window_height: u32,
) !EncodedImage {
    const page = c.fz_load_page(self.ctx, self.doc, page_number);
    defer c.fz_drop_page(self.ctx, page);
    const bound = c.fz_bound_page(self.ctx, page);

    const scale: f32 = @min(
        @as(f32, @floatFromInt(window_width)) / bound.x1,
        @as(f32, @floatFromInt(window_height)) / bound.y1,
    );

    // initial zoom
    if (self.zoom == 0) {
        self.zoom = scale * self.config.general.size;
    }

    self.zoom = @max(self.zoom, self.config.general.zoom_min);

    // document view
    const view_width = @max(1, @min(self.zoom * bound.x1, @as(f32, @floatFromInt(window_width))));
    const view_height = @max(1, @min(self.zoom * bound.y1, @as(f32, @floatFromInt(window_height))));

    // translation to center view
    self.x_center = (bound.x1 - view_width / self.zoom) / 2;
    self.y_center = (bound.y1 - view_height / self.zoom) / 2;

    // don't scroll off page
    self.x_offset = c.fz_clamp(self.x_offset, -self.x_center, self.x_center);
    self.y_offset = c.fz_clamp(self.y_offset, -self.y_center, self.y_center);

    const bbox = c.fz_make_irect(
        0,
        0,
        @intFromFloat(view_width),
        @intFromFloat(view_height),
    );
    const pix = c.fz_new_pixmap_with_bbox(self.ctx, c.fz_device_rgb(self.ctx), bbox, null, 0);
    defer c.fz_drop_pixmap(self.ctx, pix);
    c.fz_clear_pixmap_with_value(self.ctx, pix, 0xFF);

    var ctm = c.fz_scale(self.zoom, self.zoom);
    ctm = c.fz_pre_translate(ctm, self.x_offset - self.x_center, self.y_offset - self.y_center);

    const dev = c.fz_new_draw_device(self.ctx, ctm, pix);
    defer c.fz_drop_device(self.ctx, dev);
    c.fz_run_page(self.ctx, page, dev, c.fz_identity, null);
    c.fz_close_device(self.ctx, dev);

    if (self.config.general.colorize) {
        c.fz_tint_pixmap(self.ctx, pix, self.config.general.black, self.config.general.white);
    }

    const width = @as(usize, @intCast(@abs(bbox.x1)));
    const height = @as(usize, @intCast(@abs(bbox.y1)));
    const samples = c.fz_pixmap_samples(self.ctx, pix);

    const base64Encoder = fastb64z.standard.Encoder;
    const sample_count = width * height * 3;

    const b64_buf = try self.allocator.alloc(u8, base64Encoder.calcSize(sample_count));
    const encoded = base64Encoder.encode(b64_buf, samples[0..sample_count]);

    return EncodedImage{
        .base64 = encoded,
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

pub fn changePage(self: *Self, delta: i32) bool {
    const new_page = @as(i32, @intCast(self.current_page_number)) + delta;

    if (new_page >= 0 and new_page < self.total_pages) {
        self.current_page_number = @as(u16, @intCast(new_page));
        return true;
    }
    return false;
}

pub fn adjustZoom(self: *Self, increase: bool) void {
    if (increase) {
        self.zoom *= (self.config.general.zoom_step + 1);
    } else {
        self.zoom /= (self.config.general.zoom_step + 1);
    }
}

pub fn toggleColor(self: *Self) void {
    self.config.general.colorize = !self.config.general.colorize;
}

pub fn scroll(self: *Self, direction: ScrollDirection) void {
    const step = self.config.general.scroll_step / self.zoom;
    switch (direction) {
        .Up => {
            const translation = self.y_offset + step;
            if (self.y_offset < translation) {
                self.y_offset = translation;
            } else {
                self.y_offset = std.math.nextAfter(f32, self.y_offset, std.math.inf(f32));
            }
        },
        .Down => {
            const translation = self.y_offset - step;
            if (self.y_offset > translation) {
                self.y_offset = translation;
            } else {
                self.y_offset = std.math.nextAfter(f32, self.y_offset, -std.math.inf(f32));
            }
        },
        .Left => {
            const translation = self.x_offset + step;
            if (self.x_offset < translation) {
                self.x_offset = translation;
            } else {
                self.x_offset = std.math.nextAfter(f32, self.x_offset, std.math.inf(f32));
            }
        },
        .Right => {
            const translation = self.x_offset - step;
            if (self.x_offset > translation) {
                self.x_offset = translation;
            } else {
                self.x_offset = std.math.nextAfter(f32, self.x_offset, -std.math.inf(f32));
            }
        },
    }
}

pub fn resetZoomAndScroll(self: *Self) void {
    self.zoom = 0;
    self.y_offset = 0;
    self.x_offset = 0;
}

pub fn goToPage(self: *Self, pageNum: u16) bool {
    if (pageNum >= 1 and pageNum <= self.total_pages and pageNum != self.current_page_number + 1) {
        self.current_page_number = @as(u16, @intCast(pageNum)) - 1;
        return true;
    }
    return false;
}
