// in your build.zig, you can specify a custom test runner:
// const tests = b.addTest(.{
//   .target = target,
//   .optimize = optimize,
//   .test_runner = "test_runner.zig", // add this line
//   .root_source_file = .{ .path = "src/main.zig" },
// });

const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const BORDER = "=" ** 80;

// use in custom panic handler
var current_test: ?[]const u8 = null;

pub fn main() !void {
    if (builtin.test_functions.len == 0) {
        return;
    }
    var mem: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&mem);

    const allocator = fba.allocator();

    const env = Env.init(allocator);
    defer env.deinit(allocator);

    var slowest = SlowTracker.init(allocator, 5);
    defer slowest.deinit();

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    var buffer = std.ArrayList(u8).init(allocator);
    var printer = Printer.init(buffer.writer().any());

    printer.fmt("\r\x1b[m", .{}); // beginning of line and clear to end of line

    const name = builtin.test_functions[0].name;
    var name_split = std.mem.splitBackwardsScalar(u8, name, '.');
    _ = name_split.next();
    const prefix_name = name_split.rest();
    printer.fmt("{s}\n", .{prefix_name});
    printer.fmt("---------------------------\n", .{});

    for (builtin.test_functions) |t| {
        std.testing.allocator_instance = .{};

        var status = Status.pass;
        slowest.startTiming();

        current_test = t.name;
        var parts = std.mem.splitBackwardsScalar(u8, t.name, '.');
        const short_name = parts.next().?;

        const result = t.func();
        current_test = null;

        const ns_taken = slowest.endTiming(t.name);

        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
            printer.status(.fail, "\n{s}\n\"{s}\" - Memory Leak\n{s}\n", .{ BORDER, t.name, BORDER });
        }

        if (result) |_| {
            pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip += 1;
                status = .skip;
            },
            else => {
                status = .fail;
                fail += 1;
                printer.status(.fail, "\n{s}\n\"{s}\" - {s}\n{s}\n", .{ BORDER, t.name, @errorName(err), BORDER });
                if (@errorReturnTrace()) |trace| {
                    printer.fmt("\x1b[31m{}\x1b[m\n", .{trace.*});
                }
                if (env.fail_first) {
                    break;
                }
            },
        }

        if (env.verbose) {
            const ms = @as(f64, @floatFromInt(ns_taken)) / 100_000.0;
            const time_buf = try std.fmt.allocPrint(allocator, "({d:.2}ms)", .{ms});
            printer.status(status, "{s:<10}{s}\n", .{ time_buf, short_name });
        } else {
            printer.status(status, ".", .{});
        }
    }

    const total_tests = pass + fail;
    const status = if (fail == 0) Status.pass else Status.fail;
    printer.fmt("\n", .{});
    printer.status(status, "{d} of {d} test{s} passed\n", .{ pass, total_tests, if (total_tests != 1) "s" else "" });
    if (skip > 0) {
        printer.status(.skip, "{d} test{s} skipped\n", .{ skip, if (skip != 1) "s" else "" });
    }
    if (leak > 0) {
        printer.status(.fail, "{d} test{s} leaked\n", .{ leak, if (leak != 1) "s" else "" });
    }
    printer.fmt("\n", .{});
    try slowest.display(printer);
    printer.fmt("\n", .{});
    try std.io.getStdErr().writeAll(try buffer.toOwnedSlice());
    std.posix.exit(if (fail == 0) 0 else 1);
}

const Printer = struct {
    out: std.io.AnyWriter,

    fn init(w: std.io.AnyWriter) Printer {
        return .{
            //.out = &std.io.getStdErr().writer().any(),
            .out = w,
        };
    }

    fn fmt(self: Printer, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.out, format, args) catch unreachable;
    }

    fn status(self: Printer, s: Status, comptime format: []const u8, args: anytype) void {
        const color = switch (s) {
            .pass => "\x1b[32m  OK    \x1b[m",
            .fail => "\x1b[31m  FAIL  \x1b[m",
            .skip => "\x1b[33m  SKIP  \x1b[m",
            else => "",
        };
        const out = self.out;
        out.writeAll(color) catch @panic("writeAll failed?!");
        std.fmt.format(out, format, args) catch @panic("std.fmt.format failed?!");
    }
};

const Status = enum {
    pass,
    fail,
    skip,
    text,
};

const SlowTracker = struct {
    const SlowestQueue = std.PriorityDequeue(TestInfo, void, compareTiming);
    max: usize,
    slowest: SlowestQueue,
    timer: std.time.Timer,

    fn init(allocator: Allocator, count: u32) SlowTracker {
        const timer = std.time.Timer.start() catch @panic("failed to start timer");
        var slowest = SlowestQueue.init(allocator, {});
        slowest.ensureTotalCapacity(count) catch @panic("OOM");
        return .{
            .max = count,
            .timer = timer,
            .slowest = slowest,
        };
    }

    const TestInfo = struct {
        ns: u64,
        name: []const u8,
    };

    fn deinit(self: SlowTracker) void {
        self.slowest.deinit();
    }

    fn startTiming(self: *SlowTracker) void {
        self.timer.reset();
    }

    fn endTiming(self: *SlowTracker, test_name: []const u8) u64 {
        var timer = self.timer;
        const ns = timer.lap();

        var slowest = &self.slowest;

        if (slowest.count() < self.max) {
            // Capacity is fixed to the # of slow tests we want to track
            // If we've tracked fewer tests than this capacity, than always add
            slowest.add(TestInfo{ .ns = ns, .name = test_name }) catch @panic("failed to track test timing");
            return ns;
        }

        {
            // Optimization to avoid shifting the dequeue for the common case
            // where the test isn't one of our slowest.
            const fastest_of_the_slow = slowest.peekMin() orelse unreachable;
            if (fastest_of_the_slow.ns > ns) {
                // the test was faster than our fastest slow test, don't add
                return ns;
            }
        }

        // the previous fastest of our slow tests, has been pushed off.
        _ = slowest.removeMin();
        slowest.add(TestInfo{ .ns = ns, .name = test_name }) catch @panic("failed to track test timing");
        return ns;
    }

    fn display(self: *SlowTracker, printer: Printer) !void {
        var slowest = self.slowest;
        const count = slowest.count();
        printer.fmt("Slowest {d} test{s}: \n", .{ count, if (count != 1) "s" else "" });
        while (slowest.removeMinOrNull()) |info| {
            const ms = @as(f64, @floatFromInt(info.ns)) / 100_000.0;
            printer.fmt("  {d:.2}ms\t{s}\n", .{ ms, info.name });
        }
    }

    fn compareTiming(context: void, a: TestInfo, b: TestInfo) std.math.Order {
        _ = context;
        return std.math.order(a.ns, b.ns);
    }
};

const Env = struct {
    verbose: bool,
    fail_first: bool,
    filter: ?[]const u8,

    fn init(allocator: Allocator) Env {
        return .{
            .verbose = readEnvBool(allocator, "TEST_VERBOSE", true),
            .fail_first = readEnvBool(allocator, "TEST_FAIL_FIRST", false),
            .filter = readEnv(allocator, "TEST_FILTER"),
        };
    }

    fn deinit(self: Env, allocator: Allocator) void {
        if (self.filter) |f| {
            allocator.free(f);
        }
    }

    fn readEnv(allocator: Allocator, key: []const u8) ?[]const u8 {
        const v = std.process.getEnvVarOwned(allocator, key) catch |err| {
            if (err == error.EnvironmentVariableNotFound) {
                return null;
            }
            std.log.warn("failed to get env var {s} due to err {}", .{ key, err });
            return null;
        };
        return v;
    }

    fn readEnvBool(allocator: Allocator, key: []const u8, deflt: bool) bool {
        const value = readEnv(allocator, key) orelse return deflt;
        defer allocator.free(value);
        return std.ascii.eqlIgnoreCase(value, "true");
    }
};

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (current_test) |ct| {
        std.debug.print("\x1b[31m{s}\npanic running \"{s}\"\n{s}\x1b[0m\n", .{ BORDER, ct, BORDER });
    }
    std.builtin.default_panic(msg, error_return_trace, ret_addr);
}
