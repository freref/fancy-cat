const Self = @This();
const std = @import("std");
const vaxis = @import("vaxis");
const Context = @import("../Context.zig").Context;
const Config = @import("../config/Config.zig");
const ViewMode = @import("./ViewMode.zig");
const TextInput = vaxis.widgets.TextInput;

context: *Context,
text_input: TextInput,
history_prefix: ?[]const u8 = null,

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
    if (self.history_prefix) |history_prefix| self.context.allocator.free(history_prefix);
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

        if (cmd.len > 0) {
            self.executeCommand(cmd);
            self.context.history.addToHistory(cmd);
        }

        self.context.changeMode(.view);
        return;
    }

    // History
    if (key.matches(km.history_back.codepoint, km.history_back.mods) or key.matches(km.history_forward.codepoint, km.history_forward.mods)) {
        if (self.history_prefix == null) {
            const text_input = try self.text_input.buf.toOwnedSlice();
            defer self.context.allocator.free(text_input);
            self.history_prefix = try self.context.allocator.dupe(u8, text_input);
        }

        const history_prefix = self.history_prefix.?;
        var filtered = std.ArrayList([]const u8){};
        defer filtered.deinit(self.context.allocator);

        for (self.context.history.items.items) |cmd| {
            if (std.mem.startsWith(u8, cmd, history_prefix)) {
                try filtered.append(self.context.allocator, cmd);
            }
        }

        const count = @as(isize, @intCast(filtered.items.len));
        if (count > 0) {
            if (key.matches(km.history_back.codepoint, km.history_back.mods)) {
                if (self.context.history.index == -1) {
                    self.context.history.index = count - 1;
                } else if (self.context.history.index > 0) {
                    self.context.history.index -= 1;
                }
            } else if (key.matches(km.history_forward.codepoint, km.history_forward.mods)) {
                if (self.context.history.index >= 0 and self.context.history.index < count - 1) {
                    self.context.history.index += 1;
                } else {
                    self.context.history.index = -1;
                }
            }
        }

        const input_to_display = if (self.context.history.index == -1 or count == 0)
            history_prefix
        else
            filtered.items[@as(usize, @intCast(self.context.history.index))];

        self.text_input.buf.clearRetainingCapacity();
        self.text_input.reset();
        try self.text_input.insertSliceAtCursor(input_to_display);

        return;
    }

    if (self.history_prefix) |history_prefix| {
        self.context.allocator.free(history_prefix);
        self.history_prefix = null;
    }
    self.context.history.index = -1;

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
    if (self.handleQuit(cmd)) return;
    if (self.handleGoToPage(cmd)) return;
    if (self.handleZoom(cmd)) return;
    if (self.handleScroll(cmd)) return;
}

fn handleQuit(self: *Self, cmd: []const u8) bool {
    if (!std.mem.eql(u8, cmd, "q")) return false;
    self.context.should_quit = true;
    return true;
}

fn handleGoToPage(self: *Self, cmd: []const u8) bool {
    const page_num = (std.fmt.parseInt(u16, cmd, 10) catch return false);
    if (!self.context.document_handler.goToPage(page_num)) return false;

    self.context.resetCurrentPage();
    return true;
}

fn handleZoom(self: *Self, cmd: []const u8) bool {
    if (!std.mem.endsWith(u8, cmd, "%")) return false;

    const number_str = cmd[0 .. cmd.len - 1];
    if (std.fmt.parseFloat(f32, number_str)) |percent| {
        // TODO detect DPI
        const dpi = self.context.document_handler.pdf_handler.config.general.dpi;
        const zoom_factor = (percent * dpi) / 7200.0;
        self.context.document_handler.setZoom(zoom_factor);
        self.context.resetCurrentPage();
        return true;
    } else |_| {
        return false;
    }
}

fn handleScroll(self: *Self, cmd: []const u8) bool {
    if (cmd.len < 3) return false;
    const axis = cmd[0];
    const sign = cmd[1];
    if ((axis != 'x' and axis != 'y') or (sign != '+' and sign != '-')) return false;

    const number_str = cmd[2..];

    if (std.fmt.parseFloat(f32, number_str)) |amount| {
        const delta = if (sign == '+') amount else -amount;
        const dx: f32 = if (axis == 'x') delta else 0.0;
        const dy: f32 = if (axis == 'y') delta else 0.0;
        self.context.document_handler.offsetScroll(dx, dy);
        self.context.resetCurrentPage();
        return true;
    } else |_| {
        return false;
    }
}
