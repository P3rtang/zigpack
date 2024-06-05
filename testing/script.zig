const std = @import("std");
const s = @import("script");

test "parse_json" {
    const json =
        \\{
        \\  "name": "test",
        \\  "description": "testing script module",
        \\  "script": 42069,
        \\  "dependencies": [
        \\      "cmake",
        \\      "rustup"
        \\  ],
        \\  "env": {}
        \\}
    ;

    const script = try s.Script.fromJSON(std.testing.allocator, json);
    defer script.deinit();

    try std.testing.expectEqualStrings("test", script.value.data.name);

    const deps: []const []const u8 = &.{ "cmake", "rustup" };
    for (script.value.data.dependencies, 0..) |dep, i| {
        try std.testing.expectEqualStrings(dep, deps[i]);
    }
}

test "script_iter" {
    const alloc = std.testing.allocator;
    {
        const script =
            \\echo hello
        ;

        var s_iter = try s.ScriptIter.init(alloc, script, .{});
        defer s_iter.deinit();
        var child = (try s_iter.next()).?;

        try std.testing.expectEqualStrings("echo", child.argv[0]);
        try std.testing.expectEqualStrings("hello", child.argv[1]);

        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        var stdout = std.ArrayList(u8).init(alloc);
        var stderr = std.ArrayList(u8).init(alloc);
        defer {
            stdout.deinit();
            stderr.deinit();
        }

        try child.spawn();
        try child.collectOutput(&stdout, &stderr, 1024);
        try std.testing.expectEqualStrings("echo", child.argv[0]);
        try std.testing.expectEqualStrings("hello\n", stdout.items);
    }
    {
        const script =
            \\echo hello,
            \\echo world!
        ;

        const expect: []const []const u8 = &.{ "hello,\n", "world!\n" };

        var s_iter = try s.ScriptIter.init(alloc, script, .{});
        defer s_iter.deinit();

        var i: usize = 0;
        var child: ?std.process.Child = try s_iter.next();
        while (child != null) : (i += 1) {
            var stdout = std.ArrayList(u8).init(alloc);
            var stderr = std.ArrayList(u8).init(alloc);
            defer {
                stdout.deinit();
                stderr.deinit();
            }

            child.?.stdout_behavior = .Pipe;
            child.?.stderr_behavior = .Pipe;

            try child.?.spawn();
            try child.?.collectOutput(&stdout, &stderr, 4096);
            _ = try child.?.wait();

            try std.testing.expectEqualStrings(expect[i], stdout.items);

            child = try s_iter.next();
        }
    }
}

test "quotes" {
    const alloc = std.testing.allocator;
    {
        const script =
            \\echo "Hello, world!"
        ;

        var s_iter = try s.ScriptIter.init(alloc, script, .{});
        defer s_iter.deinit();

        const child: std.process.Child = (try s_iter.next()).?;
        try std.testing.expectEqualStrings("Hello, world!", child.argv[1]);
    }
    {
        const script =
            \\echo "\"Hello, world!\""
        ;

        var s_iter = try s.ScriptIter.init(alloc, script, .{});
        defer s_iter.deinit();

        const child: std.process.Child = (try s_iter.next()).?;
        try std.testing.expectEqualStrings("\"Hello, world!\"", child.argv[1]);
    }
}

test "read_script" {
    const alloc = std.testing.allocator;
    const json =
        \\{
        \\  "name": "test",
        \\  "description": "testing script module",
        \\  "script": 42069,
        \\  "dependencies": [
        \\      "cmake",
        \\      "rustup"
        \\  ],
        \\  "env": {}
        \\}
    ;

    var script = try s.Script.fromJSON(alloc, json);
    defer script.deinit();

    script.value.scriptDir("./testing");

    var script_iter = try script.value.scriptContent();
    defer script_iter.deinit();

    const child: std.process.Child = (try script_iter.next()).?;
    try std.testing.expectEqualStrings("Hello, world!", child.argv[1]);
    const child2: std.process.Child = (try script_iter.next()).?;
    try std.testing.expectEqualStrings("Hello, world!", child2.argv[1]);
}

test "execute_script" {
    const alloc = std.testing.allocator;
    {
        const json =
            \\{
            \\  "name": "test",
            \\  "description": "testing script module",
            \\  "script": 42069,
            \\  "dependencies": [
            \\      "cmake",
            \\      "rustup"
            \\  ],
            \\  "env": {}
            \\}
        ;

        var script = try s.Script.fromJSON(alloc, json);
        defer script.deinit();
        script.value.scriptDir("./testing");
        var iter = try script.value.scriptContent();

        var runner = try s.ScriptRunner.init(&iter);

        var stdout = std.ArrayList(u8).init(alloc);
        var stderr = std.ArrayList(u8).init(alloc);
        var stdout_w = stdout.writer().any();
        var stderr_w = stdout.writer().any();
        defer {
            stdout.deinit();
            stderr.deinit();
        }

        runner.collectOutput(&stdout_w, &stderr_w, .{});
        try runner.execNext();

        try std.testing.expectStringStartsWith(stdout.items, "Hello, world!\n");
    }
}
