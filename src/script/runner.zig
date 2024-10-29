const std = @import("std");
const debug = @import("debug");
const module = @import("mod.zig");
const utils = @import("utils");
const Iterator = utils.IteratorBox;
const CallbackFn = utils.CallbackFn;

const Self = @This();

stdout: ?*std.io.AnyWriter = null,
stderr: ?*std.io.AnyWriter = null,
collect_options: module.CollectOptions = module.CollectOptions{},

step: usize = 0,
steps: std.ArrayList([]const u8),
iterator: *Iterator(std.ChildProcess),

alloc: std.mem.Allocator,

fn call(item: std.ChildProcess) []const u8 {
    return item.argv[0];
}

pub fn init(alloc: std.mem.Allocator, iter: *Iterator(std.ChildProcess)) Self {
    const steps = iter.map([]const u8, call).collect();
    iter.reset();

    return Self{
        .steps = steps,
        .iterator = iter,
        .alloc = alloc,
    };
}

pub fn collectOutput(self: *Self, stdout: *std.io.AnyWriter, stderr: *std.io.AnyWriter, options: module.CollectOptions) void {
    self.stdout = stdout;
    self.stderr = stderr;
    self.collect_options = options;
}

pub fn execNext(self: *Self) !void {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};

    if (self.iterator.next()) |child| {
        const pipes = try std.posix.pipe2(.{ .NONBLOCK = true });
        const pid = std.os.linux.fork();

        if (pid == 0) {
            std.posix.close(pipes[0]);
            try std.posix.dup2(pipes[1], std.posix.STDOUT_FILENO);
            try std.posix.dup2(pipes[1], std.posix.STDERR_FILENO);

            var t = std.ArrayList(?[*:0]const u8).init(alloc.allocator());
            defer t.deinit();

            for (child.argv[0..]) |arg| {
                var null_arg: [:0]u8 = try alloc.allocator().allocSentinel(u8, arg.len, 0);
                @memcpy(null_arg[0..arg.len], arg);
                try t.append(null_arg);
            }

            const args: [*:null]?[*:0]const u8 = try t.toOwnedSliceSentinel(null);

            var env_vars = std.ArrayList(?[*:0]const u8).init(alloc.allocator());
            defer env_vars.deinit();

            for (std.os.environ) |v| {
                try env_vars.append(v);
            }

            const env: [*:null]?[*:0]const u8 = try env_vars.toOwnedSliceSentinel(null);

            const result = std.posix.execvpeZ(args[0].?, args, env);

            var buf: [16000]u8 = undefined;

            // TODO: recognize access denied add chmod +x option in case that was the problem

            _ = try std.posix.write(pipes[1], try std.fmt.bufPrint(&buf, "{!}\n", .{result}));
            std.process.exit(1);
        } else {
            _ = try self.forkParent(0, pipes);
        }
    } else {
        return error.EndOfScript;
    }

    if (alloc.detectLeaks()) return error.MemoryLeaked;
}

fn forkParent(self: *Self, childPid: i32, pipes: [2]i32) !u32 {
    std.posix.close(pipes[1]);
    while (true) {
        std.time.sleep(5 * std.time.ns_per_ms);
        var buf: [16000]u8 = undefined;

        const size = std.posix.read(pipes[0], &buf) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return err,
        };

        if (size == 0) {
            break;
        }

        if (self.stdout) |stdout| {
            try stdout.writeAll(buf[0..size]);
        }
    }

    const result = std.posix.waitpid(childPid, 0);
    self.step += 1;
    return result.status;
}

pub fn exec(self: *Self) !void {
    while (blk: {
        self.execNext() catch |err| switch (err) {
            error.EndOfScript => break :blk false,
            else => return err,
        };
        break :blk true;
    }) {}
}
