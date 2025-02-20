const Self = @This();
const std = @import("std");
const vaxis = @import("vaxis");
const Context = @import("../Context.zig").Context;
const Config = @import("../config/Config.zig");
const ViewState = @import("./ViewState.zig");

context: *Context,
command_buffer: std.ArrayList(u8),

pub fn init(context: *Context) Self {
    return .{
        .context = context,
        .command_buffer = std.ArrayList(u8).init(context.allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.command_buffer.deinit();
}

pub fn handleKeyStroke(self: *Self, key: vaxis.Key, km: Config.KeyMap) !void {
    if (key.matches(km.exit_command_mode.codepoint, km.exit_command_mode.mods)) {
        self.context.changeState(.view);
        return;
    }

    if (key.matches(km.execute_command.codepoint, km.execute_command.mods)) {
        _ = self.context.executeCommand(self.command_buffer.items);
        self.context.changeState(.view);
        return;
    }

    if (key.matches(vaxis.Key.backspace, .{})) {
        if (self.command_buffer.items.len > 0) _ = self.command_buffer.pop();
        return;
    }

    // TODO clean this up
    if (key.shifted_codepoint) |shifted| {
        if (key.mods.shift and shifted < 128) {
            var buf: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(shifted, &buf) catch return;
            try self.command_buffer.appendSlice(buf[0..n]);
            return;
        }
    }
    if (key.codepoint < 128) {
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(key.codepoint, &buf) catch return;
        try self.command_buffer.appendSlice(buf[0..n]);
    }
}

pub fn drawCommandBar(self: *Self, win: vaxis.Window) void {
    const command_bar = win.child(.{
        .x_off = 0,
        .y_off = win.height - 1,
        .width = win.width,
        .height = 1,
    });
    _ = command_bar.print(
        &.{
            .{ .text = ":" },
            .{ .text = self.command_buffer.items },
        },
        .{ .col_offset = 0 },
    );
}
