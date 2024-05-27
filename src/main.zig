const std = @import("std");
const c = @import("cmd/mod.zig");
const script = @import("script/script.zig");

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

    _ = try cmd.addCommand(.{ .use = "install" });

    try cmd.execute();

    try bw.flush();
}

const cmdContext = struct {
    const Self = @This();
    const Cmd = c.command(Self);

    cb: ?*const fn (ctx: *Self, cmd: *Cmd) void = null,

    pub fn call(self: *Self, cmd: *Cmd) void {
        if (self.cb) |cb| {
            cb(self, cmd);
        }
    }
};
