const Self = @This();
const vaxis = @import("vaxis");
const Context = @import("../Context.zig").Context;
const CommandState = @import("./CommandState.zig");
const Config = @import("../config/Config.zig");

context: *Context,

pub const KeyAction = struct {
    codepoint: u21,
    mods: vaxis.Key.Modifiers,
    handler: *const fn (*Context) void,
};

pub fn init(context: *Context) Self {
    return .{
        .context = context,
    };
}

pub fn handleKeyStroke(self: *Self, key: vaxis.Key, km: Config.KeyMap) !void {
    // O(n) but n is small
    // Centralized key handling
    const key_actions = &[_]KeyAction{
        .{
            .codepoint = km.next.codepoint,
            .mods = km.next.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    if (s.pdf_handler.changePage(1)) {
                        s.resetCurrentPage();
                    }
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.prev.codepoint,
            .mods = km.prev.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    if (s.pdf_handler.changePage(-1)) {
                        s.resetCurrentPage();
                    }
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.zoom_in.codepoint,
            .mods = km.zoom_in.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_handler.adjustZoom(true);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.zoom_out.codepoint,
            .mods = km.zoom_out.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_handler.adjustZoom(false);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_up.codepoint,
            .mods = km.scroll_up.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_handler.scroll(.Up);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_down.codepoint,
            .mods = km.scroll_down.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_handler.scroll(.Down);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_left.codepoint,
            .mods = km.scroll_left.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_handler.scroll(.Left);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_right.codepoint,
            .mods = km.scroll_right.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_handler.scroll(.Right);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.colorize.codepoint,
            .mods = km.colorize.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_handler.toggleColor();
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.enter_command_mode.codepoint,
            .mods = km.enter_command_mode.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.changeState(.command);
                }
            }.action,
        },
    };

    for (key_actions) |action| {
        if (key.matches(action.codepoint, action.mods)) {
            action.handler(self.context);
            return;
        }
    }
}
