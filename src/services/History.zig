const Self = @This();
const std = @import("std");
const Config = @import("../config/Config.zig");

allocator: std.mem.Allocator,
config: *Config,
items: std.ArrayList([]const u8),
index: isize,

pub fn init(allocator: std.mem.Allocator, config: *Config) Self {
    var self = Self{
        .allocator = allocator,
        .config = config,
        .items = .{},
        .index = -1,
    };

    if (config.general.history <= 0) return self;

    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return self;
    defer allocator.free(home);

    var history_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const history_path = std.fmt.bufPrint(&history_path_buf, "{s}/.local/state/fancy-cat/history.txt", .{home}) catch return self;

    const file = std.fs.openFileAbsolute(history_path, .{ .mode = .read_only }) catch return self;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return self;
    defer allocator.free(content);

    var line = std.mem.tokenizeScalar(u8, content, '\n');
    while (line.next()) |cmd| {
        const cmd_copy = allocator.dupe(u8, cmd) catch continue;
        self.items.append(allocator, cmd_copy) catch {
            allocator.free(cmd_copy);
            continue;
        };
    }

    return self;
}

pub fn deinit(self: *Self) void {
    defer {
        for (self.items.items) |entry| {
            self.allocator.free(entry);
        }
        self.items.deinit(self.allocator);
    }

    if (self.config.general.history <= 0) return;

    const home = std.process.getEnvVarOwned(self.allocator, "HOME") catch return;
    defer self.allocator.free(home);

    var history_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const history_dir = std.fmt.bufPrint(&history_dir_buf, "{s}/.local/state/fancy-cat", .{home}) catch return;

    std.fs.makeDirAbsolute(history_dir) catch |err| {
        if (err != error.PathAlreadyExists) return;
    };

    var history_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const history_path = std.fmt.bufPrint(&history_path_buf, "{s}/history.txt", .{history_dir}) catch return;

    const file = std.fs.createFileAbsolute(history_path, .{}) catch return;
    defer file.close();

    for (self.items.items) |cmd| {
        file.writeAll(cmd) catch continue;
        file.writeAll("\n") catch continue;
    }
}

pub fn addToHistory(self: *Self, cmd: []const u8) void {
    if (self.config.general.history <= 0) return;

    for (self.items.items, 0..) |existing_cmd, i| {
        if (std.mem.eql(u8, existing_cmd, cmd)) {
            self.allocator.free(self.items.orderedRemove(i));
            break;
        }
    }

    const cmd_copy = self.allocator.dupe(u8, cmd) catch return;
    self.items.append(self.allocator, cmd_copy) catch {
        self.allocator.free(cmd_copy);
        return;
    };

    const max: usize = self.config.general.history;
    while (self.items.items.len > max) {
        const removed = self.items.orderedRemove(0);
        self.allocator.free(removed);
    }

    self.index = -1;
}
