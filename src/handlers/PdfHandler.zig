const Self = @This();
const std = @import("std");
const fastb64z = @import("fastb64z");
const vaxis = @import("vaxis");
const Config = @import("../config/Config.zig");
const types = @import("./types.zig");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

allocator: std.mem.Allocator,
ctx: [*c]c.fz_context,
doc: [*c]c.fz_document,
total_pages: u16,
path: []const u8,
active_zoom: f32,
default_zoom: f32,
width_mode: bool,
y_offset: f32,
x_offset: f32,
y_center: f32,
x_center: f32,
config: *Config,

pub fn init(
    allocator: std.mem.Allocator,
    path: []const u8,
    config: *Config,
) !Self {
    const ctx = c.fz_new_context(null, null, c.FZ_STORE_UNLIMITED) orelse {
        std.debug.print("Failed to create mupdf context\n", .{});
        return types.DocumentError.FailedToCreateContext;
    };
    errdefer c.fz_drop_context(ctx);

    c.fz_register_document_handlers(ctx);
    c.fz_set_error_callback(ctx, null, null);
    c.fz_set_warning_callback(ctx, null, null);

    const doc = c.fz_open_document(ctx, path.ptr) orelse {
        const err_msg = c.fz_caught_message(ctx);
        std.debug.print("Failed to open document: {s}\n", .{err_msg});
        return types.DocumentError.FailedToOpenDocument;
    };
    errdefer c.fz_drop_document(ctx, doc);

    const total_pages = @as(u16, @intCast(c.fz_count_pages(ctx, doc)));

    return .{
        .allocator = allocator,
        .ctx = ctx,
        .doc = doc,
        .total_pages = total_pages,
        .path = path,
        .active_zoom = 0,
        .default_zoom = 0,
        .width_mode = false,
        .y_offset = 0,
        .x_offset = 0,
        .y_center = 0,
        .x_center = 0,
        .config = config,
    };
}

pub fn deinit(self: *Self) void {
    c.fz_drop_document(self.ctx, self.doc);
    c.fz_drop_context(self.ctx);
}

pub fn reloadDocument(self: *Self) !void {
    if (self.doc) |doc| {
        c.fz_drop_document(self.ctx, doc);
        self.doc = null;
    }

    self.doc = c.fz_open_document(self.ctx, self.path.ptr) orelse {
        std.debug.print("Failed to reload document\n", .{});
        return types.DocumentError.FailedToOpenDocument;
    };

    self.total_pages = @as(u16, @intCast(c.fz_count_pages(self.ctx, self.doc.?)));
}

fn calculateZoomLevel(self: *Self, window_width: u32, window_height: u32, bound: c.fz_rect) void {
    var scale: f32 = 0;
    if (self.width_mode) {
        scale = @as(f32, @floatFromInt(window_width)) / bound.x1;
    } else {
        scale = @min(
            @as(f32, @floatFromInt(window_width)) / bound.x1,
            @as(f32, @floatFromInt(window_height)) / bound.y1,
        );
    }

    // initial zoom
    if (self.default_zoom == 0) {
        self.default_zoom = scale * self.config.general.size;
    }

    if (self.active_zoom == 0) {
        self.active_zoom = self.default_zoom;
    }

    self.active_zoom = @max(self.active_zoom, self.config.general.zoom_min);
}

fn calculateXY(self: *Self, view_width: f32, view_height: f32, bound: c.fz_rect) void {
    // translation to center view
    self.x_center = (bound.x1 - view_width / self.active_zoom) / 2;
    self.y_center = (bound.y1 - view_height / self.active_zoom) / 2;

    if (self.x_offset == 0 and self.y_offset == 0 and self.width_mode) {
        self.y_offset = self.y_center;
    }

    // don't scroll off page
    self.x_offset = c.fz_clamp(self.x_offset, -self.x_center, self.x_center);
    self.y_offset = c.fz_clamp(self.y_offset, -self.y_center, self.y_center);
}

pub fn renderPage(
    self: *Self,
    page_number: u16,
    window_width: u32,
    window_height: u32,
) !types.EncodedImage {
    const page = c.fz_load_page(self.ctx, self.doc, page_number);
    defer c.fz_drop_page(self.ctx, page);
    const bound = c.fz_bound_page(self.ctx, page);

    self.calculateZoomLevel(window_width, window_height, bound);

    // document view
    const view_width = @max(1, @min(
        self.active_zoom * bound.x1,
        @as(f32, @floatFromInt(window_width)),
    ));
    const view_height = @max(1, @min(
        self.active_zoom * bound.y1,
        @as(f32, @floatFromInt(window_height)),
    ));

    self.calculateXY(view_width, view_height, bound);

    const bbox = c.fz_make_irect(
        0,
        0,
        @intFromFloat(view_width),
        @intFromFloat(view_height),
    );
    const pix = c.fz_new_pixmap_with_bbox(self.ctx, c.fz_device_rgb(self.ctx), bbox, null, 0);
    defer c.fz_drop_pixmap(self.ctx, pix);
    c.fz_clear_pixmap_with_value(self.ctx, pix, 0xFF);

    var ctm = c.fz_scale(self.active_zoom, self.active_zoom);
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

    return types.EncodedImage{
        .base64 = encoded,
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

pub fn zoomIn(self: *Self) void {
    self.active_zoom *= self.config.general.zoom_step;
}

pub fn zoomOut(self: *Self) void {
    self.active_zoom /= self.config.general.zoom_step;
}

pub fn toggleColor(self: *Self) void {
    self.config.general.colorize = !self.config.general.colorize;
}

pub fn scroll(self: *Self, direction: types.ScrollDirection) void {
    const step = self.config.general.scroll_step / self.active_zoom;
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

pub fn resetDefaultZoom(self: *Self) void {
    self.default_zoom = 0;
}

pub fn resetZoomAndScroll(self: *Self) void {
    self.active_zoom = self.default_zoom;
    self.y_offset = 0;
    self.x_offset = 0;
}

pub fn toggleWidthMode(self: *Self) void {
    self.default_zoom = 0;
    self.active_zoom = 0;
    self.width_mode = !self.width_mode;
}
