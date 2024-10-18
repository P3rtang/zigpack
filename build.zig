const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main = b.addExecutable(.{
        .name = "p3desk",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    main.linkLibC();

    const tui = b.addStaticLibrary(std.Build.StaticLibraryOptions{
        .name = "tui",
        .root_source_file = b.path("tui/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    main.root_module.addImport("tui", &tui.root_module);

    try SetupModules(b, &main.root_module, &.{
        .{ .name = "string", .path = b.path("src/string.zig") },
        .{ .name = "debug", .path = b.path("src/debug_print.zig") },
        .{ .name = "script", .path = b.path("src/script/mod.zig"), .module_deps = &.{"debug"} },
        .{ .name = "cmd", .path = b.path("cmd/lib.zig"), .module_deps = &.{"string"} },
        .{ .name = "tui", .path = b.path("tui/lib.zig") },
        .{ .name = "utils", .path = b.path("utils/lib.zig") },
    });

    b.installArtifact(main);

    main.addIncludePath(b.path("src/string.zig"));
    main.addIncludePath(b.path("cmd/lib.zig"));
    main.addIncludePath(b.path("tui/lib.zig"));
    main.addIncludePath(b.path("utils/lib.zig"));
    main.addIncludePath(b.path("src/debug_print.zig"));

    const run_cmd = b.addRunArtifact(main);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    SetupTests(b, test_step, &.{
        .{ .name = "cmd", .path = b.path("cmd/test.zig"), .config = .{ .module_deps = &.{"string"} } },
    });

    SetupTests(b, test_step, &.{.{
        .name = "script",
        .path = b.path("src/script/test.zig"),
        .config = .{ .module_deps = &.{ "utils", "debug" } },
    }});

    try SetupTestDirs(b, test_step, &.{
        .{ .path = "testing", .config = .{ .module_deps = &.{ "string", "script", "debug" }, .useLibC = true } },
    });

    const tui_test = b.step("tui", "Run tui unit tests");
    try SetupTestDirs(b, tui_test, &.{
        .{ .path = "tui/testing", .config = .{ .module_deps = &.{"tui"}, .useLibC = true } },
    });

    test_step.dependOn(tui_test);
}

fn SetupModules(b: *std.Build, parent_mod: *std.Build.Module, mods: []const Module) !void {
    for (mods) |m| {
        const mod = b.addModule(m.name, .{
            .root_source_file = m.path,
        });

        parent_mod.addImport(m.name, mod);

        for (m.module_deps) |dep| {
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

    if (t.config.useLibC) {
        c.linkLibC();
    }

    for (t.config.system_libs) |lib| {
        c.linkSystemLibrary(lib);
    }

    for (t.config.module_deps) |dep| {
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
                    .config = test_dir.config,
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
    module_deps: []const []const u8 = &.{},
};

const Test = struct {
    name: []const u8,
    path: std.Build.LazyPath,
    config: TestConfig,
};

const TestDir = struct {
    path: []const u8,
    config: TestConfig,
};

const TestConfig = struct {
    module_deps: []const []const u8 = &.{},
    system_libs: []const []const u8 = &.{},
    useLibC: bool = false,
};
