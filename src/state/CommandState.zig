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

pub fn handleKeyStroke(self: *Self, key: vaxis.Key, km: Config.KeyMap) !void {
    // O(n) but n is small
    // Centralized key handling
    const key_actions = &[_]Context.KeyAction{
        .{
            .codepoint = km.exit_command_mode.codepoint,
            .mods = km.exit_command_mode.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.changeState(.view);
                }
            }.action,
        },
        .{
            .codepoint = km.enter_command_mode.codepoint,
            .mods = km.enter_command_mode.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.changeState(.view);
                }
            }.action,
        },
    };

    for (key_actions) |action| {
        if (key.matches(action.codepoint, action.mods)) {
            action.handler(self.context);
            break;
        }
    }

    // have to convert codepoint to u8
    //if (std.ascii.isASCII(@as(u8, @intCast(key.codepoint)))) {
    //    var writer = self.context.command_buffer.writer();
    //    try writer.write(key.codepoint);
    //    self.context.reload = true;
    //}

    self.context.reload = true;
}
