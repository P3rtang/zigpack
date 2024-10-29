const std = @import("std");
const debug = @import("debug");
const Iterator = @import("utils").Iterator;
const IteratorBox = @import("utils").IteratorBox;

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
    Dash,
    Dollar,
};

pub const Tokenizer = struct {
    const Self = @This();

    arena: *std.heap.ArenaAllocator,

    iterator: Iterator(Token) = Iterator(Token){ .nextFn = next, .methods = .{
        .resetFn = reset,
        .peekFn = peek,
    } },
    content: []const u8,

    index: usize = 0,
    line: usize = 0,
    // INFO: self.char is different from self.index because of newlines
    char: usize = 0,

    pub fn init(arena: *std.heap.ArenaAllocator, content: []const u8) *IteratorBox(Token) {
        const tokenizer = arena.allocator().create(Tokenizer) catch std.debug.panic("Out of Memory, buy more RAM", .{});
        tokenizer.* = Tokenizer{ .arena = arena, .content = content };

        const iter = tokenizer.iterator.box(arena);
        return iter;
    }

    fn next(iter: *Iterator(Token)) ?Token {
        const self = iter.cast(Self);

        if (self.content.len <= self.index) {
            return null;
        }

        switch (self.content[self.index]) {
            ' ' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Space, self.line, self.char, null);
            },
            '\n' => {
                defer {
                    self.line += 1;
                    self.char = 0;
                    self.index += 1;
                }
                return Token.new(.NewLine, self.line, self.char, null);
            },
            '#' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Hash, self.line, self.char, null);
            },
            '.' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Dot, self.line, self.char, null);
            },
            ',' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Comma, self.line, self.char, null);
            },
            '!' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Bang, self.line, self.char, null);
            },
            '/' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Slash, self.line, self.char, null);
            },
            '~' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Tilde, self.line, self.char, null);
            },
            '"' => {
                const old_index = self.index;
                self.index += 1;
                var value = std.ArrayList(u8).init(self.arena.allocator());

                while (self.content.len > self.index and self.content[self.index] != '"') : (self.index += 1) {
                    value.append(self.content[self.index]) catch {};
                }

                if (self.content.len == self.index) {
                    self.index = old_index + 1;
                    defer self.char += 1;
                    return Token.new(.{ .DoubleQuote = null }, self.line, self.char, null);
                } else {
                    self.index += 1;
                    defer self.char += value.items.len + 2;
                    return Token.new(.{ .DoubleQuote = value.items }, self.line, self.char, null);
                }
            },
            '-' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Dash, self.line, self.char, null);
            },
            '$' => {
                defer {
                    self.char += 1;
                    self.index += 1;
                }
                return Token.new(.Dollar, self.line, self.char, null);
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
                self.index += 1;

                while (self.content.len > self.index and
                    (std.ascii.isAlphanumeric(self.content[self.index]) or
                    self.content[self.index] == '_')) : (self.index += 1)
                {
                    value.append(self.content[self.index]) catch {};
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

    fn peek(iter: *Iterator(Token)) ?Token {
        const self = iter.cast(Self);
        const old_index = self.index;
        defer self.index = old_index;
        return iter.next();
    }

    fn reset(iter: *Iterator(Token)) void {
        var self = iter.cast(Self);
        self.index = 0;
    }
};
