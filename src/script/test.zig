const std = @import("std");
const parser = @import("parser.zig");
const Token = parser.Token;

test "tokenizer" {
    {
        const input = "hello, world!";

        var token_iter = parser.Tokenizer.init(std.testing.allocator, input);
        defer token_iter.deinit();

        const expected_tokens = .{
            Token{ .kind = .{ .Word = "hello" }, .location = .{ .line = 0, .char = 0, .file = null } },
            Token{ .kind = .Comma, .location = .{ .line = 0, .char = 5, .file = null } },
            Token{ .kind = .Space, .location = .{ .line = 0, .char = 6, .file = null } },
            Token{ .kind = .{ .Word = "world" }, .location = .{ .line = 0, .char = 7, .file = null } },
            Token{ .kind = .Bang, .location = .{ .line = 0, .char = 12, .file = null } },
        };

        try std.testing.expectEqualDeep(expected_tokens[0], token_iter.iterator.next());
    }
    {
        const input =
            \\first_line\n
            \\second_line"
        ;

        var token_iter = parser.Tokenizer.init(std.testing.allocator, input);
        defer token_iter.deinit();

        const expected_tokens = .{
            Token{ .kind = .{ .Word = "first_line" }, .location = .{ .line = 0, .char = 0, .file = null } },
            Token{ .kind = .NewLine, .location = .{ .line = 0, .char = 10, .file = null } },
            Token{ .kind = .{ .Word = "second_line" }, .location = .{ .line = 1, .char = 0, .file = null } },
        };

        try std.testing.expectEqualDeep(expected_tokens[0], token_iter.iterator.next());
    }
    {
        const input = "~./#\"hello\"\"";

        var token_iter = parser.Tokenizer.init(std.testing.allocator, input);
        defer token_iter.deinit();

        const expected_tokens = .{
            Token{ .kind = .Tilde, .location = .{ .line = 0, .char = 0, .file = null } },
            Token{ .kind = .Dot, .location = .{ .line = 0, .char = 1, .file = null } },
            Token{ .kind = .Slash, .location = .{ .line = 0, .char = 2, .file = null } },
            Token{ .kind = .Hash, .location = .{ .line = 0, .char = 3, .file = null } },
            Token{ .kind = .{ .DoubleQuote = "hello" }, .location = .{ .line = 0, .char = 4, .file = null } },
            Token{ .kind = .{ .DoubleQuote = null }, .location = .{ .line = 0, .char = 4, .file = null } },
        };

        try std.testing.expectEqualDeep(expected_tokens[0], token_iter.iterator.next());
    }
}
