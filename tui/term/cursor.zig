const std = @import("std");
const super = @import("mod.zig");

const Pos = super.super.Pos;
const Self = @This();

term: *super.Term,
context: *anyopaque,
getPos: *const fn (*anyopaque) Pos,

pub fn pos(self: *Self) Pos {
    self.getPos(self.context);
}

pub fn setShape(self: *const Self, shape: CursorShape) !void {
    try self.term.write(shape.code());
}

pub fn show(self: *const Self) !void {
    try self.term.write("\x1b[?25h");
}

pub fn hide(self: *const Self) !void {
    try self.term.write("\x1b[?25l\x1b[?50l");
}

pub fn move(self: *const Self, position: Pos) !void {
    try self.term.print("\x1b[{};{}f", .{ position.y + 1, position.x + 1 });
}

pub fn movex(self: *Self, x: usize) !void {
    self.move(.{ .x = x, .y = self.pos.y });
}

pub fn movey(self: *Self, y: usize) !void {
    self.move(.{ .x = self.pos.x, .y = y });
}

pub const CursorShape = enum {
    Block,
    Line,

    pub fn code(self: CursorShape) []const u8 {
        return switch (self) {
            .Block => "\x1b[2 q",
            .Line => "\x1b[5 q",
        };
    }
};
