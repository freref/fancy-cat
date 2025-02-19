const Self = @This();
const vaxis = @import("vaxis");
const Context = @import("../Context.zig").Context;

context: *Context,
// view-specific data

pub fn init(context: *Context) Self {
    return .{
        .context = context,
    };
}

pub fn handleKeyStroke(self: *Self, key: vaxis.Key) !void {
    _ = self;
    _ = key;
}
