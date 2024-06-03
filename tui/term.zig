const std = @import("std");
const lib = @import("lib.zig");
const Pos = lib.Pos;
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("fcntl.h");
});

pub const Term = struct {
    const Self = @This();
    const stdout_r = std.io.getStdOut().reader();
    const stdout_w = std.io.getStdOut().writer();

    tty: std.fs.File,
    termios: std.os.linux.termios,

    buffer: std.ArrayList(u8),

    arena: std.heap.ArenaAllocator,

    pub inline fn init(alloc: std.mem.Allocator) !Term {
        const tty: std.fs.File = try std.fs.cwd().openFile("/dev/tty", std.fs.File.OpenFlags{ .mode = .read_write });
        var termios: std.os.linux.termios = undefined;
        _ = std.os.linux.tcgetattr(tty.handle, &termios);

        const buffer = std.ArrayList(u8).init(alloc);

        return Term{
            .tty = tty,
            .termios = termios,

            .buffer = buffer,

            .arena = std.heap.ArenaAllocator.init(alloc),
        };
    }

    pub fn deinit(self: *const Term) void {
        _ = c.fcntl(self.tty.handle, c.F_SETFL, c.fcntl(self.tty.handle, c.F_GETFL) & ~c.O_NONBLOCK);
        try self.intoCanon();
        self.tty.close();
        self.buffer.deinit();
        self.arena.deinit();
    }

    pub fn intoRaw(self: *Self) !void {
        try self.setNonBlock(true);

        var raw = self.termios;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        raw.oflag.OPOST = false;

        try self.writeAll("\x1b[?1049h");

        _ = std.os.linux.tcsetattr(self.tty.handle, .FLUSH, &raw);
    }

    pub fn intoCanon(self: *const Self) !void {
        try self.setNonBlock(false);

        stdout_w.writeAll("\x1B[?47l") catch {};
        stdout_w.writeAll("\x1B[u") catch {};
        stdout_w.writeAll("\x1B[?1049l") catch {};
        _ = std.os.linux.tcsetattr(self.tty.handle, .FLUSH, &self.termios);
    }

    pub fn clearTerm(self: *Self) !void {
        try self.writeAll("\x1b[2J");
    }

    fn toggleNonBlock(self: *const Self) !void {
        if (c.fcntl(self.tty.handle, c.F_SETFL, c.fcntl(self.tty.handle, c.F_GETFL) | c.O_NONBLOCK) != 0) {
            return error.CouldNotToggle;
        }
    }

    fn setNonBlock(self: *const Self, set: bool) !void {
        _ = if (set) c.fcntl(self.tty.handle, c.F_SETFL, c.fcntl(self.tty.handle, c.F_GETFL) | c.O_NONBLOCK) else c.fcntl(self.tty.handle, c.F_SETFL, c.fcntl(self.tty.handle, c.F_GETFL) & ~c.O_NONBLOCK);
    }

    pub fn pollChar(self: *Self) !?u8 {
        var buffer: [1]u8 = undefined;
        const size = self.tty.read(&buffer) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return error.ReadError,
        };

        switch (size) {
            1 => {
                return buffer[0];
            },
            else => unreachable,
        }
    }

    pub fn getCursorPos(self: *Self) !Pos {
        errdefer self.deinit();

        try self.setNonBlock(false);
        defer self.setNonBlock(true) catch {};

        try self.tty.writer().writeAll("\x1b[6n");
        var buf: [16]u8 = undefined;
        var len: usize = 0;
        var byte = try self.tty.reader().readByte();
        while (byte != 'R') : ({
            len += 1;
            byte = try self.tty.reader().readByte();
        }) {
            buf[len] = byte;
        }

        var split = std.mem.splitScalar(u8, buf[2..len], ';');
        const y = split.next().?;
        const x = split.next().?;

        return Pos{ .x = try std.fmt.parseInt(u32, x, 10), .y = try std.fmt.parseInt(u32, y, 10) };
    }

    pub fn move(self: *Self, x: u32, y: u32) !void {
        try self.print("\x1b[{};{}f", .{ y + 1, x + 1 });
    }

    pub fn movex(self: *Self, x: u32) !void {
        const cur = try self.getCursorPos();
        try self.move(x, cur.y);
    }

    pub fn movey(self: *Self, y: u32) !void {
        const cur = try self.getCursorPos();
        try self.move(cur.x, y);
    }

    pub fn movexBegin(self: *Self) !void {
        try self.print("\x1b[G", .{});
    }

    pub fn drawHorzLine(self: *Self, pos: Pos, len: u32) !void {
        for (0..len) |i| {
            const offset: u32 = @intCast(i);
            try self.move(pos.x + offset, pos.y);
            try self.writeAll("─");
        }
    }

    pub fn drawVertLine(self: *Self, pos: Pos, len: u32) !void {
        for (0..len) |i| {
            const offset: u32 = @intCast(i);
            try self.move(pos.x, pos.y + offset);
            try self.writeAll("│");
        }
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        errdefer self.deinit();
        try self.buffer.writer().print(fmt, args);
    }

    pub fn writeAll(self: *Self, bytes: []const u8) !void {
        errdefer self.deinit();
        try self.buffer.writer().writeAll(bytes);
    }

    pub fn flush(self: *Self) !void {
        try stdout_w.writeAll(try self.buffer.toOwnedSlice());
    }
};
