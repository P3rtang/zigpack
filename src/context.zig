const std = @import("std");
const c = @import("cmd");
const s = @import("script");
const tui = @import("tui");
const nc = @cImport({
    @cInclude("curses.h");
    @cInclude("locale.h");
});

const InstallWin = @import("install.zig").InstallWindow;

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
    self.try_install(cmd) catch |err| std.debug.panicExtra(@errorReturnTrace(), null, "{any}\n", .{err});
}

fn try_install(_: *Self, cmd: *Cmd) !void {
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
        var script = try s.Script.init(arena.allocator(), val.value_ptr.*);
        try script.collectOutput(&stdout_buf_w, &stdout_buf_w, .{});
        try scripts.put(script.data.name, script);
    }

    var thread: ?std.Thread = null;
    if (scripts.getPtr(program)) |p| {
        thread = try std.Thread.spawn(.{}, s.Script.exec, .{p});
    } else {
        std.log.warn("No such program: `{s}`", .{program});
    }

    var install_win = InstallWin.init(arena.allocator(), &stdout_buf);
    try install_win.run();
    // wait on scripts to finish
    if (thread) |t| t.join();
}

pub fn record(_: *Self, _: *Cmd) void {
    try_record() catch |err| std.debug.panicExtra(@errorReturnTrace(), null, "{any}", .{err});
}

fn try_record() !void {
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

    var ui = tui.UI.init(gpa.allocator());
    defer ui.deinit();

    while (true) {
        std.time.sleep(10 * std.time.ns_per_ms);
        var layout = tui.Layout{ .border = .Rounded };
        try ui.beginWidget(&layout.widget);
        {
            mutex.lock();
            defer mutex.unlock();
            var textBox = tui.TextBox.init(stdoutBuf.items, .{ .w = 80, .h = 20 });
            try ui.beginWidget(&textBox.widget);
            try ui.endWidget();
        }
        try ui.endWidget();
    }

    _ = nc.getch();

    _ = nc.endwin();

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
