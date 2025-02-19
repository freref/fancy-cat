const std = @import("std");
const Context = @import("Context.zig").Context;

pub const FANCY_CAT_VERSION = "0.1.1";

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len == 2 and (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v"))) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("fancy-cat version {s}\n", .{FANCY_CAT_VERSION});
        return;
    }

    if (args.len < 2 or args.len > 3) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("Usage: fancy-cat <path-to-pdf> <optional-page-number>\n");
        return error.InvalidArguments;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();

    var app = try Context.init(allocator, args);
    defer app.deinit();

    try app.run();
}
