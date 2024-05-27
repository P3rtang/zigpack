const std = @import("std");
const s = @import("script.zig");

test "parse_json" {
    const json =
        \\{
        \\  "name": "test",
        \\  "description": "testing script module",
        \\  "script": 42069,
        \\  "dependencies": [
        \\      "cmake",
        \\      "rustup"
        \\  ]
        \\}
    ;

    const script = try s.Script.fromJSON(std.testing.allocator, json);
    defer script.deinit();

    try std.testing.expectEqualStrings("test", script.value.name);

    const deps: []const []const u8 = &.{ "cmake", "rustup" };
    for (script.value.dependencies, 0..) |dep, i| {
        try std.testing.expectEqualStrings(dep, deps[i]);
    }
}

test "script_iter" {
    var alloc = std.testing.allocator;
    {
        const script =
            \\echo hello
        ;

        var s_iter = try s.ScriptIter.init(alloc, script);
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

        const expect = [2][]const u8{ "hello,\n", "world!\n" };

        var s_iter = try s.ScriptIter.init(alloc, script);
        defer s_iter.deinit();

        var i: usize = 0;
        var child: ?std.process.Child = try s_iter.next();
        var stdout = std.ArrayList(u8).init(alloc);
        var stderr = std.ArrayList(u8).init(alloc);
        defer {
            stdout.deinit();
            stderr.deinit();
        }

        while (child != null) : (i += 1) {
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
    var alloc = std.testing.allocator;
    {
        const script =
            \\echo "Hello, world!"
        ;

        var s_iter = try s.ScriptIter.init(alloc, script);
        defer s_iter.deinit();

        var child: std.process.Child = (try s_iter.next()).?;
        try std.testing.expectEqualStrings("Hello, world!", child.argv[1]);
    }
    {
        const script =
            \\echo "\"Hello, world!\""
        ;

        var s_iter = try s.ScriptIter.init(alloc, script);
        defer s_iter.deinit();

        var child: std.process.Child = (try s_iter.next()).?;
        try std.testing.expectEqualStrings("\"Hello, world!\"", child.argv[1]);
    }
}

test "read_script" {
    var alloc = std.testing.allocator;
    const json =
        \\{
        \\  "name": "test",
        \\  "description": "testing script module",
        \\  "script": 42069,
        \\  "dependencies": [
        \\      "cmake",
        \\      "rustup"
        \\  ]
        \\}
    ;

    var script = try s.Script.fromJSON(alloc, json);
    defer script.deinit();

    var script_iter = try script.value.scriptContent(alloc);
    defer script_iter.deinit();

    var child: std.process.Child = (try script_iter.next()).?;
    try std.testing.expectEqualStrings("Hello, world!", child.argv[1]);
}
