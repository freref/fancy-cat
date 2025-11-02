const Self = @This();
const std = @import("std");
const vaxis = @import("vaxis");

pub const KeyMap = struct {
    next: vaxis.Key = .{ .codepoint = 'n' },
    prev: vaxis.Key = .{ .codepoint = 'p' },
    scroll_up: vaxis.Key = .{ .codepoint = 'k' },
    scroll_down: vaxis.Key = .{ .codepoint = 'j' },
    scroll_left: vaxis.Key = .{ .codepoint = 'h' },
    scroll_right: vaxis.Key = .{ .codepoint = 'l' },
    zoom_in: vaxis.Key = .{ .codepoint = 'i' },
    zoom_out: vaxis.Key = .{ .codepoint = 'o' },
    width_mode: vaxis.Key = .{ .codepoint = 'w' },
    colorize: vaxis.Key = .{ .codepoint = 'z' },
    quit: vaxis.Key = .{ .codepoint = 'c', .mods = .{ .ctrl = true } },
    full_screen: vaxis.Key = .{ .codepoint = 'f' },
    enter_command_mode: vaxis.Key = .{ .codepoint = ':' },
    exit_command_mode: vaxis.Key = .{ .codepoint = vaxis.Key.escape },
    execute_command: vaxis.Key = .{ .codepoint = vaxis.Key.enter },
    history_back: vaxis.Key = .{ .codepoint = vaxis.Key.up },
    history_forward: vaxis.Key = .{ .codepoint = vaxis.Key.down },

    pub fn parse(val: std.json.Value, allocator: std.mem.Allocator) KeyMap {
        var keymap = KeyMap{};
        if (val != .object) return keymap;

        inline for (std.meta.fields(KeyMap)) |key| {
            @field(keymap, key.name) = parseKeyBinding(val.object, key.name, allocator, @field(
                keymap,
                key.name,
            ));
        }

        return keymap;
    }
};

pub const FileMonitor = struct {
    enabled: bool = true,
    // Amount of time in seconds to wait in between polling for file changes
    latency: f16 = 0.1,
    reload_indicator_duration: f16 = 1.0,

    pub fn parse(val: std.json.Value, allocator: std.mem.Allocator) FileMonitor {
        var file_monitor = FileMonitor{};
        if (val != .object) return file_monitor;

        file_monitor.enabled = parseType(
            bool,
            val.object,
            "enabled",
            allocator,
            file_monitor.enabled,
        );
        file_monitor.latency = parseType(
            f16,
            val.object,
            "latency",
            allocator,
            file_monitor.latency,
        );
        file_monitor.reload_indicator_duration = parseType(
            f16,
            val.object,
            "reload_indicator_duration",
            allocator,
            file_monitor.reload_indicator_duration,
        );

        return file_monitor;
    }
};

pub const General = struct {
    colorize: bool = false,
    white: i32 = 0x000000,
    black: i32 = 0xffffff,
    // size of the pdf
    // 1 is the whole window
    size: f32 = 1.0,
    // percentage
    zoom_step: f32 = 1.25,
    zoom_min: f32 = 1.0,
    // pixels
    scroll_step: f32 = 100.0,
    // seconds
    retry_delay: f32 = 0.2,
    timeout: f32 = 5.0,
    // resolution
    dpi: f32 = 96.0,
    // whole number (possibly 0)
    history: u32 = 1000,

    pub fn parse(val: std.json.Value, allocator: std.mem.Allocator) General {
        var general = General{};
        if (val != .object) return general;

        general.colorize = parseType(bool, val.object, "colorize", allocator, general.colorize);

        if (val.object.get("white")) |white| {
            if (parseRGB(white, allocator)) |rgb| {
                general.white = @intCast(
                    (@as(u32, rgb[0]) << 16) | (@as(u32, rgb[1]) << 8) | @as(u32, rgb[2]),
                );
            }
        }
        if (val.object.get("black")) |black| {
            if (parseRGB(black, allocator)) |rgb| {
                general.black = @intCast(
                    (@as(u32, rgb[0]) << 16) | (@as(u32, rgb[1]) << 8) | @as(u32, rgb[2]),
                );
            }
        }

        general.size = parseType(f32, val.object, "size", allocator, general.size);
        general.zoom_step = parseType(f32, val.object, "zoom_step", allocator, general.zoom_step);
        general.zoom_min = parseType(f32, val.object, "zoom_min", allocator, general.zoom_min);
        general.scroll_step = parseType(f32, val.object, "scroll_step", allocator, general.scroll_step);
        general.retry_delay = parseType(f32, val.object, "retry_delay", allocator, general.retry_delay);
        general.timeout = parseType(f32, val.object, "timeout", allocator, general.timeout);
        general.dpi = parseType(f32, val.object, "dpi", allocator, general.dpi);
        general.history = parseType(u32, val.object, "history", allocator, general.history);

        return general;
    }
};

pub const StatusBar = struct {
    pub const StyledItem = struct {
        text: []const u8,
        style: vaxis.Cell.Style,
    };
    pub const ModeAwareItem = struct {
        view: StyledItem,
        command: StyledItem,
    };
    pub const ReloadAwareItem = struct {
        idle: StyledItem,
        reload: StyledItem,
        watching: StyledItem,
    };
    pub const Item = union(enum) {
        styled: StyledItem,
        mode_aware: ModeAwareItem,
        reload_aware: ReloadAwareItem,
    };

    const default_style = vaxis.Cell.Style{
        .bg = .{ .rgb = .{ 0, 0, 0 } },
        .fg = .{ .rgb = .{ 255, 255, 255 } },
    };

    pub const PATH = "<path>";
    pub const SEPARATOR = "<separator>";
    pub const PAGE = "<page>";
    pub const TOTAL_PAGES = "<total_pages>";

    pub const default_items: []const StatusBar.Item = &.{
        .{ .styled = .{ .text = " ", .style = default_style } },
        .{ .mode_aware = .{
            .view = .{ .text = "VIS", .style = default_style },
            .command = .{ .text = "CMD", .style = default_style },
        } },
        .{ .styled = .{ .text = "   ", .style = default_style } },
        .{ .styled = .{ .text = PATH, .style = default_style } },
        .{ .styled = .{ .text = " ", .style = default_style } },
        .{ .reload_aware = .{
            .idle = .{ .text = " ", .style = default_style },
            .reload = .{ .text = "*", .style = default_style },
            .watching = .{ .text = " ", .style = default_style },
        } },
        .{ .styled = .{ .text = SEPARATOR, .style = default_style } },
        .{ .styled = .{ .text = PAGE, .style = default_style } },
        .{ .styled = .{ .text = ":", .style = default_style } },
        .{ .styled = .{ .text = TOTAL_PAGES, .style = default_style } },
        .{ .styled = .{ .text = " ", .style = default_style } },
    };

    enabled: bool = true,
    style: vaxis.Cell.Style = default_style,
    items: []const StatusBar.Item = default_items,

    pub fn parse(val: std.json.Value, allocator: std.mem.Allocator) StatusBar {
        var status_bar = StatusBar{};
        if (val != .object) return status_bar;

        status_bar.enabled = parseType(bool, val.object, "enabled", allocator, status_bar.enabled);
        status_bar.style = parseStyle(val.object, allocator, status_bar.style);
        status_bar.items = parseItems(val.object, allocator, status_bar.style);

        return status_bar;
    }
};

pub const Cache = struct {
    enabled: bool = true,
    // Number of pages to cache
    lru_size: u16 = 10,

    pub fn parse(val: std.json.Value, allocator: std.mem.Allocator) Cache {
        var cache = Cache{};
        if (val != .object) return cache;

        cache.enabled = parseType(bool, val.object, "enabled", allocator, cache.enabled);
        // XXX temporary change to u16 from usize due to bug in std
        cache.lru_size = parseType(u16, val.object, "lru_size", allocator, cache.lru_size);

        return cache;
    }
};

arena: std.heap.ArenaAllocator,

key_map: KeyMap = .{},
file_monitor: FileMonitor = .{},
general: General = .{},
status_bar: StatusBar = .{},
cache: Cache = .{},

legacy_path: bool = false,

pub fn init(allocator: std.mem.Allocator) Self {
    var self = Self{ .arena = std.heap.ArenaAllocator.init(allocator) };
    const arena_allocator = self.arena.allocator();

    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return self;
    defer allocator.free(home);

    var path: []u8 = "";
    const xdg_config_home = std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME") catch null;
    if (xdg_config_home) |x| {
        path = std.fmt.allocPrint(allocator, "{s}/fancy-cat/config.json", .{x}) catch return self;
        allocator.free(x);
    } else path = std.fmt.allocPrint(allocator, "{s}/.config/fancy-cat/config.json", .{home}) catch return self;
    defer allocator.free(path);

    var content = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch null;
    if (content == null) {
        const legacy_path = std.fmt.allocPrint(allocator, "{s}/.fancy-cat", .{home}) catch return self;
        defer allocator.free(legacy_path);

        content = std.fs.cwd().readFileAlloc(allocator, legacy_path, 1024 * 1024) catch null;
        if (content == null) {
            if (std.fs.path.dirname(path)) |dir| std.fs.cwd().makePath(dir) catch {};
            const file = std.fs.createFileAbsolute(path, .{}) catch return self;
            file.close();
            return self;
        }
        self.legacy_path = true;
    }
    defer allocator.free(content.?);

    if (content.?.len == 0) return self;

    var parsed = std.json.parseFromSlice(std.json.Value, arena_allocator, content.?, .{}) catch return self;
    defer parsed.deinit();

    if (parsed.value.object.get("KeyMap")) |key_map| self.key_map = KeyMap.parse(key_map, arena_allocator);
    if (parsed.value.object.get("FileMonitor")) |file_monitor| self.file_monitor = FileMonitor.parse(file_monitor, arena_allocator);
    if (parsed.value.object.get("General")) |general| self.general = General.parse(general, arena_allocator);
    if (parsed.value.object.get("StatusBar")) |status_bar| self.status_bar = StatusBar.parse(status_bar, arena_allocator);
    if (parsed.value.object.get("Cache")) |cache| self.cache = Cache.parse(cache, arena_allocator);

    return self;
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

fn parseKeyBinding(obj: std.json.ObjectMap, name: []const u8, allocator: std.mem.Allocator, fallback: vaxis.Key) vaxis.Key {
    const val = obj.get(name) orelse return fallback;
    if (val != .object) return fallback;

    const key_str = parseType([]const u8, val.object, "key", allocator, "");
    if (key_str.len == 0) return fallback;

    var binding = fallback;
    binding.codepoint = vaxis.Key.name_map.get(key_str) orelse @as(u21, key_str[0]);

    var mods = vaxis.Key.Modifiers{};
    const modifiers = val.object.get("modifiers") orelse return binding;
    if (modifiers != .array) return binding;

    for (modifiers.array.items) |mod| {
        if (mod != .string) continue;
        if (std.mem.eql(u8, mod.string, "shift")) mods.shift = true;
        if (std.mem.eql(u8, mod.string, "alt")) mods.alt = true;
        if (std.mem.eql(u8, mod.string, "ctrl")) mods.ctrl = true;
        if (std.mem.eql(u8, mod.string, "super")) mods.super = true;
        if (std.mem.eql(u8, mod.string, "hyper")) mods.hyper = true;
        if (std.mem.eql(u8, mod.string, "meta")) mods.meta = true;
        if (std.mem.eql(u8, mod.string, "caps_lock")) mods.caps_lock = true;
        if (std.mem.eql(u8, mod.string, "num_lock")) mods.num_lock = true;
    }

    binding.mods = mods;

    return binding;
}

fn parseType(comptime T: type, obj: std.json.ObjectMap, key: []const u8, allocator: std.mem.Allocator, fallback: T) T {
    if (obj.get(key)) |raw_key| {
        return std.json.innerParseFromValue(T, allocator, raw_key, .{}) catch fallback;
    }
    return fallback;
}

fn parseStyle(obj: std.json.ObjectMap, allocator: std.mem.Allocator, fallback: vaxis.Cell.Style) vaxis.Cell.Style {
    const val = obj.get("style") orelse return fallback;
    if (val != .object) return fallback;

    var style = fallback;
    inline for (std.meta.fields(vaxis.Cell.Style)) |field| {
        if (val.object.get(field.name)) |field_val| {
            if (comptime std.mem.eql(u8, field.name, "fg") or std.mem.eql(u8, field.name, "bg") or std.mem.eql(u8, field.name, "ul")) {
                if (parseRGB(field_val, allocator)) |rgb| {
                    @field(style, field.name) = .{ .rgb = rgb };
                } else {
                    @field(style, field.name) = std.json.innerParseFromValue(field.type, allocator, field_val, .{}) catch @field(style, field.name);
                }
            } else {
                @field(style, field.name) = std.json.innerParseFromValue(field.type, allocator, field_val, .{}) catch @field(style, field.name);
            }
        }
    }

    return style;
}

fn parseRGB(val: std.json.Value, allocator: std.mem.Allocator) ?[3]u8 {
    switch (val) {
        .string => |str| {
            var hex = str;
            if (hex.len == 0) return null;
            if (std.mem.startsWith(u8, hex, "#")) hex = hex[1..];
            if (std.mem.startsWith(u8, hex, "0x") or std.mem.startsWith(u8, hex, "0X")) hex = hex[2..];
            if (hex.len != 6) return null;

            const rgb_int = std.fmt.parseInt(u32, hex, 16) catch return null;
            const r = @as(u8, @intCast((rgb_int >> 16) & 0xFF));
            const g = @as(u8, @intCast((rgb_int >> 8) & 0xFF));
            const b = @as(u8, @intCast(rgb_int & 0xFF));
            return .{ r, g, b };
        },
        .object => |obj| {
            const rgb_val = obj.get("rgb") orelse return null;
            const rgb = std.json.innerParseFromValue([3]u8, allocator, rgb_val, .{}) catch return null;
            return rgb;
        },
        else => return null,
    }
}

fn parseItems(obj: std.json.ObjectMap, allocator: std.mem.Allocator, fallback_style: vaxis.Cell.Style) []const StatusBar.Item {
    const raw_items = obj.get("items") orelse {
        const items = allocator.alloc(StatusBar.Item, StatusBar.default_items.len) catch return StatusBar.default_items;
        for (StatusBar.default_items, 0..) |item, i| {
            items[i] = applyStyle(item, fallback_style, allocator);
        }
        return items;
    };

    if (raw_items != .array) return StatusBar.default_items;

    const items = allocator.alloc(StatusBar.Item, raw_items.array.items.len) catch return StatusBar.default_items;
    for (raw_items.array.items, 0..) |item, i| {
        items[i] = parseItem(item, allocator, fallback_style);
    }
    return items;
}

fn applyStyle(item: StatusBar.Item, style: vaxis.Cell.Style, allocator: std.mem.Allocator) StatusBar.Item {
    var styled_item: StatusBar.Item = .{ .styled = StatusBar.StyledItem{ .text = "", .style = style } };
    var mode_aware_item: StatusBar.Item = .{ .mode_aware = StatusBar.ModeAwareItem{
        .view = StatusBar.StyledItem{ .text = "", .style = style },
        .command = StatusBar.StyledItem{ .text = "", .style = style },
    } };
    var reload_aware_item: StatusBar.Item = .{ .reload_aware = StatusBar.ReloadAwareItem{
        .idle = StatusBar.StyledItem{ .text = "", .style = style },
        .reload = StatusBar.StyledItem{ .text = "", .style = style },
        .watching = StatusBar.StyledItem{ .text = "", .style = style },
    } };

    switch (item) {
        .styled => |styled| {
            styled_item.styled.text = allocator.dupe(u8, styled.text) catch styled_item.styled.text;
            return styled_item;
        },
        .mode_aware => |mode_aware| {
            mode_aware_item.mode_aware.view.text = allocator.dupe(u8, mode_aware.view.text) catch mode_aware_item.mode_aware.view.text;
            mode_aware_item.mode_aware.command.text = allocator.dupe(u8, mode_aware.command.text) catch mode_aware_item.mode_aware.command.text;
            return mode_aware_item;
        },
        .reload_aware => |reload_aware| {
            reload_aware_item.reload_aware.idle.text = allocator.dupe(u8, reload_aware.idle.text) catch reload_aware_item.reload_aware.idle.text;
            reload_aware_item.reload_aware.reload.text = allocator.dupe(u8, reload_aware.reload.text) catch reload_aware_item.reload_aware.reload.text;
            reload_aware_item.reload_aware.watching.text = allocator.dupe(u8, reload_aware.watching.text) catch reload_aware_item.reload_aware.watching.text;
            return reload_aware_item;
        },
    }
}

fn parseItem(val: std.json.Value, allocator: std.mem.Allocator, fallback_style: vaxis.Cell.Style) StatusBar.Item {
    var styled_item: StatusBar.Item = .{ .styled = StatusBar.StyledItem{ .text = "", .style = fallback_style } };
    var mode_aware_item: StatusBar.Item = .{ .mode_aware = StatusBar.ModeAwareItem{
        .view = StatusBar.StyledItem{ .text = "", .style = fallback_style },
        .command = StatusBar.StyledItem{ .text = "", .style = fallback_style },
    } };
    var reload_aware_item: StatusBar.Item = .{ .reload_aware = StatusBar.ReloadAwareItem{
        .idle = StatusBar.StyledItem{ .text = "", .style = fallback_style },
        .reload = StatusBar.StyledItem{ .text = "", .style = fallback_style },
        .watching = StatusBar.StyledItem{ .text = "", .style = fallback_style },
    } };

    switch (val) {
        .string => |str| {
            styled_item.styled.text = allocator.dupe(u8, str) catch "";
            return styled_item;
        },

        .object => |obj| {
            if (obj.contains("view") or obj.contains("command")) {
                mode_aware_item.mode_aware.view = parseStyledItem(obj.get("view"), allocator, mode_aware_item.mode_aware.view);
                mode_aware_item.mode_aware.command = parseStyledItem(obj.get("command"), allocator, mode_aware_item.mode_aware.command);
                return mode_aware_item;
            }
            if (obj.contains("idle") or obj.contains("reload") or obj.contains("watching")) {
                reload_aware_item.reload_aware.idle = parseStyledItem(obj.get("idle"), allocator, reload_aware_item.reload_aware.idle);
                reload_aware_item.reload_aware.reload = parseStyledItem(obj.get("reload"), allocator, reload_aware_item.reload_aware.reload);
                reload_aware_item.reload_aware.watching = parseStyledItem(obj.get("watching"), allocator, reload_aware_item.reload_aware.watching);
                return reload_aware_item;
            }

            styled_item.styled = parseStyledItem(val, allocator, styled_item.styled);
            return styled_item;
        },

        else => return styled_item,
    }
}

fn parseStyledItem(val: ?std.json.Value, allocator: std.mem.Allocator, fallback: StatusBar.StyledItem) StatusBar.StyledItem {
    const item = val orelse return fallback;

    var styled_item = fallback;
    switch (item) {
        .string => |str| {
            styled_item.text = allocator.dupe(u8, str) catch fallback.text;
            return styled_item;
        },
        .object => |obj| {
            if (obj.get("text")) |raw_text| {
                const text = std.json.innerParseFromValue([]const u8, allocator, raw_text, .{}) catch return styled_item;
                styled_item.text = allocator.dupe(u8, text) catch fallback.text;
            } else {
                styled_item.text = fallback.text;
            }
            if (obj.get("style")) |raw_style| {
                if (raw_style == .object)
                    styled_item.style = parseStyle(obj, allocator, fallback.style);
            }

            return styled_item;
        },
        else => return styled_item,
    }
}
