const Self = @This();
const std = @import("std");
const vaxis = @import("vaxis");

pub const KeyBinding = struct {
    key: u8,
    modifiers: vaxis.Key.Modifiers,
};

/// XXX There is a lot of redundancy, e.g the default values. Worth checking if its necessary
/// JSON parsing is also worth looking over again
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
    enabled: bool = true,
    style: vaxis.Cell.Style = .{
        .bg = .{ .rgb = .{ 216, 74, 74 } },
        .fg = .{ .rgb = .{ 255, 255, 255 } },
    },
};

key_map: KeyMap,
file_monitor: FileMonitor,
general: General,
status_bar: StatusBar,

pub fn init(allocator: std.mem.Allocator) !Self {
    // Create config file in ~/.config/fancy-cat/config.json
    const config_file = @embedFile("config.json");
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer if (home.len != 1) allocator.free(home);

    var config_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const config_dir = try std.fmt.bufPrint(&config_path_buf, "{s}/.config/fancy-cat", .{home});

    std.fs.makeDirAbsolute(config_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const config_path = try std.fmt.bufPrint(
        &config_path_buf,
        "{s}/.config/fancy-cat/config.json",
        .{home},
    );

    const file = blk: {
        if (std.fs.openFileAbsolute(config_path, .{})) |f| {
            break :blk f;
        } else |err| {
            if (err == error.FileNotFound) {
                const f = try std.fs.createFileAbsolute(config_path, .{});
                defer f.close();
                try f.writeAll(config_file);
                break :blk try std.fs.openFileAbsolute(config_path, .{});
            } else {
                return err;
            }
        }
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    return Self{
        .key_map = if (root.get("KeyMap")) |km| try parseKeyMap(km, allocator) else .{},
        .file_monitor = if (root.get("FileMonitor")) |fm| try parseFileMonitor(fm, allocator) else .{},
        .general = if (root.get("General")) |g| try parseGeneral(g, allocator) else .{},
        .status_bar = if (root.get("StatusBar")) |sb| try parseStatusBar(sb, allocator) else .{},
    };
}

fn parseKeyMap(value: std.json.Value, allocator: std.mem.Allocator) !KeyMap {
    const obj = value.object;

    return KeyMap{
        .next = try parseKeyBinding(obj.get("next"), allocator) orelse .{
            .key = 'n',
            .modifiers = .{},
        },
        .prev = try parseKeyBinding(obj.get("prev"), allocator) orelse .{
            .key = 'p',
            .modifiers = .{},
        },
        .scroll_up = try parseKeyBinding(obj.get("scroll_up"), allocator) orelse .{
            .key = 'k',
            .modifiers = .{},
        },
        .scroll_down = try parseKeyBinding(obj.get("scroll_down"), allocator) orelse .{
            .key = 'j',
            .modifiers = .{},
        },
        .scroll_left = try parseKeyBinding(obj.get("scroll_left"), allocator) orelse .{
            .key = 'h',
            .modifiers = .{},
        },
        .scroll_right = try parseKeyBinding(obj.get("scroll_right"), allocator) orelse .{
            .key = 'l',
            .modifiers = .{},
        },
        .zoom_in = try parseKeyBinding(obj.get("zoom_in"), allocator) orelse .{
            .key = 'i',
            .modifiers = .{},
        },
        .zoom_out = try parseKeyBinding(obj.get("zoom_out"), allocator) orelse .{
            .key = 'o',
            .modifiers = .{},
        },
        .colorize = try parseKeyBinding(obj.get("colorize"), allocator) orelse .{
            .key = 'z',
            .modifiers = .{},
        },
        .quit = try parseKeyBinding(obj.get("quit"), allocator) orelse .{
            .key = 'c',
            .modifiers = .{ .ctrl = true },
        },
    };
}

fn parseKeyBinding(value: ?std.json.Value, allocator: std.mem.Allocator) !?KeyBinding {
    const binding = value orelse return null;
    const obj = binding.object;

    const key = try std.json.innerParseFromValue(
        []const u8,
        allocator,
        obj.get("key") orelse return null,
        .{},
    );
    defer allocator.free(key);

    var modifiers = vaxis.Key.Modifiers{};
    if (obj.get("modifiers")) |mods| {
        for (mods.array.items) |mod| {
            const mod_str = try std.json.innerParseFromValue([]const u8, allocator, mod, .{});
            defer allocator.free(mod_str);

            if (std.mem.eql(u8, mod_str, "ctrl")) {
                modifiers.ctrl = true;
            }
            // TODO: Add more modifiers
        }
    }

    return KeyBinding{
        .key = key[0],
        .modifiers = modifiers,
    };
}

fn parseFileMonitor(value: std.json.Value, allocator: std.mem.Allocator) !FileMonitor {
    const obj = value.object;

    return FileMonitor{
        .enabled = try std.json.innerParseFromValue(
            bool,
            allocator,
            obj.get("enabled") orelse .{ .bool = true },
            .{},
        ),
        .latency = try std.json.innerParseFromValue(
            f16,
            allocator,
            obj.get("latency") orelse .{ .float = 0.1 },
            .{},
        ),
    };
}

fn parseGeneral(value: std.json.Value, allocator: std.mem.Allocator) !General {
    const obj = value.object;

    const white = obj.get("white") orelse std.json.Value{ .string = "0x000000" };
    const black = obj.get("black") orelse std.json.Value{ .string = "0xffffff" };

    return General{
        .colorize = try std.json.innerParseFromValue(
            bool,
            allocator,
            obj.get("colorize") orelse .{ .bool = false },
            .{},
        ),
        .white = try std.fmt.parseInt(i32, white.string[2..], 16),
        .black = try std.fmt.parseInt(i32, black.string[2..], 16),
        .size = try std.json.innerParseFromValue(
            f32,
            allocator,
            obj.get("size") orelse .{ .float = 0.90 },
            .{},
        ),
        .zoom_step = try std.json.innerParseFromValue(
            f32,
            allocator,
            obj.get("zoom_step") orelse .{ .float = 0.25 },
            .{},
        ),
        .scroll_step = try std.json.innerParseFromValue(
            f32,
            allocator,
            obj.get("scroll_step") orelse .{ .float = 100.0 },
            .{},
        ),
    };
}

fn parseStatusBar(value: std.json.Value, allocator: std.mem.Allocator) !StatusBar {
    const obj = value.object;

    const enabled = try std.json.innerParseFromValue(
        bool,
        allocator,
        obj.get("enabled") orelse .{ .bool = true },
        .{},
    );

    if (obj.get("style")) |style_val| {
        const style_obj = style_val.object;
        const bg = style_obj.get("bg").?.object;
        const fg = style_obj.get("fg").?.object;

        const bg_rgb = bg.get("rgb").?.array;
        const fg_rgb = fg.get("rgb").?.array;

        const style = .{
            .bg = .{ .rgb = .{
                try std.json.innerParseFromValue(u8, allocator, bg_rgb.items[0], .{}),
                try std.json.innerParseFromValue(u8, allocator, bg_rgb.items[1], .{}),
                try std.json.innerParseFromValue(u8, allocator, bg_rgb.items[2], .{}),
            } },
            .fg = .{ .rgb = .{
                try std.json.innerParseFromValue(u8, allocator, fg_rgb.items[0], .{}),
                try std.json.innerParseFromValue(u8, allocator, fg_rgb.items[1], .{}),
                try std.json.innerParseFromValue(u8, allocator, fg_rgb.items[2], .{}),
            } },
        };

        return StatusBar{
            .enabled = enabled,
            .style = style,
        };
    }

    return .{};
}
