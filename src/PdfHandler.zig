const Self = @This();
const std = @import("std");
const fastb64z = @import("fastb64z");
const vaxis = @import("vaxis");
const config = @import("config");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

pub const PdfError = error{
    FailedToCreateContext,
    FailedToOpenDocument,
    InvalidPageNumber,
};

pub const ScrollDirection = enum {
    Up,
    Down,
    Left,
    Right,
};

pub const EncodedImage = struct {
    base64: []const u8,
    width: u16,
    height: u16,
};

allocator: std.mem.Allocator,
ctx: [*c]c.fz_context,
doc: [*c]c.fz_document,
temp_doc: ?[*c]c.fz_document,
total_pages: u16,
current_page_number: u16,
path: []const u8,
zoom: f32,
size: f32,
y_offset: f32,
x_offset: f32,
width: f32,
height: f32,
colorize: bool,

pub fn init(allocator: std.mem.Allocator, path: []const u8, initial_page: ?u16) !Self {
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
        .size = 0,
        .y_offset = 0,
        .x_offset = 0,
        .width = 0,
        .height = 0,
        .colorize = config.General.colorize,
    };
}

pub fn deinit(self: *Self) void {
    if (self.temp_doc) |doc| c.fz_drop_document(self.ctx, doc);
    c.fz_drop_document(self.ctx, self.doc);
    c.fz_drop_context(self.ctx);
}

pub fn reloadDocument(self: *Self) !void {
    self.temp_doc = c.fz_open_document(self.ctx, self.path.ptr) orelse {
        std.debug.print("Failed to reload document\n", .{});
        return PdfError.FailedToOpenDocument;
    };
    // TODO check this more efficient
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
    allocator: std.mem.Allocator,
    window_width: u32,
    window_height: u32,
) !EncodedImage {
    const page = c.fz_load_page(self.ctx, self.doc, self.current_page_number);
    defer c.fz_drop_page(self.ctx, page);
    const bound = c.fz_bound_page(self.ctx, page);

    const scale: f32 = @min(
        @as(f32, @floatFromInt(window_width)) / bound.x1,
        @as(f32, @floatFromInt(window_height)) / bound.y1,
    );

    self.width = @as(f32, bound.x1);
    self.height = @as(f32, bound.y1);
    if (self.size == 0) self.size = scale * config.General.size;
    if (self.zoom == 0) self.zoom = self.size;

    const bbox = c.fz_make_irect(
        0,
        0,
        @intFromFloat(bound.x1 * self.size),
        @intFromFloat(bound.y1 * self.size),
    );
    const pix = c.fz_new_pixmap_with_bbox(self.ctx, c.fz_device_rgb(self.ctx), bbox, null, 0);
    defer c.fz_drop_pixmap(self.ctx, pix);
    c.fz_clear_pixmap_with_value(self.ctx, pix, 0xFF);

    self.zoom = @max(self.zoom, self.size);
    self.x_offset = @min(0, self.x_offset);
    self.y_offset = @min(0, self.y_offset);

    const bound_x_offset = bound.x1 - bound.x1 * (self.size / self.zoom);
    const bound_y_offset = bound.y1 - bound.y1 * (self.size / self.zoom);

    self.x_offset = @max(self.x_offset, -bound_x_offset);
    self.y_offset = @max(self.y_offset, -bound_y_offset);

    var ctm = c.fz_scale(self.zoom, self.zoom);
    ctm = c.fz_pre_translate(ctm, self.x_offset, self.y_offset);

    const dev = c.fz_new_draw_device(self.ctx, ctm, pix);
    defer c.fz_drop_device(self.ctx, dev);
    c.fz_run_page(self.ctx, page, dev, c.fz_identity, null);
    c.fz_close_device(self.ctx, dev);

    if (self.colorize) {
        c.fz_tint_pixmap(self.ctx, pix, config.General.black, config.General.white);
    } else {
        c.fz_tint_pixmap(self.ctx, pix, 0x000000, 0xffffff);
    }

    const width = bbox.x1;
    const height = bbox.y1;
    const samples = c.fz_pixmap_samples(self.ctx, pix);

    var img = try vaxis.zigimg.Image.fromRawPixels(
        allocator,
        @intCast(width),
        @intCast(height),
        samples[0..@intCast(width * height * 3)],
        .rgb24,
    );
    defer img.deinit();

    try img.convert(.rgb24);
    const buf = img.rawBytes();

    const base64Encoder = fastb64z.standard.Encoder;
    const b64_buf = try self.allocator.alloc(u8, base64Encoder.calcSize(buf.len));

    const encoded = base64Encoder.encode(b64_buf, buf);

    return .{
        .base64 = encoded,
        .width = @intCast(img.width),
        .height = @intCast(img.height),
    };
}

pub fn changePage(self: *Self, delta: i32) bool {
    const new_page = @as(i32, @intCast(self.current_page_number)) + delta;
    const valid_page = new_page >= 0 and new_page < self.total_pages;

    if (valid_page) {
        self.current_page_number = @as(u16, @intCast(new_page));
        return true;
    }
    return false;
}

pub fn adjustZoom(self: *Self, increase: bool) void {
    const factor = self.size * config.General.zoom_step / 2;
    if (increase) {
        self.zoom *= (config.General.zoom_step + 1);
        self.x_offset -= factor * self.width / self.zoom;
        self.y_offset -= factor * self.height / self.zoom;
    } else {
        self.x_offset += factor * self.width / self.zoom;
        self.y_offset += factor * self.height / self.zoom;
        self.zoom /= (config.General.zoom_step + 1);
    }
}

pub fn toggleColor(self: *Self) void {
    self.colorize = !self.colorize;
}

pub fn scroll(self: *Self, direction: ScrollDirection) void {
    const step = config.General.scroll_step / self.zoom;
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
    self.size = 0;
    self.zoom = 0;
    self.y_offset = 0;
    self.x_offset = 0;
}
