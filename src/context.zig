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
        var script = try p.scriptContent();
        var runner = try s.ScriptRunner.init(&script);
        runner.collectOutput(&stdout_buf_w, &stdout_buf_w, .{});
        defer runner.deinit();

        var window_data = WindowData{ .mutex = mutex, .step = runner.step, .steps = runner.steps };

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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // displaying unicode characters in curses needs this and cursesw in build.zig
    var stdoutBuf = std.ArrayList(u8).init(gpa.allocator());
    var stderrBuf = std.ArrayList(u8).init(gpa.allocator());

    defer {
        stdoutBuf.deinit();
        stderrBuf.deinit();
    }

    var mutex = std.Thread.Mutex{};
    const thread = try std.Thread.spawn(.{}, loop, .{
        &mutex,
        stdoutBuf.writer().any(),
        stderrBuf.writer().any(),
    });

    var ui = try tui.UI.init(gpa.allocator());

    defer ui.deinit();

    thread.join();
}

fn loop(mutex: *std.Thread.Mutex, stdout_w: std.io.AnyWriter, stderr_w: std.io.AnyWriter) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};

    const args: []const []const u8 = &.{ "echo", "Hello, world!" };
    var child = std.process.Child.init(args, alloc.allocator());
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var out = std.ArrayList(u8).init(alloc.allocator());
    var err = std.ArrayList(u8).init(alloc.allocator());
    defer {
        out.deinit();
        err.deinit();
    }

    inline for (0..5) |_| {
        std.time.sleep(2 * std.time.ns_per_s);
        try child.spawn();
        try child.collectOutput(&out, &err, 4096);
        _ = try child.wait();

        mutex.lock();
        defer mutex.unlock();
        try stdout_w.writeAll(out.items);
        try stderr_w.writeAll(err.items);
    }
}

pub fn testing(_: *Self, _: *Cmd) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};

    var ui = try tui.UI.init(alloc.allocator());
    defer ui.deinit();

    const pos = try ui.term.?.getCursorPos();
    try stdout.print("{any}", .{pos});

    std.time.sleep(4 * std.time.ns_per_s);
}
