const std = @import("std");
const c = @import("cmd/mod.zig");
const s = @import("script");

const alloc = std.heap.page_allocator;
const Self = @This();
const Cmd = c.command(Self);
var stdout = std.io.getStdOut().writer().any();
var stderr = std.io.getStdErr().writer().any();

cb: ?*const fn (ctx: *Self, cmd: *Cmd) void = null,

pub fn call(self: *Self, cmd: *Cmd) void {
    if (self.cb) |cb| {
        cb(self, cmd);
    }
}

pub fn install(self: *Self, cmd: *Cmd) void {
    self.try_install(cmd) catch |err| std.debug.panic("{any}\n", .{err});
}

fn try_install(_: *Self, cmd: *Cmd) !void {
    const program = cmd.getArgument("program").?.String;

    const script_file_path = try std.fs.realpathAlloc(alloc, "./scripts/scripts.json");
    const script_file = try std.fs.openFileAbsolute(script_file_path, .{});
    const reader = script_file.reader();

    var scripts = std.StringHashMap(s.Script).init(alloc);

    var json = try reader.readUntilDelimiterOrEofAlloc(alloc, ';', 1024);
    while (json != null) : (json = try reader.readUntilDelimiterOrEofAlloc(alloc, ';', 1024)) {
        var script = try s.Script.fromJSON(alloc, json.?);
        try script.collectOutput(&stdout, &stderr, .{});
        try scripts.put(script.data.name, script);
    }

    if (scripts.get(program)) |p| {
        try p.exec();
    } else {
        std.log.warn("No such program: `{s}`", .{program});
    }

    scripts.deinit();
}
