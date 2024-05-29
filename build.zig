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

    const main = b.addExecutable(.{
        .name = "p3desk",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    try SetupModules(b, &.{
        .{ .name = "string", .path = b.path("src/string.zig") },
        .{ .name = "script", .path = b.path("src/script/script.zig") },
        .{ .name = "cmd", .path = b.path("src/cmd/mod.zig"), .dependencies = &.{"string"} },
    });

    main.root_module.addImport("string", b.modules.get("string").?);
    main.root_module.addImport("script", b.modules.get("script").?);

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

    const test_step = b.step("test", "Run unit tests");

    // const cmd_test = b.addTest(.{ .name = "cmd", .root_source_file = b.path("src/cmd/test.zig") });
    // cmd_test.root_module.addImport("string", string);
    // test_step.dependOn(&cmd_test.step);

    // _ = b.addRunArtifact(cmd_test);
    //
    SetupTests(b, test_step, &.{
        .{ .name = "cmd", .path = b.path("src/cmd/test.zig"), .dependencies = &.{"string"} },
    });

    try SetupTestDirs(b, test_step, &.{
        .{ .path = "testing", .dependencies = &.{ "string", "script" } },
    });
}

fn SetupModules(b: *std.Build, mods: []const Module) !void {
    for (mods) |m| {
        const mod = b.addModule(m.name, .{
            .root_source_file = m.path,
        });
        for (m.dependencies) |dep| {
            mod.addImport(dep, b.modules.get(dep).?);
        }
    }
}

fn SetupTests(b: *std.Build, step: *std.Build.Step, list: []const Test) void {
    for (list) |t| {
        SetupTest(b, step, t);
    }
}

fn SetupTest(b: *std.Build, step: *std.Build.Step, t: Test) void {
    const c = b.addTest(.{
        .name = t.name,
        .root_source_file = t.path,
        .test_runner = b.path("test_runner.zig"),
    });
    for (t.dependencies) |dep| {
        c.root_module.addImport(dep, b.modules.get(dep).?);
    }
    const run = b.addRunArtifact(c);
    run.has_side_effects = true;
    step.dependOn(&run.step);
}

fn SetupTestDir(b: *std.Build, step: *std.Build.Step, test_dir: TestDir) !void {
    const lazy_path = b.path(test_dir.path);
    const dir_path = lazy_path.getPath(b);
    const dir = try std.fs.openDirAbsolute(dir_path, .{ .iterate = true });
    var iter = dir.iterate();
    while (try iter.next()) |f| {
        switch (f.kind) {
            .file => {
                if (!std.mem.eql(u8, std.fs.path.extension(f.name), ".zig")) {
                    continue;
                }
                SetupTest(b, step, .{
                    .name = f.name,
                    .path = b.path(b.pathJoin(&.{ test_dir.path, f.name })),
                    .dependencies = test_dir.dependencies,
                });
            },
            else => {},
        }
    }
}

fn SetupTestDirs(b: *std.Build, step: *std.Build.Step, list: []const TestDir) !void {
    for (list) |d| {
        try SetupTestDir(b, step, d);
    }
}

const Module = struct {
    name: []const u8,
    path: std.Build.LazyPath,
    dependencies: []const []const u8 = &.{},
};

const Test = struct {
    name: []const u8,
    path: std.Build.LazyPath,
    dependencies: []const []const u8 = &.{},
};

const TestDir = struct {
    path: []const u8,
    dependencies: []const []const u8 = &.{},
};
