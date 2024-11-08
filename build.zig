const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cat-pdf",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const config = b.addModule("config", .{ .root_source_file = b.path("config.zig") });
    exe.root_module.addImport("config", config);

    exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/Cellar/mupdf/1.24.9/include" });
    exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/Cellar/mupdf/1.24.9/lib" });
    exe.linkSystemLibrary("mupdf");
    exe.linkSystemLibrary("z");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
