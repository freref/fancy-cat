const Self = @This();
const std = @import("std");
const Config = @import("config/Config.zig");

pub const Key = struct { colorize: bool, page: u16 };
pub const EncodedImage = struct { base64: []const u8, width: u16, height: u16, cached: bool };

allocator: std.mem.Allocator,
pages: std.AutoHashMap(Key, EncodedImage),
order: std.ArrayList(Key),
config: Config,
max_pages: usize,

pub fn init(allocator: std.mem.Allocator, config: Config) Self {
    return .{
        .allocator = allocator,
        .pages = std.AutoHashMap(Key, EncodedImage).init(allocator),
        .order = std.ArrayList(Key).init(allocator),
        .config = config,
        .max_pages = config.cache.max_pages,
    };
}

pub fn deinit(self: *Self) void {
    var it = self.pages.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.value_ptr.base64);
    }
    self.pages.deinit();
    self.order.deinit();
}

pub fn get(self: *Self, key: Key) ?EncodedImage {
    return self.pages.get(key);
}

pub fn put(self: *Self, key: Key, image: EncodedImage) !bool {
    if (self.pages.contains(key)) return false;

    if (self.order.items.len >= self.max_pages) {
        const oldest_page = self.order.orderedRemove(0);
        if (self.pages.fetchRemove(oldest_page)) |entry| {
            self.allocator.free(entry.value.base64);
        }
    }

    try self.pages.put(key, image);
    try self.order.append(key);
    return true;
}
