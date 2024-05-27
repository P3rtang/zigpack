const std = @import("std");
const str = @import("string").str;

pub const Script = struct {
    name: []const u8,
    description: []const u8 = "",
    comment: []const u8 = "",
    script: u16,
    dependencies: [][]const u8 = &.{},
    build_dependencies: [][]const u8 = &.{},
    script_directory: []const u8 = "./.test",

    pub fn fromJSON(alloc: std.mem.Allocator, json: []const u8) !std.json.Parsed(Script) {
        return try std.json.parseFromSlice(Script, alloc, json, .{});
    }

    pub fn scriptContent(self: *Script, alloc: std.mem.Allocator) !ScriptIter {
        var arena_alloc = std.heap.ArenaAllocator.init(alloc);
        var arena = arena_alloc.allocator();
        defer arena_alloc.deinit();

        const dir_path = try std.fs.realpathAlloc(arena, self.script_directory);
        std.log.warn("{s}", .{dir_path});

        var dir = try std.fs.openDirAbsolute(dir_path, .{});
        defer dir.close();

        const file_name = try std.fmt.allocPrint(arena, "{}.sh", .{self.script});
        var file = try dir.openFile(file_name, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        const reader = buf_reader.reader();
        var content = std.ArrayList(u8).init(arena);
        try reader.readAllArrayList(&content, try file.getEndPos());

        const script_iter = ScriptIter.init(alloc, try content.toOwnedSlice());
        return script_iter;
    }

    pub fn exec(self: *Script) !void {
        _ = self;
    }
};

pub const ScriptIter = struct {
    index: usize = 0,
    count: usize = 0,
    content: []ScriptToken,
    alloc: std.heap.ArenaAllocator,

    pub fn init(alloc: std.mem.Allocator, content: []const u8) !ScriptIter {
        var arena = std.heap.ArenaAllocator.init(alloc);
        var tokens = std.ArrayList(ScriptToken).init(arena.allocator());
        defer tokens.deinit();

        var values = std.ArrayList(u8).init(arena.allocator());
        var kind: ?TokenKind = null;
        var i: usize = 0;

        while (i < content.len) : (i += 1) {
            switch (content[i]) {
                '\n' => {
                    if (kind) |k| {
                        try addToken(&tokens, k, try values.toOwnedSlice());
                    }
                    try tokens.append(.{ .NewLine = '\n' });
                    kind = .NewLine;
                },

                ' ' => {
                    if (kind) |k| {
                        try addToken(&tokens, k, try values.toOwnedSlice());
                    }
                    try tokens.append(.{ .Space = ' ' });
                    kind = .Space;
                },

                '"' => {
                    i += 1;
                    while (content[i] != '"') : (i += 1) {
                        if (content[i] == '\\') {
                            i += 1;
                        }
                        try values.append(content[i]);
                    }
                    kind = .DoubleQuote;
                },

                '\\' => {
                    i += 1;
                    try values.append(content[i]);
                    kind = .Word;
                },

                else => |char| {
                    try values.append(char);
                    if (kind == null) {
                        if (std.ascii.isDigit(char)) {
                            kind = .Value;
                        }
                        kind = .Word;
                        continue;
                    }
                    switch (kind.?) {
                        .Word => {},
                        .Value => {
                            if (!std.ascii.isDigit(char)) {
                                return error.InvalidExpression;
                            }
                        },
                        else => {
                            if (std.ascii.isDigit(char)) {
                                kind = .Value;
                            }
                            kind = .Word;
                        },
                    }
                },
            }
        }

        if (kind) |k| {
            switch (k) {
                .NewLine, .Space => {},
                else => try addToken(&tokens, k, try values.toOwnedSlice()),
            }
        }

        return ScriptIter{
            .content = try tokens.toOwnedSlice(),
            .alloc = arena,
        };
    }

    fn addToken(list: *std.ArrayList(ScriptToken), kind: TokenKind, value: []const u8) !void {
        switch (kind) {
            .Word => {
                try list.append(.{ .Word = value });
            },
            .Value => {
                try list.append(.{ .Value = try std.fmt.parseInt(i32, value, 10) });
            },
            .DoubleQuote => {
                try list.append(.{ .DoubleQuote = value });
            },
            .Space => {
                try list.append(.{ .Space = ' ' });
            },
            .NewLine => {
                try list.append(.{ .NewLine = '\n' });
            },
        }
    }

    pub fn deinit(self: ScriptIter) void {
        self.alloc.deinit();
    }

    pub fn next(self: *ScriptIter) !?std.process.Child {
        var args = std.ArrayList([]const u8).init(self.alloc.allocator());

        loop: while (self.count < self.content.len) : (self.count += 1) {
            switch (self.content[self.count]) {
                .Word => |val| try args.append(val),
                .Value => |val| try args.append(try std.fmt.allocPrint(self.alloc.allocator(), "{d}", .{val})),
                .DoubleQuote => |val| try args.append(try std.fmt.allocPrint(self.alloc.allocator(), "{s}", .{val})),
                .Space => {},
                .NewLine => break :loop,
            }
        }
        if (args.items.len > 0) {
            return std.process.Child.init(try args.toOwnedSlice(), self.alloc.allocator());
        } else {
            return null;
        }
    }
};

const ScriptToken = union(TokenKind) {
    Word: []const u8,
    Value: i32,
    NewLine: u8,
    Space: u8,
    DoubleQuote: []const u8,
};

const TokenKind = enum {
    Word,
    Value,
    NewLine,
    Space,
    DoubleQuote,
};
