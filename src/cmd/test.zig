const std = @import("std");
const testing = std.testing;
const c = @import("cmd.zig");
const parse = @import("parse.zig");
const pPrint = @import("pprint").pPrint;

test "parser from args" {
    const parser = try parse.Parser.new(testing.allocator);
    defer parser.deinit();
}

test "cmd parse arguments" {
    const args1 = "test -a --full";
    var parser = try parse.Parser.fromStr(args1, ' ', testing.allocator);
    defer parser.deinit();

    try std.testing.expectEqualSlices(u8, parser.peek().?.content, "test");
    try std.testing.expect(parser.next().?.kind == .argument);
    try std.testing.expectEqualSlices(u8, parser.peek().?.content, "a");
    try std.testing.expect(parser.next().?.kind == .short_flag);
    try std.testing.expectEqualSlices(u8, parser.peek().?.content, "full");
    try std.testing.expect(parser.next().?.kind == .flag);
    try std.testing.expect(parser.next() == null);
}

test "handle commands" {
    const testValue = enum {
        Default,
        Test1,
        Test2,
        Test3,
    };

    const cmdContext = struct {
        const Self = @This();
        const Cmd = c.command(Self);
        const testVal = .Default;

        value: testValue = testVal,
        cb: ?*const fn (ctx: *Self, cmd: *Cmd) void = null,

        pub fn call(self: *Self, cmd: *Cmd) void {
            if (self.cb) |cb| {
                cb(self, cmd);
            }
        }

        fn hello(ctx: *Self, cmd: *Cmd) void {
            _ = cmd;
            ctx.value = .Test1;
        }

        fn world(ctx: *Self, cmd: *Cmd) void {
            _ = cmd;
            ctx.value = .Test2;
        }

        fn helloWorld(ctx: *Self, cmd: *Cmd) void {
            _ = cmd;
            ctx.value = .Test3;
        }
    };

    var cmd = c.command(cmdContext).init(testing.allocator);
    defer cmd.deinit();

    var helloContext = cmdContext{ .cb = cmdContext.hello };
    var worldContext = cmdContext{ .cb = cmdContext.world };
    const helloCmd = try cmd.addCommand(.{ .use = "hello", .serve = &helloContext });
    _ = try cmd.addCommand(.{ .use = "world", .serve = &worldContext });

    var helloWorldContext = cmdContext{ .cb = cmdContext.helloWorld };
    _ = try helloCmd.addCommand(.{ .use = "world", .serve = &helloWorldContext });

    const args1 = "test hello";
    var parser1 = try parse.Parser.fromStr(args1, ' ', testing.allocator);
    defer parser1.deinit();
    try cmd.executeWithParser(&parser1);

    try std.testing.expect(helloContext.value == .Test1);

    try std.testing.expect(worldContext.value == .Default);

    const args2 = "test world";
    var parser2 = try parse.Parser.fromStr(args2, ' ', testing.allocator);
    defer parser2.deinit();
    try cmd.executeWithParser(&parser2);

    try std.testing.expect(worldContext.value == .Test2);

    const args3 = "test hello world";
    var parser3 = try parse.Parser.fromStr(args3, ' ', testing.allocator);
    defer parser3.deinit();
    try cmd.executeWithParser(&parser3);

    try std.testing.expect(helloWorldContext.value == .Test3);
}

test "handle arguments" {
    const cmdContext = struct {
        const Self = @This();
        const Cmd = c.command(Self);

        file: []const u8 = "",
        cb: ?*const fn (ctx: *Self, cmd: *Cmd) void = null,

        pub fn call(self: *Self, cmd: *Cmd) void {
            if (self.cb) |cb| {
                cb(self, cmd);
            }
        }

        fn testArg(self: *Self, cmd: *Cmd) void {
            if (cmd.getArgument("file")) |arg| {
                self.file = arg.String;
            }
        }
    };

    var cmd = c.command(cmdContext).init(testing.allocator);
    defer cmd.deinit();

    var fileCtx = cmdContext{ .cb = cmdContext.testArg };
    var fileCmd = try cmd.addCommand(.{ .use = "file", .serve = &fileCtx });
    try fileCmd.addArgument("file", c.ArgType{ .String = "" });

    const args1 = "test file ~/local/share";
    var parser1 = try parse.Parser.fromStr(args1, ' ', testing.allocator);
    defer parser1.deinit();
    try cmd.executeWithParser(&parser1);
    try std.testing.expectEqualStrings("~/local/share", fileCtx.file);

    const args2 = "test file";
    var parser2 = try parse.Parser.fromStr(args2, ' ', testing.allocator);
    defer parser2.deinit();
    try std.testing.expectError(c.commandError.MissingArgument, cmd.executeWithParser(&parser2));
}

test "handle flags" {
    const cmdContext = struct {
        const Self = @This();
        const Cmd = c.command(Self);

        int: i64 = 0,
        cb: ?*const fn (ctx: *Self, cmd: *Cmd) void = null,

        pub fn call(self: *Self, cmd: *Cmd) void {
            if (self.cb) |cb| {
                cb(self, cmd);
            }
        }

        fn testFlag(self: *Self, cmd: *Cmd) void {
            if (cmd.getFlag("flag")) |flag| {
                self.int = @as(i64, flag.Integer);
            }
        }
    };

    var cmd = c.command(cmdContext).init(testing.allocator);
    defer cmd.deinit();

    var fooCtx = cmdContext{ .cb = cmdContext.testFlag };
    var fooCmd = try cmd.addCommand(.{ .use = "foo", .serve = &fooCtx });
    try fooCmd.addFlag(.{ .use = "flag", .short = "f", .value = .{ .Integer = 69 } });
    const args1 = "test foo";
    var parser1 = try parse.Parser.fromStr(args1, ' ', testing.allocator);
    defer parser1.deinit();
    try cmd.executeWithParser(&parser1);

    try std.testing.expect(fooCtx.int == 69);

    const args2 = "test foo -f 420";
    var parser2 = try parse.Parser.fromStr(args2, ' ', testing.allocator);
    defer parser2.deinit();
    try cmd.executeWithParser(&parser2);
    try std.testing.expect(fooCtx.int == 420);
}

test "show command usage" {
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

    var cmd = c.command(cmdContext){ .alloc = testing.allocator, .config = .{ .use = "test", .short = "short cmd description" } };
    try cmd.addFlag(.{ .use = "help", .short = "h", .comment = "Show this message" });
    defer cmd.deinit();

    var fileCtx = cmdContext{};
    _ = try cmd.addCommand(.{ .use = "foo", .serve = &fileCtx });
    _ = try cmd.addCommand(.{ .use = "baz", .serve = &fileCtx });
    _ = try cmd.addCommand(.{ .use = "bar", .serve = &fileCtx });

    try std.testing.expectEqualStrings(" \nshort cmd description\n\nUsage:\n  test [command]\n\nAvailable Commands:\n  baz\n  bar\n  foo\n\nFlags:\n  --help | -h\tShow this message\n\n", try cmd.usage());
}
