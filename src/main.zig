const std = @import("std");
const Context = @import("Context.zig").Context;

// Types for build.zig.zon
// For now metadata is only used in main.zig, but can move it to types.zig if needed eleswhere
// This wont be necessary once https://github.com/ziglang/zig/pull/22907 is merged

const PackageName = enum { fancy_cat };

const DependencyType = struct {
    url: []const u8,
    hash: []const u8,
};

const DependenciesType = struct {
    vaxis: DependencyType,
    fzwatch: DependencyType,
    fastb64z: DependencyType,
};

const MetadataType = struct {
    name: PackageName,
    fingerprint: u64,
    version: []const u8,
    minimum_zig_version: []const u8,
    dependencies: DependenciesType,
    paths: []const []const u8,
};

const metadata: MetadataType = @import("metadata");

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len == 2 and (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v"))) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("fancy-cat version {s}\n", .{metadata.version});
        return;
    }

    if (args.len < 2 or args.len > 3) {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("Usage: fancy-cat <path-to-pdf> <optional-page-number>\n");
        return;
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
