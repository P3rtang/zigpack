const std = @import("std");
const parser = @import("script").parser;
const Token = parser.Token;

test "tokenizer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    {
        const input = "hello, world!";

        var token_iter = parser.Tokenizer.init(&arena, input);

        const expected_tokens: [5]Token = .{
            Token{ .kind = .{ .Word = "hello" }, .location = .{ .line = 0, .char = 0, .file = null } },
            Token{ .kind = .Comma, .location = .{ .line = 0, .char = 5, .file = null } },
            Token{ .kind = .Space, .location = .{ .line = 0, .char = 6, .file = null } },
            Token{ .kind = .{ .Word = "world" }, .location = .{ .line = 0, .char = 7, .file = null } },
            Token{ .kind = .Bang, .location = .{ .line = 0, .char = 12, .file = null } },
        };

        for (expected_tokens) |token| {
            try std.testing.expectEqualDeep(token, token_iter.iterator.next());
        }
    }
    {
        const input =
            \\first_line
            \\second_line
        ;

        var token_iter = parser.Tokenizer.init(&arena, input);

        const expected_tokens: [3]Token = .{
            Token{ .kind = .{ .Word = "first_line" }, .location = .{ .line = 0, .char = 0, .file = null } },
            Token{ .kind = .NewLine, .location = .{ .line = 0, .char = 10, .file = null } },
            Token{ .kind = .{ .Word = "second_line" }, .location = .{ .line = 1, .char = 0, .file = null } },
        };

        for (expected_tokens) |token| {
            try std.testing.expectEqualDeep(token, token_iter.iterator.next());
        }
    }
    {
        const input = "~./#\"hello\"\"-$";

        var token_iter = parser.Tokenizer.init(&arena, input);

        const expected_tokens: [8]Token = .{
            Token{ .kind = .Tilde, .location = .{ .line = 0, .char = 0, .file = null } },
            Token{ .kind = .Dot, .location = .{ .line = 0, .char = 1, .file = null } },
            Token{ .kind = .Slash, .location = .{ .line = 0, .char = 2, .file = null } },
            Token{ .kind = .Hash, .location = .{ .line = 0, .char = 3, .file = null } },
            Token{ .kind = .{ .DoubleQuote = "hello" }, .location = .{ .line = 0, .char = 4, .file = null } },
            Token{ .kind = .{ .DoubleQuote = null }, .location = .{ .line = 0, .char = 11, .file = null } },
            Token{ .kind = .Dash, .location = .{ .line = 0, .char = 12, .file = null } },
            Token{ .kind = .Dollar, .location = .{ .line = 0, .char = 13, .file = null } },
        };

        for (expected_tokens) |token| {
            try std.testing.expectEqualDeep(token, token_iter.iterator.next());
        }
    }
    {
        const input =
            \\echo "hello"
            \\echo "hello"
        ;

        var token_iter = parser.Tokenizer.init(&arena, input);

        const expected_tokens: [7]Token = .{
            Token{ .kind = .{ .Word = "echo" }, .location = .{ .line = 0, .char = 0, .file = null } },
            Token{ .kind = .Space, .location = .{ .line = 0, .char = 4, .file = null } },
            Token{ .kind = .{ .DoubleQuote = "hello" }, .location = .{ .line = 0, .char = 5, .file = null } },
            Token{ .kind = .NewLine, .location = .{ .line = 0, .char = 12, .file = null } },
            Token{ .kind = .{ .Word = "echo" }, .location = .{ .line = 1, .char = 0, .file = null } },
            Token{ .kind = .Space, .location = .{ .line = 1, .char = 4, .file = null } },
            Token{ .kind = .{ .DoubleQuote = "hello" }, .location = .{ .line = 1, .char = 5, .file = null } },
        };

        for (expected_tokens) |token| {
            try std.testing.expectEqualDeep(token, token_iter.iterator.next());
        }
    }
}
