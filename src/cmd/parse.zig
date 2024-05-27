const mem = @import("std").mem;
const std = @import("std");

const str = []const u8;

const parserError = error{
    InvalidToken,
    FlagWithoutName,
};

const token = struct {
    kind: tokenKind,
    content: []const u8,

    fn fromStr(string: str) !token {
        if (string.len == 0) {
            return error.InvalidToken;
        }
        switch (string[0]) {
            '-' => {
                if (string.len < 2) {
                    return error.FlagWithoutName;
                }
                switch (string[1]) {
                    '-' => {
                        if (string.len == 2) {
                            return token{ .kind = tokenKind.dash_separator, .content = "" };
                        }
                        return token{ .kind = tokenKind.flag, .content = string[2..] };
                    },
                    else => {
                        return token{ .kind = tokenKind.short_flag, .content = string[1..] };
                    },
                }
            },
            else => {
                return token{ .kind = tokenKind.argument, .content = string };
            },
        }
    }
};

const tokenKind = enum {
    argument,
    flag,
    short_flag,
    dash_separator,
    Invalid,
};

pub const Parser = struct {
    index: u32 = 0,
    content: []str,
    alloc: std.mem.Allocator,

    pub fn new(alloc: std.mem.Allocator) !Parser {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();

        var contentList = std.ArrayList([]const u8).init(alloc);
        var i: u32 = 0;
        while (args.next()) |arg| : (i += 1) {
            try contentList.append(arg);
        }
        return Parser{
            .content = try contentList.toOwnedSlice(),
            .alloc = alloc,
        };
    }

    pub fn fromStr(string: str, delim: u8, alloc: std.mem.Allocator) !Parser {
        var split = mem.splitScalar(u8, string, delim);

        var contentList = std.ArrayList([]const u8).init(alloc);
        var i: u32 = 0;
        while (split.next()) |arg| : (i += 1) {
            try contentList.append(arg);
        }
        return Parser{
            .content = try contentList.toOwnedSlice(),
            .alloc = alloc,
        };
    }

    pub fn next(self: *Parser) ?token {
        if (self.content.len <= self.index) {
            return null;
        }
        const raw = self.content[self.index];
        const tok = token.fromStr(raw) catch return null;

        self.index += 1;
        return tok;
    }

    pub fn peek(self: *Parser) ?token {
        const raw = self.content[self.index];
        return token.fromStr(raw) catch return null;
    }

    pub fn deinit(self: *const Parser) void {
        self.alloc.free(self.content);
    }
};
