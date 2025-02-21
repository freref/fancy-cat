const Self = @This();
const vaxis = @import("vaxis");
const Context = @import("../Context.zig").Context;
const CommandState = @import("./CommandState.zig");
const Config = @import("../config/Config.zig");

context: *Context,

pub fn init(context: *Context) Self {
    return .{
        .context = context,
    };
}

pub fn handleKeyStroke(self: *Self, key: vaxis.Key, km: Config.KeyMap) !void {
    // O(n) but n is small
    // Centralized key handling
    const key_actions = &[_]Context.KeyAction{
        .{
            .codepoint = km.next.codepoint,
            .mods = km.next.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    if (s.pdf_helper.changePage(1)) {
                        s.resetCurrentPage();
                        s.pdf_helper.resetZoomAndScroll();
                    }
                    s.reload_flags = .{ .page = true, .status_bar = true };
                }
            }.action,
        },
        .{
            .codepoint = km.prev.codepoint,
            .mods = km.prev.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    if (s.pdf_helper.changePage(-1)) {
                        s.resetCurrentPage();
                        s.pdf_helper.resetZoomAndScroll();
                    }
                    s.reload_flags = .{ .page = true, .status_bar = true };
                }
            }.action,
        },
        .{
            .codepoint = km.zoom_in.codepoint,
            .mods = km.zoom_in.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_helper.adjustZoom(true);
                    s.reload_flags.page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.zoom_out.codepoint,
            .mods = km.zoom_out.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_helper.adjustZoom(false);
                    s.reload_flags.page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_up.codepoint,
            .mods = km.scroll_up.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_helper.scroll(.Up);
                    s.reload_flags.page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_down.codepoint,
            .mods = km.scroll_down.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_helper.scroll(.Down);
                    s.reload_flags.page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_left.codepoint,
            .mods = km.scroll_left.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_helper.scroll(.Left);
                    s.reload_flags.page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_right.codepoint,
            .mods = km.scroll_right.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_helper.scroll(.Right);
                    s.reload_flags.page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.colorize.codepoint,
            .mods = km.colorize.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.pdf_helper.toggleColor();
                    s.reload_flags.page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.enter_command_mode.codepoint,
            .mods = km.enter_command_mode.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.changeState(.command);
                    s.reload_flags.command_bar = true;
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
