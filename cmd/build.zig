const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(b, std.Build.StaticLibraryOptions{
        .name = "cmd",
        .root_source_file = "lib.zig",
        .optimize = optimize,
        .target = target,
    });

    b.installArtifact(lib);
}
