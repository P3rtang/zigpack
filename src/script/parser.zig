const std = @import("std");
const debug = @import("debug");
const Iterator = @import("utils").Iterator;

pub const Token = struct {
    kind: TokenKind,
    location: Location,

    pub fn new(kind: TokenKind, line: usize, char: usize, file: ?[]const u8) Token {
        return .{ .kind = kind, .location = .{ .line = line, .char = char, .file = file } };
    }
};

const Location = struct {
    line: usize,
    char: usize,
    file: ?[]const u8 = null,
};

pub const TokenKind = union(enum) {
    Word: []const u8,
    Value: isize,
    NewLine,
    Space,
    DoubleQuote: ?[]const u8,
    Dot,
    Comma,
    Slash,
    Hash,
    Bang,
    Tilde,
};

pub const Tokenizer = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,

    iterator: Iterator(Token) = .{ .nextFn = Self.next },
    content: []const u8,
    line: usize = 0,
    char: usize = 0,

    pub fn init(alloc: std.mem.Allocator, content: []const u8) Self {
        return Tokenizer{ .arena = std.heap.ArenaAllocator.init(alloc), .content = content };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }

    fn next(iter: *Iterator(Token)) ?Token {
        const self = iter.cast(Self);

        if (self.content.len <= iter.index) {
            return null;
        }

        switch (self.content[iter.index]) {
            ' ' => {
                defer self.char += 1;
                return Token.new(.Space, self.line, self.char, null);
            },
            '\n' => {
                defer {
                    self.line += 1;
                    self.char = 0;
                }
                return Token.new(.NewLine, self.line, self.char, null);
            },
            '#' => {
                defer self.char += 1;
                return Token.new(.Hash, self.line, self.char, null);
            },
            '.' => {
                defer self.char += 1;
                return Token.new(.Dot, self.line, self.char, null);
            },
            ',' => {
                defer self.char += 1;
                return Token.new(.Comma, self.line, self.char, null);
            },
            '/' => {
                defer self.char += 1;
                return Token.new(.Slash, self.line, self.char, null);
            },
            '~' => {
                defer self.char += 1;
                return Token.new(.Tilde, self.line, self.char, null);
            },
            '"' => {
                const old_index = iter.index;
                var value = std.ArrayList(u8).init(self.arena.allocator());

                while (self.content.len > iter.index and self.content[iter.index] != '"') : (iter.index += 1) {
                    value.append(self.content[iter.index]) catch {};
                }

                if (self.content.len == iter.index) {
                    iter.index = old_index + 1;
                    defer self.char += 1;
                    return Token.new(.{ .DoubleQuote = null }, self.line, self.char, null);
                } else {
                    defer self.char += value.items.len;
                    return Token.new(.{ .DoubleQuote = value.items }, self.line, self.char, null);
                }
            },
            else => |char| {
                if (!std.ascii.isAlphanumeric(char) or char == '_') {
                    std.debug.panic(
                        "Unrecognised Character: {}, line {d}, char {d}",
                        .{ char, self.line, self.char },
                    );
                }

                var value = std.ArrayList(u8).init(self.arena.allocator());
                value.append(char) catch {};
                iter.index += 1;

                while (self.content.len > iter.index and
                    std.ascii.isAlphanumeric(self.content[iter.index]) or
                    self.content[iter.index] == '_') : (iter.index += 1)
                {
                    value.append(self.content[iter.index]) catch {};
                }

                const len = value.items.len;
                defer self.char += len;

                return Token.new(
                    .{ .Word = value.items },
                    self.line,
                    self.char,
                    null,
                );
            },
        }

        return null;
    }
};
