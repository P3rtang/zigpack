const std = @import("std");
pub const super = @import("../lib.zig");

pub const TTY = @import("tty.zig");
pub const Cursor = @import("cursor.zig");

const F = std.os.linux.F;
const O = std.os.linux.O;
const Pos = super.Pos;

pub const Term = struct {
    const Self = @This();

    termios: ?std.os.linux.termios = null,

    arena: *std.heap.ArenaAllocator,
    context: *anyopaque,

    getHandle: ?*const fn (*anyopaque) i32 = null,
    writeFn: *const fn (*anyopaque, bytes: []const u8) anyerror!void,
    pollKeyFn: *const fn (*anyopaque) PollKeyError!?Key,
    getCursorFn: *const fn (*anyopaque, *Term) CursorError!Cursor,
    flushFn: ?*const fn (*anyopaque) anyerror!void = null,

    termCodeFn: *const fn (*anyopaque, code: TermCode) anyerror!void,

    pub fn write(self: *Self, bytes: []const u8) !void {
        return self.writeFn(self.context, bytes);
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        try self.write(try std.fmt.allocPrint(self.arena.allocator(), fmt, args));
    }

    pub fn flush(self: *Self) !void {
        if (self.flushFn) |func| {
            try func(self.context);
        }
    }

    pub fn nonBlock(self: *Self, set: bool) !void {
        if (self.getHandle) |getHandle| {
            const handle = getHandle(self.context);

            const flags = try std.posix.fcntl(handle, F.GETFL, 0);
            const non_block: u32 = @bitCast(O{ .NONBLOCK = true });
            if (set) {
                _ = try std.posix.fcntl(handle, F.SETFL, flags | non_block);
            } else {
                _ = try std.posix.fcntl(handle, F.SETFL, flags & ~non_block);
            }
        }
    }

    pub fn intoRaw(self: *Self) !void {
        if (self.getHandle) |getHandle| {
            try self.nonBlock(true);
            if (self.termios) |t| {
                var termios = t;
                termios.lflag.ECHO = false;
                termios.lflag.ICANON = false;
                termios.lflag.ISIG = false;
                termios.lflag.IEXTEN = false;

                termios.iflag.IXON = false;
                termios.iflag.ICRNL = false;
                termios.iflag.BRKINT = false;
                termios.iflag.INPCK = false;
                termios.iflag.ISTRIP = false;

                termios.oflag.OPOST = false;

                try self.write("\x1b[?1049h");

                if (std.os.linux.tcsetattr(getHandle(self.context), .FLUSH, &termios) != 0) {
                    return error.IntoRaw;
                }
            }
        }
    }

    pub fn intoCanon(self: *Self) !void {
        if (self.getHandle) |getHandle| {
            try self.setNonBlock(false);

            try self.writer.writeAll("\x1B[?47l");
            try self.writer.writeAll("\x1B[u");
            try self.writer.writeAll("\x1B[?1049l");

            if (self.termios) |termios| {
                if (std.os.linux.tcsetattr(getHandle(self.context), .FLUSH, &termios) != 0) {
                    return error.IntoCannon;
                }
            }
        }
    }

    pub fn clearTerm(self: *Self) !void {
        try self.write("\x1b[2J");
    }

    pub fn pollKey(self: *Self) !?Key {
        return self.pollKeyFn(self.context);
    }

    pub fn cursor(self: *Self) !Cursor {
        return self.getCursorFn(self.context, self);
    }

    pub fn drawHorzLine(self: *Self, pos: Pos, len: usize) !void {
        const c = try self.cursor();
        for (0..len) |i| {
            const offset: usize = @intCast(i);
            try c.move(.{ .x = pos.x + offset, .y = pos.y });
            try self.write("─");
        }
    }

    pub fn drawVertLine(self: *Self, pos: Pos, len: usize) !void {
        const c = try self.cursor();
        for (0..len) |i| {
            const offset: usize = @intCast(i);
            try c.move(.{ .x = pos.x, .y = pos.y + offset });
            try self.write("│");
        }
    }
};

const TermError = error{
    IntoRaw,
    IntoCannon,
};

const PollKeyError = error{
    WouldBlock,
    ReadError,
};

const CursorError = error{
    ReadError,
    // TODO: figure out how to make this be an enum of TermError and ReadError
    TermError,
};

pub const Key = union(KeyCode) {
    CTRLC,
    BACKSPACE,
    TAB,
    ENTER,
    ESC,
    DEL,
    CHAR: u8,
};

pub const KeyCode = enum(u8) {
    CTRLC = 3,
    BACKSPACE = 8,
    TAB = 9,
    ENTER = 13,
    ESC = 27,
    DEL = 127,
    CHAR,
};

pub const TermCode = enum {
    AlternateBuffer,
    AlternateBufferExit,

    pub fn toString(self: TermCode) []const u8 {
        return switch (self) {
            .AlternateBuffer => "\x1b[?1049h",
            .AlternateBufferExit => "\x1b[?1049l",
        };
    }
};
