const std = @import("std");
const FileReader = @import("file_reader.zig").FileReader;

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

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

    var app = try FileReader.init(allocator, args);
    defer app.deinit();

    try app.run();
}
