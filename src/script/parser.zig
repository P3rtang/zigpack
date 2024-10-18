const Iterator = @import("utils").Iterator;

pub const Token = struct {
    kind: TokenKind,
    location: Location,
};

const Location = struct {
    line: usize,
    char: usize,
    file: ?[]const u8,
};

pub const TokenKind = union(enum) {
    Word: []const u8,
    Value: isize,
    NewLine: void,
    Space: void,
    DoubleQuote: []const u8,
    Dot: void,
    Slash: u8,
    Hash: void,
};

pub const Tokenizer = struct {
    const Self = @This();

    iterator: Iterator(Token) = .{ .nextFn = Self.next },
    content: []const u8,

    pub fn new(content: []const u8) Iterator(Token) {
        const self = Tokenizer{ .content = content };
        return self.iterator;
    }

    fn next(i: *Iterator(Token)) Token {
        const self = i.cast(Self);

        switch (self.content[i]) {
            ' ' => return .{ .kind = .Space },
            '\n' => return .{ .kind = .NewLine },
            '#' => return .{ .kind = .Hash },
            '.' => return .{ .kind = .Dot },
            '/' => return .{ .kind = .Slash },
            else => |_| {},
        }
    }
};
