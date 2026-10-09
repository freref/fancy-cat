const std = @import("std");
const Context = @import("../Context.zig");
const vaxis = @import("vaxis");
stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
thread: ?std.Thread = null,
loop: *vaxis.Loop(Context.Event),
const Self = @This();
pub fn run(self: *Self) void {
    while (!self.stop.load(.acquire)) {
        std.Thread.sleep(250 * std.time.ns_per_ms);
        _ = self.loop.tryPostEvent(.graphics_tick);
    }
}
pub fn deinit(self: *Self) void {
    self.stop.store(true, .release);
    if (self.thread) |thread| thread.join();
}
