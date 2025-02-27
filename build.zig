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

    const prefix = "./local";
    const location = "./deps/mupdf/local";

    var make_args = std.ArrayList([]const u8).init(b.allocator);
    defer make_args.deinit();

    make_args.append("make") catch unreachable;

    // use as many cores as possible by default (like zig) I dont know how to check for j<N> arg
    const cpu_count = std.Thread.getCpuCount() catch 1;
    make_args.append(b.fmt("-j{d}", .{cpu_count})) catch unreachable;

    make_args.append("-C") catch unreachable;
    make_args.append("deps/mupdf") catch unreachable;

    if (target.result.os.tag == .linux) {
        make_args.append("HAVE_X11=no") catch unreachable;
        make_args.append("HAVE_GLUT=no") catch unreachable;
    }

    make_args.append("XCFLAGS=-w -DTOFU -DTOFU_CJK -DFZ_ENABLE_PDF=1 " ++
        "-DFZ_ENABLE_XPS=0 -DFZ_ENABLE_SVG=0 -DFZ_ENABLE_CBZ=0 " ++
        "-DFZ_ENABLE_IMG=0 -DFZ_ENABLE_HTML=0 -DFZ_ENABLE_EPUB=0") catch unreachable;
    make_args.append("tools=no") catch unreachable;
    make_args.append("apps=no") catch unreachable;

    const prefix_arg = b.fmt("prefix={s}", .{prefix});
    make_args.append(prefix_arg) catch unreachable;
    make_args.append("install") catch unreachable;

    const mupdf_build_step = b.addSystemCommand(make_args.items);

    const exe = b.addExecutable(.{
        .name = "fancy-cat",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.headerpad_max_install_names = true;

    const deps = .{
        .vaxis = b.dependency("vaxis", .{ .target = target, .optimize = optimize }),
        .fzwatch = b.dependency("fzwatch", .{ .target = target, .optimize = optimize }),
        .fastb64z = b.dependency("fastb64z", .{ .target = target, .optimize = optimize }),
    };

    exe.root_module.addImport("fastb64z", deps.fastb64z.module("fastb64z"));
    exe.root_module.addImport("vaxis", deps.vaxis.module("vaxis"));
    exe.root_module.addImport("fzwatch", deps.fzwatch.module("fzwatch"));

    exe.step.dependOn(&mupdf_build_step.step);

    addMupdfDeps(exe, b, location);

    b.installArtifact(exe);
    b.getInstallStep().dependOn(&mupdf_build_step.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the app").dependOn(&run_cmd.step);
}
