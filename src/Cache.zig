const Self = @This();
const std = @import("std");
const Config = @import("config/Config.zig");
const vaxis = @import("vaxis");

pub const Key = struct { colorize: bool, page: u16 };
pub const CachedImage = struct { image: vaxis.Image };

const Node = struct {
    key: Key,
    value: CachedImage,
    prev: ?*Node,
    next: ?*Node,
};

allocator: std.mem.Allocator,
map: std.AutoHashMap(Key, *Node),
head: ?*Node,
tail: ?*Node,
config: *Config,
lru_size: usize,
mutex: std.Thread.Mutex,

pub fn init(allocator: std.mem.Allocator, config: *Config) Self {
    return .{
        .allocator = allocator,
        .map = std.AutoHashMap(Key, *Node).init(allocator),
        .head = null,
        .tail = null,
        .config = config,
        .lru_size = config.cache.lru_size,
        .mutex = .{},
    };
}

pub fn deinit(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    var current = self.head;
    while (current) |node| {
        const next = node.next;
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
        // TODO clear the image from the terminal everywhere
        // Currently assuming the terminal takes care of it somewhat
        //self.vx.freeImage(self.tty.anyWriter(), node.value.image.id);
        const next = node.next;
        self.allocator.destroy(node);
        current = next;
    }

    self.map.clearRetainingCapacity();
    self.head = null;
    self.tail = null;
}

pub fn get(self: *Self, key: Key) ?CachedImage {
    self.mutex.lock();
    defer self.mutex.unlock();
    const node = self.map.get(key) orelse return null;
    self.moveToFront(node);
    return node.value;
}

pub fn put(self: *Self, key: Key, image: CachedImage) !bool {
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

    if (self.map.count() > self.lru_size) {
        const tail_node = self.tail orelse unreachable;
        _ = self.map.remove(tail_node.key);
        self.removeNode(tail_node);
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
