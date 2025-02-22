const Self = @This();
const std = @import("std");
const Config = @import("config/Config.zig");

pub const EncodedImage = struct { base64: []const u8, width: u16, height: u16, cached: bool };

allocator: std.mem.Allocator,
entries: std.AutoHashMap(u16, EncodedImage),
order: std.ArrayList(u16),
config: Config,
max_pages: usize,

pub fn init(allocator: std.mem.Allocator, config: Config) Self {
    return .{
        .allocator = allocator,
        .entries = std.AutoHashMap(u16, EncodedImage).init(allocator),
        .order = std.ArrayList(u16).init(allocator),
        .config = config,
        .max_pages = config.cache.max_pages,
    };
}

pub fn deinit(self: *Self) void {
    var it = self.entries.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.value_ptr.base64);
    }
    self.entries.deinit();
    self.order.deinit();
}

pub fn get(self: *Self, page: u16) ?EncodedImage {
    return self.entries.get(page);
}

pub fn put(self: *Self, page: u16, image: EncodedImage) !bool {
    if (self.entries.contains(page)) return false;

    if (self.order.items.len >= self.max_pages) {
        const oldest_page = self.order.orderedRemove(0);
        if (self.entries.fetchRemove(oldest_page)) |entry| {
            self.allocator.free(entry.value.base64);
        }
    }

    try self.entries.put(page, image);
    try self.order.append(page);
    return true;
}

pub fn has(self: *Self, page: u16) bool {
    return self.entries.contains(page);
}
