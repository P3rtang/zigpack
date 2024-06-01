const std = @import("std");
const c = @import("cmd");
const script = @import("script");
const cmdContext = @import("context.zig");

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;

    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    var cmd = c.command(cmdContext).init(alloc.allocator());
    defer cmd.deinit();

    {
        var ctx = cmdContext{ .cb = cmdContext.install };
        var install = try cmd.addCommand(.{ .use = "install", .serve = &ctx });
        try install.addArgument("program", .{ .String = "" });
    }
    {
        var ctx = cmdContext{ .cb = cmdContext.record };
        _ = try cmd.addCommand(.{ .use = "record", .serve = &ctx });
    }

    try cmd.execute();

    try bw.flush();
}
