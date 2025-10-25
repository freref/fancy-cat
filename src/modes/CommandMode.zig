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
        .text_input = TextInput.init(context.allocator),
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
        const text_input = try self.text_input.buf.toOwnedSlice();
        defer self.context.allocator.free(text_input);
        const cmd = std.mem.trim(u8, text_input, &std.ascii.whitespace);
        self.executeCommand(cmd);
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

    self.text_input.draw(command_bar.child(.{ .x_off = 1 }));
}

pub fn executeCommand(self: *Self, cmd: []const u8) void {
    if (std.mem.eql(u8, cmd, "q")) {
        self.context.should_quit = true;
        return;
    }

    if (cmd.len >= 3) {
        const axis = cmd[0];
        const sign = cmd[1];
        if ((axis == 'x' or axis == 'y') and (sign == '+' or sign == '-')) {
            const number_str = cmd[2..];
            if (std.fmt.parseFloat(f32, number_str)) |amount| {
                const delta = if (sign == '+') amount else -amount;
                const dx: f32 = if (axis == 'x') delta else 0.0;
                const dy: f32 = if (axis == 'y') delta else 0.0;
                self.context.document_handler.offsetScroll(dx, dy);
                self.context.resetCurrentPage();
            } else |_| {}
            return;
        }
    }

    if (std.mem.endsWith(u8, cmd, "%")) {
        const number_str = cmd[0 .. cmd.len - 1];
        if (std.fmt.parseFloat(f32, number_str)) |percent| {
            // TODO detect DPI
            const dpi = self.context.document_handler.pdf_handler.config.general.dpi;
            const zoom_factor = (percent * dpi) / 7200.0;
            self.context.document_handler.setZoom(zoom_factor);
            self.context.resetCurrentPage();
        } else |_| {}
        return;
    }

    if (std.fmt.parseInt(u16, cmd, 10)) |page_num| {
        const success = self.context.document_handler.goToPage(page_num);
        if (success) {
            self.context.resetCurrentPage();
        }
    } else |_| {}
}
