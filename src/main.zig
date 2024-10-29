const std = @import("std");
const c = @import("cmd");
const script = @import("script");
const debug = @import("debug");
const cmdContext = @import("context.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;

    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    var cmd = c.command(cmdContext).init(alloc.allocator());
    defer cmd.deinit();

    {
        var ctx = cmdContext{ .tryCb = cmdContext.install };
        var install = try cmd.addCommand(.{ .use = "install", .serve = &ctx });
        try install.addArgument("program", .{ .String = "" });
    }
    {
        var ctx = cmdContext{ .tryCb = cmdContext.record };
        _ = try cmd.addCommand(.{ .use = "record", .serve = &ctx });
    }
    {
        var ctx = cmdContext{ .tryCb = cmdContext.testing };
        _ = try cmd.addCommand(.{ .use = "test", .serve = &ctx });
    }

    try cmd.execute();

    try bw.flush();
}
