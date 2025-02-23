const Self = @This();
const std = @import("std");
const Config = @import("config/Config.zig");

pub const Key = struct { colorize: bool, page: u16 };
pub const EncodedImage = struct { base64: []const u8, width: u16, height: u16, cached: bool };

const Node = struct {
    key: Key,
    value: EncodedImage,
    prev: ?*Node,
    next: ?*Node,
};

allocator: std.mem.Allocator,
map: std.AutoHashMap(Key, *Node),
head: ?*Node,
tail: ?*Node,
config: Config,
max_pages: usize,
mutex: std.Thread.Mutex,

pub fn init(allocator: std.mem.Allocator, config: Config) Self {
    return .{
        .allocator = allocator,
        .map = std.AutoHashMap(Key, *Node).init(allocator),
        .head = null,
        .tail = null,
        .config = config,
        .max_pages = config.cache.max_pages,
        .mutex = .{},
    };
}

pub fn deinit(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    var current = self.head;
    while (current) |node| {
        const next = node.next;
        self.allocator.free(node.value.base64);
        self.allocator.destroy(node);
        current = next;
    }
    self.map.deinit();
}

pub fn clear(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    var current = self.head;
    while (current) |node| {
        const next = node.next;
        self.allocator.free(node.value.base64);
        self.allocator.destroy(node);
        current = next;
    }

    self.map.clearRetainingCapacity();
    self.head = null;
    self.tail = null;
}

pub fn get(self: *Self, key: Key) ?EncodedImage {
    self.mutex.lock();
    defer self.mutex.unlock();
    const node = self.map.get(key) orelse return null;
    self.moveToFront(node);
    return node.value;
}

pub fn put(self: *Self, key: Key, image: EncodedImage) !bool {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.map.get(key)) |node| {
        self.moveToFront(node);
        return false;
    }

    const new_node = try self.allocator.create(Node);
    new_node.* = .{
        .key = key,
        .value = image,
        .prev = null,
        .next = null,
    };

    try self.map.put(key, new_node);
    self.addToFront(new_node);

    if (self.map.count() > self.max_pages) {
        const tail_node = self.tail orelse unreachable;
        _ = self.map.remove(tail_node.key);
        self.removeNode(tail_node);
        self.allocator.free(tail_node.value.base64);
        self.allocator.destroy(tail_node);
    }

    return true;
}

fn addToFront(self: *Self, node: *Node) void {
    node.next = self.head;
    node.prev = null;

    if (self.head) |head| {
        head.prev = node;
    } else {
        self.tail = node;
    }

    self.head = node;
}

fn removeNode(self: *Self, node: *Node) void {
    if (node.prev) |prev| {
        prev.next = node.next;
    } else {
        self.head = node.next;
    }

    if (node.next) |next| {
        next.prev = node.prev;
    } else {
        self.tail = node.prev;
    }
}

fn moveToFront(self: *Self, node: *Node) void {
    if (self.head == node) return;
    self.removeNode(node);
    self.addToFront(node);
}
