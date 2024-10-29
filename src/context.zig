const std = @import("std");
const c = @import("cmd");
const s = @import("script");
const tui = @import("tui");

const InstallWin = @import("install.zig").InstallWindow;
const WindowData = @import("install.zig").WindowData;

const Self = @This();
const Cmd = c.command(Self);
var stdout = std.io.getStdOut().writer().any();
var stderr = std.io.getStdErr().writer().any();

cb: ?*const fn (ctx: *Self, cmd: *Cmd) void = null,
tryCb: ?*const fn (ctx: *Self, cmd: *Cmd) anyerror!void = null,

pub fn call(self: *Self, cmd: *Cmd) void {
    if (self.cb) |cb| {
        cb(self, cmd);
    }
}

pub fn tryCall(self: *Self, cmd: *Cmd) !void {
    if (self.tryCb) |cb| {
        try cb(self, cmd);
    }
}

pub fn install(_: *Self, cmd: *Cmd) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(alloc.allocator());
    defer arena.deinit();

    const program = cmd.getArgument("program").?.String;

    const script_file_path = try std.fs.realpathAlloc(arena.allocator(), "./scripts/scripts.json");

    const script_file = try std.fs.openFileAbsolute(script_file_path, .{});
    const reader = script_file.reader();

    var scripts = std.StringHashMap(s.Script).init(arena.allocator());

    var stdout_buf = std.ArrayList(u8).init(arena.allocator());
    var stdout_buf_w = stdout_buf.writer().any();

    const content_buf = try reader.readAllAlloc(arena.allocator(), 4096);
    const content = try std.json.parseFromSliceLeaky(
        std.json.ArrayHashMap(s.ScriptData),
        arena.allocator(),
        content_buf,
        .{},
    );

    var content_iter = content.map.iterator();
    while (content_iter.next()) |val| {
        const script = try s.Script.init(arena.allocator(), val.value_ptr.*);
        try scripts.put(script.data.name, script);
    }

    var thread: ?std.Thread = null;
    const mutex = std.Thread.Mutex{};

    if (scripts.getPtr(program)) |p| {
        const script = try p.scriptContent();
        var runner = s.ScriptRunner.init(arena.allocator(), script);
        runner.collectOutput(&stdout_buf_w, &stdout_buf_w, .{});

        var window_data = WindowData{ .mutex = mutex, .step = runner.step, .steps = runner.steps.items };

        thread = try std.Thread.spawn(.{}, scriptRunnerThread, .{ &runner, &window_data });

        var install_win = try InstallWin.init(
            arena.allocator(),
            &stdout_buf,
            &window_data,
        );

        try install_win.run();
    } else {
        std.log.warn("No such program: `{s}`", .{program});
    }
    // wait on scripts to finish
    if (thread) |t| t.join();
}

fn scriptRunnerThread(runner: *s.ScriptRunner, window_data: *WindowData) !void {
    while (blk: {
        runner.execNext() catch |err| switch (err) {
            error.EndOfScript => break :blk false,
            else => return err,
        };
        break :blk true;
    }) {
        window_data.mutex.lock();
        defer window_data.mutex.unlock();

        window_data.step = runner.step;
    }
}

pub fn record(_: *Self, _: *Cmd) !void {
    const RecordUI = @import("record.zig").RecordUI;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    var record_ui = try RecordUI.init(gpa.allocator());
    defer record_ui.deinit();
    try record_ui.run();
}

pub fn testing(_: *Self, _: *Cmd) !void {
    const TestUI = @import("test_ui.zig").TestUI;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    var test_ui = try TestUI.init(gpa.allocator());
    try test_ui.run();
}
