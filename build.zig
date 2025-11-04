const std = @import("std");

fn addMupdfStatic(exe: *std.Build.Step.Compile, b: *std.Build, prefix: []const u8) void {
    exe.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{prefix}) });
    exe.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{prefix}) });

    exe.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib/libmupdf.a", .{prefix}) });
    exe.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib/libmupdf-third.a", .{prefix}) });

    exe.linkLibC();
}

fn addMupdfDynamic(exe: *std.Build.Step.Compile, target: std.Target) void {
    if (target.os.tag == .macos and target.cpu.arch == .aarch64) {
        exe.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        exe.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
    } else if (target.os.tag == .macos and target.cpu.arch == .x86_64) {
        exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
        exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    } else if (target.os.tag == .linux) {
        exe.addIncludePath(.{ .cwd_relative = "/home/linuxbrew/.linuxbrew/include" });
        exe.addLibraryPath(.{ .cwd_relative = "/home/linuxbrew/.linuxbrew/lib" });

        const linux_libs = [_][]const u8{
            "mupdf-third", "harfbuzz",
            "freetype",    "jbig2dec",
            "jpeg",        "openjp2",
            "gumbo",       "mujs",
        };
        for (linux_libs) |lib| exe.linkSystemLibrary(lib);
    }
    exe.linkSystemLibrary("mupdf");
    exe.linkSystemLibrary("z");
    exe.linkLibC();
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var useVendorMupdf = true;
    const prefix = "./local";
    const location = "./deps/mupdf/local";

    std.fs.cwd().access("./deps/mupdf/Makefile", .{}) catch |err| {
        if (err == error.FileNotFound) {
            useVendorMupdf = false;
        } else {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            return;
        }
    };
    const allocator = std.heap.page_allocator;
    var make_args: std.ArrayList([]const u8) = .empty;
    defer make_args.deinit(allocator);

    make_args.append(allocator, "make") catch unreachable;

    // use as many cores as possible by default (like zig) I dont know how to check for j<N> arg
    const cpu_count = std.Thread.getCpuCount() catch 1;
    make_args.append(allocator, b.fmt("-j{d}", .{cpu_count})) catch unreachable;

    make_args.append(allocator, "-C") catch unreachable;
    make_args.append(allocator, "deps/mupdf") catch unreachable;

    if (target.result.os.tag == .linux) {
        make_args.append(allocator, "HAVE_X11=no") catch unreachable;
        make_args.append(allocator, "HAVE_GLUT=no") catch unreachable;
    }

    make_args.append(allocator, "XCFLAGS=-w -DTOFU -DTOFU_CJK -DFZ_ENABLE_PDF=1 " ++
        "-DFZ_ENABLE_XPS=0 -DFZ_ENABLE_SVG=0 -DFZ_ENABLE_CBZ=0 " ++
        "-DFZ_ENABLE_IMG=0 -DFZ_ENABLE_HTML=0 -DFZ_ENABLE_EPUB=0") catch unreachable;
    make_args.append(allocator, "tools=no") catch unreachable;
    make_args.append(allocator, "apps=no") catch unreachable;

    const prefix_arg = b.fmt("prefix={s}", .{prefix});
    make_args.append(allocator, prefix_arg) catch unreachable;
    make_args.append(allocator, "install") catch unreachable;

    const mupdf_build_step = b.addSystemCommand(make_args.items);

    const exe = b.addExecutable(.{
        .name = "fancy-cat",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.headerpad_max_install_names = true;

    if (target.result.os.tag == .macos) exe.linkFramework("CoreGraphics");

    const deps = .{
        .vaxis = b.dependency("vaxis", .{ .target = target, .optimize = optimize }),
        .fzwatch = b.dependency("fzwatch", .{ .target = target, .optimize = optimize }),
        .fastb64z = b.dependency("fastb64z", .{ .target = target, .optimize = optimize }),
    };

    exe.root_module.addImport("fastb64z", deps.fastb64z.module("fastb64z"));
    exe.root_module.addImport("vaxis", deps.vaxis.module("vaxis"));
    exe.root_module.addImport("fzwatch", deps.fzwatch.module("fzwatch"));

    exe.root_module.addAnonymousImport("metadata", .{ .root_source_file = b.path("build.zig.zon") });

    if (useVendorMupdf) {
        exe.step.dependOn(&mupdf_build_step.step);
        addMupdfStatic(exe, b, location);
        b.installArtifact(exe);
        b.getInstallStep().dependOn(&mupdf_build_step.step);
    } else {
        addMupdfDynamic(exe, target.result);
        b.installArtifact(exe);
    }

    exe.addIncludePath(.{ .cwd_relative = "src/mupdf-z" });
    exe.addCSourceFile(.{ .file = .{ .cwd_relative = "src/mupdf-z/fitz-z.c" } });

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the app").dependOn(&run_cmd.step);
}
