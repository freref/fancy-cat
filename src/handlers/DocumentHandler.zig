const Self = @This();
const std = @import("std");
const Config = @import("../config/Config.zig");
const PdfHandler = @import("./PdfHandler.zig");
const types = @import("./types.zig");

pub const FileFormat = enum {
    pdf,
    // epub,

    pub fn fromPath(path: []const u8) !FileFormat {
        if (std.mem.endsWith(u8, path, ".pdf")) {
            return .pdf;
        } // else if (std.mem.endsWith(u8, path, ".epub")) {
        //     return .epub;
        // }
        return types.DocumentError.UnsupportedFileFormat;
    }
};

pdf_handler: PdfHandler,
current_page_number: u16,
file_format: FileFormat,

pub fn init(
    allocator: std.mem.Allocator,
    path: []const u8,
    initial_page: ?u16,
    config: *Config,
) !Self {
    // TODO use this for conditional rendering
    const format = try FileFormat.fromPath(path);

    var pdf_handler = try PdfHandler.init(allocator, path, config);
    errdefer pdf_handler.deinit();

    const current_page_number = if (initial_page) |page| blk: {
        if (page < 1 or page > pdf_handler.total_pages) {
            return types.DocumentError.InvalidPageNumber;
        }
        break :blk page - 1;
    } else 0;

    return .{
        .pdf_handler = pdf_handler,
        .current_page_number = current_page_number,
        .file_format = format,
    };
}

pub fn deinit(self: *Self) void {
    self.pdf_handler.deinit();
}

pub fn reloadDocument(self: *Self) !void {
    try self.pdf_handler.reloadDocument();
    if (self.current_page_number >= self.pdf_handler.total_pages) {
        self.current_page_number = self.pdf_handler.total_pages - 1;
    }
}

pub fn renderPage(
    self: *Self,
    page_number: u16,
    window_width: u32,
    window_height: u32,
) !types.EncodedImage {
    return try self.pdf_handler.renderPage(page_number, window_width, window_height);
}

pub fn zoomIn(self: *Self) void {
    self.pdf_handler.zoomIn();
}

pub fn zoomOut(self: *Self) void {
    self.pdf_handler.zoomOut();
}

pub fn toggleColor(self: *Self) void {
    self.pdf_handler.toggleColor();
}

pub fn scroll(self: *Self, direction: types.ScrollDirection) void {
    self.pdf_handler.scroll(direction);
}

pub fn resetDefaultZoom(self: *Self) void {
    self.pdf_handler.resetDefaultZoom();
}

pub fn resetZoomAndScroll(self: *Self) void {
    self.pdf_handler.resetZoomAndScroll();
}

pub fn toggleWidthMode(self: *Self) void {
    self.pdf_handler.toggleWidthMode();
}
pub fn goToPage(self: *Self, page_num: u16) bool {
    if (page_num >= 1 and page_num <= self.getTotalPages() and page_num != self.current_page_number + 1) {
        self.current_page_number = @as(u16, @intCast(page_num)) - 1;
        return true;
    }
    return false;
}
pub fn changePage(self: *Self, delta: i32) bool {
    const new_page = @as(i32, @intCast(self.current_page_number)) + delta;

    if (new_page >= 0 and new_page < self.getTotalPages()) {
        self.current_page_number = @as(u16, @intCast(new_page));
        return true;
    }
    return false;
}

// getters

pub fn getWidthMode(self: *Self) bool {
    return self.pdf_handler.getWidthMode();
}

pub fn getCurrentPageNumber(self: *Self) u16 {
    return self.current_page_number;
}

pub fn getPath(self: *Self) []const u8 {
    return self.pdf_handler.path;
}

pub fn getTotalPages(self: *Self) u16 {
    return self.pdf_handler.total_pages;
}

pub fn getActiveZoom(self: *Self) f32 {
    return self.pdf_handler.active_zoom;
}

pub fn getXOffset(self: *Self) f32 {
    return self.pdf_handler.x_offset;
}

pub fn getYOffset(self: *Self) f32 {
    return self.pdf_handler.y_offset;
}
