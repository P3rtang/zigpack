const std = @import("std");
const parser = @import("parser.zig");

test "tokenizer" {
    const input = "hello, world!";

    const token_iter = parser.Tokenizer.new(input);

    const expected_tokens = .{parser.Token{
        .kind = .{ .Word = "hello" },
        .location = .{ .line = 0, .char = 0, .file = null },
    }};

    std.testing.expectEqualDeep(expected_tokens[0], token_iter.next());
}
