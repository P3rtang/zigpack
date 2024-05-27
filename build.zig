const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "p3desk",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const main = b.addExecutable(.{
        .name = "p3desk",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const cmd = b.addStaticLibrary(.{
        .name = "cmd",
        .root_source_file = .{ .path = "src/cmd/mod.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(main);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(main);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    try SetupModules(b, &.{
        .{ .name = "pprint", .path = "src/pp.zig" },
        .{ .name = "string", .path = "src/string.zig" },
        .{ .name = "script", .path = "src/script/script.zig" },
    });

    main.addModule("string", b.modules.get("string").?);
    main.addModule("script", b.modules.get("script").?);
    cmd.addModule("string", b.modules.get("string").?);

    try SetupTest(b, &.{
        .{ .name = "main", .path = "src/main.zig" },
        .{ .name = "root", .path = "src/root.zig" },
        .{ .name = "cmd", .path = "src/cmd/test.zig", .dependencies = &.{"string"} },
        .{ .name = "script", .path = "testing/script.zig", .dependencies = &.{ "string", "script" } },
    });
}

fn SetupModules(b: *std.Build, mods: []const Module) !void {
    for (mods) |mod| {
        _ = b.addModule(mod.name, .{
            .source_file = .{ .path = mod.path },
        });
    }
}

fn SetupTest(b: *std.Build, tests: []const Test) !void {
    const test_step = b.step("test", "Run unit tests");

    for (tests) |t| {
        const buildTest = b.addTest(.{
            .name = t.name,
            .root_source_file = .{ .path = t.path },
        });

        const run_test = b.addRunArtifact(buildTest);
        for (t.dependencies) |dep| {
            _ = buildTest.addModule(dep, b.modules.get(dep).?);
        }

        test_step.dependOn(&run_test.step);
    }
}

const Test = struct {
    name: []const u8,
    path: []const u8,
    dependencies: []const []const u8 = &.{},
};

const Module = struct {
    name: []const u8,
    path: []const u8,
};
