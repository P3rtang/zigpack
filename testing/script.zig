const std = @import("std");
const s = @import("script");
const debug = @import("debug");

// test "parse_json" {
//     const json =
//         \\{
//         \\  "name": "test",
//         \\  "description": "testing script module",
//         \\  "script": 42069,
//         \\  "dependencies": [
//         \\      "cmake",
//         \\      "rustup"
//         \\  ],
//         \\  "env": {}
//         \\}
//     ;

//     const script = try s.Script.fromJSON(std.testing.allocator, json);
//     defer script.deinit();

//     try std.testing.expectEqualStrings("test", script.value.data.name);

//     const deps: []const []const u8 = &.{ "cmake", "rustup" };
//     for (script.value.data.dependencies, 0..) |dep, i| {
//         try std.testing.expectEqualStrings(dep, deps[i]);
//     }
// }

// test "read_script" {
//     const alloc = std.testing.allocator;
//     const json =
//         \\{
//         \\  "name": "test",
//         \\  "description": "testing script module",
//         \\  "script": 42069,
//         \\  "dependencies": [
//         \\      "cmake",
//         \\      "rustup"
//         \\  ],
//         \\  "env": {}
//         \\}
//     ;

//     var script = try s.Script.fromJSON(alloc, json);
//     defer script.deinit();

//     script.value.scriptDir("./testing");

//     var script_iter = try script.value.scriptContent();

//     {
//         const child: std.process.Child = script_iter.next().?;
//         try std.testing.expectEqualStrings("Hello, world!", child.argv[1]);
//     }
//     {
//         const child: std.process.Child = script_iter.next().?;
//         try std.testing.expectEqualStrings(std.posix.getenv("HOME").?, child.argv[1]);
//     }
//     {
//         const child: std.process.Child = script_iter.next().?;
//         try std.testing.expectEqualStrings("Hello, world!", child.argv[1]);
//     }
// }

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

        const iter = try script.value.scriptContent();
        var runner = s.ScriptRunner.init(alloc, iter);

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
