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
    if (key.matches(km.exit_command_mode.codepoint, km.exit_command_mode.mods) or
        (key.matches(vaxis.Key.backspace, .{}) and self.text_input.buf.realLength() == 0))
    {
        self.context.changeMode(.view);
        return;
    }

    if (key.matches(km.execute_command.codepoint, km.execute_command.mods)) {
        self.executeCommand(self.text_input.buf.firstHalf());
        self.context.changeMode(.view);
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
        return;
    }

    if (std.mem.endsWith(u8, cmd_str, "%")) {
        const number_str = cmd_str[0 .. cmd_str.len - 1];
        if (std.fmt.parseFloat(f32, number_str)) |percent| {
            // TODO detect DPI
            const dpi = self.context.document_handler.pdf_handler.config.general.dpi;
            const zoom_factor = (percent * dpi) / 7200.0;
            self.context.document_handler.setZoom(zoom_factor);
            self.context.resetCurrentPage();
        } else |_| {}
        return;
    }

    if (std.fmt.parseInt(u16, cmd_str, 10)) |page_num| {
        const success = self.context.document_handler.goToPage(page_num);
        if (success) {
            self.context.resetCurrentPage();
        }
    } else |_| {}
}
