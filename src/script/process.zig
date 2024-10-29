const std = @import("std");
const debug = @import("debug");
const utils = @import("utils");
const Token = @import("parser.zig").Token;

const Iterator = utils.Iterator;
const IteratorBox = utils.IteratorBox;
const PeekableBox = utils.PeekableBox;

const Self = @This();

alloc: *std.heap.ArenaAllocator,
iterator: Iterator(anyerror!std.ChildProcess),
tokens: *PeekableBox(Token),

pub fn init(arena: *std.heap.ArenaAllocator, tokens: *PeekableBox(Token)) *IteratorBox(anyerror!std.ChildProcess) {
    const iter = Iterator(anyerror!std.ChildProcess){ .nextFn = Self.next, .methods = .{ .resetFn = reset } };

    const self = arena.allocator().create(Self) catch std.debug.panic("Out of Memory, buy more RAM", .{});
    self.* = .{ .alloc = arena, .iterator = iter, .tokens = tokens };

    return self.iterator.box(arena);
}

pub fn deinit(self: *Self) void {
    self.alloc.deinit();
}

pub fn next(iter: *Iterator(anyerror!std.ChildProcess)) ?anyerror!std.ChildProcess {
    const self = iter.cast(Self);

    var program: ?[]const u8 = null;
    var args = std.ArrayList([]const u8).init(self.alloc.allocator());
    var cur_argument = std.ArrayList(u8).init(self.alloc.allocator());

    while (self.tokens.next()) |token| {
        switch (token.kind) {
            .NewLine => {
                if (cur_argument.items.len > 0) {
                    if (program != null) {
                        try args.append(try cur_argument.toOwnedSlice());
                    } else {
                        program = try cur_argument.toOwnedSlice();
                    }
                }
                if (program != null) {
                    break;
                } else {
                    continue;
                }
            },
            .Space => {
                if (program != null and cur_argument.items.len > 0) {
                    try args.append(try cur_argument.toOwnedSlice());
                } else {
                    program = try cur_argument.toOwnedSlice();
                }
            },
            .Dot => {
                const next_token = self.tokens.peek();
                if (program == null and next_token != null and next_token.?.kind == .Slash) {
                    _ = self.tokens.next();
                    try cur_argument.appendSlice(try std.fs.cwd().realpathAlloc(self.alloc.allocator(), "."));
                    try cur_argument.append('/');
                } else {
                    try cur_argument.append('.');
                }
            },
            .Slash => try cur_argument.append('/'),
            .Word => |val| try cur_argument.appendSlice(val),
            // TODO: parse floats which would look like (.Value, .Dot, .Value)
            .Value => |val| try cur_argument.appendSlice(std.fmt.allocPrint(self.alloc.allocator(), "{d}", .{val}) catch ""),
            .DoubleQuote => |val| {
                if (val) |v| {
                    try cur_argument.appendSlice(v);
                } else {
                    try cur_argument.append('"');
                }
            },
            .Hash => {
                while (self.tokens.next()) |t| {
                    if (t.kind == .NewLine) {
                        break;
                    }
                }
            },
            .Bang => try cur_argument.append('!'),
            .Comma => try cur_argument.append(','),
            .Tilde => {
                if (program != null and std.posix.getenv("HOME") != null) {
                    try cur_argument.appendSlice(std.posix.getenv("HOME").?);
                } else {
                    try cur_argument.append('~');
                }
            },
            .Dash => try cur_argument.append('-'),
            .Dollar => {
                if (self.tokens.next()) |t| {
                    switch (t.kind) {
                        .Word => |val| {
                            if (std.posix.getenv(val)) |env| {
                                try cur_argument.appendSlice(env);
                            } else {
                                std.debug.panic(
                                    "{d}:{d} Environment variable {s} not found",
                                    .{ t.location.line, t.location.char, val },
                                );
                            }
                        },
                        .Space => try cur_argument.append('$'),
                        else => std.debug.panic("$ operator should be followed by a variable or a space", .{}),
                    }
                } else {
                    try cur_argument.append('$');
                }
            },
        }
    }

    if (cur_argument.items.len > 0) {
        if (program != null) {
            try args.append(try cur_argument.toOwnedSlice());
        } else {
            program = try cur_argument.toOwnedSlice();
        }
    }

    if (program) |p| {
        try args.insert(0, p);
        return std.ChildProcess.init(args.items, self.alloc.allocator());
    } else {
        return null;
    }
}

fn reset(iter: *Iterator(anyerror!std.ChildProcess)) void {
    const self = iter.cast(Self);
    self.tokens.iterator.reset();
}
