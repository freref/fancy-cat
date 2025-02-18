// config
pub const KeyMap = struct {
    pub const next = .{ .key = 'n', .modifiers = .{} };
    pub const prev = .{ .key = 'p', .modifiers = .{} };
    pub const scroll_up = .{ .key = 'k', .modifiers = .{} };
    pub const scroll_down = .{ .key = 'j', .modifiers = .{} };
    pub const scroll_left = .{ .key = 'h', .modifiers = .{} };
    pub const scroll_right = .{ .key = 'l', .modifiers = .{} };
    pub const zoom_in = .{ .key = 'i', .modifiers = .{} };
    pub const zoom_out = .{ .key = 'o', .modifiers = .{} };
    pub const colorize = .{ .key = 'z', .modifiers = .{} };
    pub const quit = .{ .key = 'c', .modifiers = .{ .ctrl = true } };
};

/// File monitor will be used to watch for changes to files and rerender them
pub const FileMonitor = struct {
    pub const enabled: bool = true;
    // Amount of time to wait inbetween polling for file changes
    pub const latency: f16 = 0.1;
};

pub const General = struct {
    pub const colorize: bool = false;
    pub const white: u32 = 0x000000;
    pub const black: u32 = 0xffffff;
    // size of the pdf
    // 1 is the whole screen
    pub const size: f32 = 0.90;
    // percentage
    pub const zoom_step: f32 = 0.25;
    // pixels
    pub const scroll_step: f32 = 100.0;
};

pub const StatusBar = struct {
    // status bar shows the page numbers and file name
    pub const enabled: bool = true;
    pub const style = .{
        .bg = .{ .rgb = .{ 216, 74, 74 } },
        .fg = .{ .rgb = .{ 255, 255, 255 } },
    };
};
