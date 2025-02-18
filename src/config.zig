const Self = @This();
const std = @import("std");
const vaxis = @import("vaxis");

pub const KeyBinding = struct {
    key: u8,
    modifiers: vaxis.Key.Modifiers,
};

// config
pub const KeyMap = struct {
    next: KeyBinding = .{ .key = 'n', .modifiers = .{} },
    prev: KeyBinding = .{ .key = 'p', .modifiers = .{} },
    scroll_up: KeyBinding = .{ .key = 'k', .modifiers = .{} },
    scroll_down: KeyBinding = .{ .key = 'j', .modifiers = .{} },
    scroll_left: KeyBinding = .{ .key = 'h', .modifiers = .{} },
    scroll_right: KeyBinding = .{ .key = 'l', .modifiers = .{} },
    zoom_in: KeyBinding = .{ .key = 'i', .modifiers = .{} },
    zoom_out: KeyBinding = .{ .key = 'o', .modifiers = .{} },
    colorize: KeyBinding = .{ .key = 'z', .modifiers = .{} },
    quit: KeyBinding = .{ .key = 'c', .modifiers = .{ .ctrl = true } },
};

/// File monitor will be used to watch for changes to files and rerender them
pub const FileMonitor = struct {
    enabled: bool = true,
    // Amount of time to wait inbetween polling for file changes
    latency: f16 = 0.1,
};

pub const General = struct {
    colorize: bool = false,
    white: i32 = 0x000000,
    black: i32 = 0xffffff,
    // size of the pdf
    // 1 is the whole screen
    size: f32 = 0.90,
    // percentage
    zoom_step: f32 = 0.25,
    // pixels
    scroll_step: f32 = 100.0,
};

pub const StatusBar = struct {
    // status bar shows the page numbers and file name
    pub const enabled: bool = true;
    pub const style = .{
        .bg = .{ .rgb = .{ 216, 74, 74 } },
        .fg = .{ .rgb = .{ 255, 255, 255 } },
    };
};

key_map: KeyMap,
file_monitor: FileMonitor,
general: General,
status_bar: StatusBar,

pub fn init(allocator: std.mem.Allocator) !Self {
    // XXX This seems like an odd way to do this (temp)
    var config_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    const config_path = try std.fmt.bufPrint(&config_path_buf, "{s}/.config/fancy-cat/config.json", .{home});
    defer if (home.len != 1) allocator.free(home);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch {
        return Self{
            .key_map = .{},
            .file_monitor = .{},
            .general = .{},
            .status_bar = .{},
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    return Self{
        .key_map = if (root.get("KeyMap")) |km| try parseKeyMap(km) else .{},
        .file_monitor = if (root.get("FileMonitor")) |fm| try parseFileMonitor(fm) else .{},
        .general = if (root.get("General")) |g| try parseGeneral(g) else .{},
        .status_bar = if (root.get("StatusBar")) |sb| try parseStatusBar(sb) else .{},
    };

    //.key_map = try parseKeyMap(root.get("KeyMap").?),
    //.file_monitor = try parseFileMonitor(root.get("FileMonitor").?),
    //.general = try parseGeneral(root.get("General").?),
    //.status_bar = try parseStatusBar(root.get("StatusBar").?),
}

fn parseKeyMap(value: std.json.Value) !KeyMap {
    _ = value;
    return KeyMap{};
}

fn parseKeyBinding(value: std.json.Value) !KeyBinding {
    _ = value;
    return KeyBinding{};
}

fn parseFileMonitor(value: std.json.Value) !FileMonitor {
    _ = value;
    return FileMonitor{};
}

fn parseGeneral(value: std.json.Value) !General {
    _ = value;
    return General{};
}

fn parseStatusBar(value: std.json.Value) !StatusBar {
    _ = value;

    return .{};
}
