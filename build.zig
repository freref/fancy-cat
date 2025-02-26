const std = @import("std");

fn addMupdfDeps(exe: *std.Build.Step.Compile, b: *std.Build, prefix: []const u8) void {
    exe.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{prefix}) });
    exe.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{prefix}) });

    exe.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib/libmupdf.a", .{prefix}) });
    exe.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib/libmupdf-third.a", .{prefix}) });

    exe.linkLibC();
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const prefix = b.option([]const u8, "prefix", "Installation prefix") orelse "./local";
    const mupdf_build_step = b.addSystemCommand(&[_][]const u8{
        "make",
        "-C",
        "thirdparty/mupdf",
        b.fmt("prefix={s}", .{prefix}),
        "install",
    });

    const exe = b.addExecutable(.{
        .name = "fancy-cat",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.headerpad_max_install_names = true;

    const deps = .{
        .vaxis = b.dependency("vaxis", .{
            .target = target,
            .optimize = optimize,
        }),
        .fzwatch = b.dependency("fzwatch", .{
            .target = target,
            .optimize = optimize,
        }),
        .fastb64z = b.dependency("fastb64z", .{
            .target = target,
            .optimize = optimize,
        }),
    };

    exe.root_module.addImport("fastb64z", deps.fastb64z.module("fastb64z"));
    exe.root_module.addImport("vaxis", deps.vaxis.module("vaxis"));
    exe.root_module.addImport("fzwatch", deps.fzwatch.module("fzwatch"));

    exe.step.dependOn(&mupdf_build_step.step);

    addMupdfDeps(exe, b, prefix);

    b.installArtifact(exe);
    b.getInstallStep().dependOn(&mupdf_build_step.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the app").dependOn(&run_cmd.step);
}
