const Self = @This();
const std = @import("std");
const vaxis = @import("vaxis");
const Context = @import("../Context.zig").Context;
const Config = @import("../config/Config.zig");
const ViewMode = @import("./ViewMode.zig");
const TextInput = vaxis.widgets.TextInput;

context: *Context,
text_input: TextInput,

pub fn init(context: *Context) Self {
    return .{
        .context = context,
        .text_input = TextInput.init(context.allocator, &context.vx.unicode),
    };
}

pub fn deinit(self: *Self) void {
    const win = self.context.vx.window();
    win.hideCursor();
    self.text_input.deinit();
}

pub fn handleKeyStroke(self: *Self, key: vaxis.Key, km: Config.KeyMap) !void {
    if (key.matches(km.exit_command_mode.codepoint, km.exit_command_mode.mods)) {
        self.context.changeState(.view);
        return;
    }

    if (key.matches(km.execute_command.codepoint, km.execute_command.mods)) {
        self.executeCommand(self.text_input.buf.firstHalf());
        self.context.changeState(.view);
        return;
    }

    try self.text_input.update(.{ .key_press = key });
}

pub fn drawCommandBar(self: *Self, win: vaxis.Window) void {
    const command_bar = win.child(.{
        .x_off = 0,
        .y_off = win.height - 1,
        .width = win.width,
        .height = 1,
    });
    _ = command_bar.print(&.{.{ .text = ":" }}, .{ .col_offset = 0 });

    const child = win.child(.{
        .x_off = 1,
        .y_off = win.height - 1,
        .width = win.width,
        .height = 1,
    });

    self.text_input.draw(child);
}

pub fn executeCommand(self: *Self, cmd: []const u8) void {
    const cmd_str = std.mem.trim(u8, cmd, " ");

    if (std.mem.eql(u8, cmd_str, "q")) {
        self.context.should_quit = true;
    }

    if (std.fmt.parseInt(u16, cmd_str, 10)) |page_num| {
        const success = self.context.document_handler.goToPage(page_num);
        if (success) {
            self.context.resetCurrentPage();
        }
    } else |_| {}
}
