const Self = @This();
const std = @import("std");

pub const EncodedImage = struct { base64: []const u8, width: u16, height: u16 };

allocator: std.mem.Allocator,
entries: std.AutoHashMap(u16, EncodedImage),
max_pages: usize = 10,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .entries = std.AutoHashMap(u16, EncodedImage).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.entries.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.value_ptr.base64);
    }
    self.entries.deinit();
}

pub fn get(self: *Self, page: u16) ?EncodedImage {
    return self.entries.get(page);
}

pub fn put(self: *Self, page: u16, image: EncodedImage) !void {
    try self.entries.put(page, image);
}
