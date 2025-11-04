const builtin = @import("builtin");
const utilities = struct {
    pub const macos = @import("./macos.zig");
};

pub fn getDPI() ?f32 {
    return switch (builtin.os.tag) {
        .macos => utilities.macos.getDPI(),
        else => null,
    };
}
