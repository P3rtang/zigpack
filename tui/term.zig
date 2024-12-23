// TODO: make the writer more generic
// TODO: add a terminal mock to test output
const std = @import("std");
const lib = @import("lib.zig");

const Key = lib.Key;
const Pos = lib.Pos;
const Quad = lib.Quad;
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("fcntl.h");
    @cInclude("sys/ioctl.h");
});

const Term = struct {
    const Self = @This();
    const stdout_w = std.io.getStdOut().writer();

    tty: ?std.fs.File = null,
    termios: std.os.linux.termios,

    buffer: std.ArrayList(u8),
    cursor: Pos,

    arena: std.heap.ArenaAllocator,

    writer: std.io.AnyWriter,

    pub fn init(alloc: std.mem.Allocator) !Term {
        const tty: std.fs.File = try std.fs.cwd().openFile("/dev/tty", std.fs.File.OpenFlags{ .mode = .read_write });
        var termios: std.os.linux.termios = undefined;
        _ = std.os.linux.tcgetattr(tty.handle, &termios);

        const arena = std.heap.ArenaAllocator.init(alloc);

        const buffer = std.ArrayList(u8).init(alloc);

        try stdout_w.writeAll("\x1b[?25l");

        return Term{
            .tty = tty,
            .termios = termios,
            .buffer = buffer,
            .cursor = Pos{},
            .arena = arena,
        };
    }

    pub fn deinit(self: *Term) void {
        self.showCursor(.Block) catch {};
        try self.intoCanon();
        if (self.tty) |tty| {
            _ = c.fcntl(tty.handle, c.F_SETFL, c.fcntl(tty.handle, c.F_GETFL) & ~c.O_NONBLOCK);
            tty.close();
        }
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

        if (self.tty) |tty| {
            _ = std.os.linux.tcsetattr(tty.handle, .FLUSH, &raw);
        }
    }

    pub fn intoCanon(self: *Self) !void {
        try self.setNonBlock(false);

        stdout_w.writeAll("\x1B[?47l") catch {};
        stdout_w.writeAll("\x1B[u") catch {};
        stdout_w.writeAll("\x1B[?1049l") catch {};
        if (self.tty) |tty| {
            _ = std.os.linux.tcsetattr(tty.handle, .FLUSH, &self.termios);
        }
    }

    pub fn clearTerm(self: *Self) !void {
        try self.writeAll("\x1b[2J");
    }

    fn toggleNonBlock(self: *const Self) !void {
        if (self.tty) |tty| {
            if (c.fcntl(tty.handle, c.F_SETFL, c.fcntl(tty.handle, c.F_GETFL) | c.O_NONBLOCK) != 0) {
                return error.CouldNotToggle;
            }
        }
    }

    fn setNonBlock(self: *const Self, set: bool) !void {
        if (self.tty) |tty| {
            _ = if (set) {
                _ = c.fcntl(tty.handle, c.F_SETFL, c.fcntl(tty.handle, c.F_GETFL) | c.O_NONBLOCK);
            } else {
                _ = c.fcntl(tty.handle, c.F_SETFL, c.fcntl(tty.handle, c.F_GETFL) & ~c.O_NONBLOCK);
            };
        }
    }

    pub fn pollKey(self: *Self) !?Key {
        if (self.tty == null) return null;

        var buffer: [1]u8 = undefined;
        const size = self.tty.?.read(&buffer) catch |err| switch (err) {
            error.WouldBlock => return null,
            else => return error.ReadError,
        };

        if (size != 1) unreachable;

        return switch (buffer[0]) {
            3 => {
                self.deinit();
                std.process.exit(0);
            },
            8 => Key{ .BACKSPACE = {} },
            9 => Key{ .TAB = {} },
            13 => Key{ .ENTER = {} },
            27 => Key{ .ESC = {} },
            127 => Key{ .DEL = {} },
            else => |char| Key{ .CHAR = char },
        };
    }

    fn getHardwareCursorPos(self: *Self) !Pos {
        if (self.tty == null) return .{};

        errdefer self.deinit();

        try self.setNonBlock(false);
        defer self.setNonBlock(true) catch {};

        try self.tty.?.writer().writeAll("\x1b[6n");
        var buf: [16]u8 = undefined;
        var len: usize = 0;
        var byte = try self.tty.?.reader().readByte();
        while (byte != 'R') : ({
            len += 1;
            byte = try self.tty.?.reader().readByte();
        }) {
            buf[len] = byte;
        }

        var split = std.mem.splitScalar(u8, buf[2..len], ';');
        const y = split.next().?;
        const x = split.next().?;

        return Pos{ .x = try std.fmt.parseInt(usize, x, 10), .y = try std.fmt.parseInt(usize, y, 10) };
    }

    pub fn moveCursor(self: *Self, x: usize, y: usize) !void {
        self.cursor.x = x;
        self.cursor.y = y;
    }

    pub fn showCursor(_: *Self, cursor_type: CursorType) !void {
        try stdout_w.writeAll("\x1b[?25h");
        switch (cursor_type) {
            .Block => try stdout_w.writeAll("\x1b[2 q"),
            .Line => try stdout_w.writeAll("\x1b[5 q"),
            .Underline => {},
        }
    }

    pub fn hideCursor(_: *Self) !void {
        try stdout_w.writeAll("\x1b[?25l\x1b[?50l");
    }

    pub fn move(self: *Self, x: usize, y: usize) !void {
        try self.print("\x1b[{};{}f", .{ y + 1, x + 1 });
    }

    pub fn movex(self: *Self, x: usize) !void {
        const cur = try self.getCursorPos();
        try self.move(x, cur.y);
    }

    pub fn movey(self: *Self, y: usize) !void {
        const cur = try self.getCursorPos();
        try self.move(cur.x, y);
    }

    pub fn movexBegin(self: *Self) !void {
        try self.print("\x1b[G", .{});
    }

    pub fn drawHorzLine(self: *Self, pos: Pos, len: usize) !void {
        for (0..len) |i| {
            const offset: usize = @intCast(i);
            try self.move(pos.x + offset, pos.y);
            try self.writeAll("─");
        }
    }

    pub fn drawVertLine(self: *Self, pos: Pos, len: usize) !void {
        for (0..len) |i| {
            const offset: usize = @intCast(i);
            try self.move(pos.x, pos.y + offset);
            try self.writeAll("│");
        }
    }

    pub fn writeAll(self: *Self, bytes: []const u8) !void {
        try self.buffer.writer().writeAll(bytes);
    }

    pub fn writeByte(self: *Self, byte: u8) !void {
        try self.buffer.writer().writeByte(byte);
    }

    pub fn print(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.buffer.writer().print(format, args);
    }

    pub fn flush(self: *Self) !void {
        errdefer self.deinit();
        try self.move(self.cursor.x, self.cursor.y);
        try stdout_w.writeAll(try self.buffer.toOwnedSlice());
        try self.clearTerm();
    }

    pub fn newWindow(self: *Self, quad: Quad) !*Window {
        const win = Window.init(self.arena.allocator(), quad);
        self.sub_windows.append(&win);
        return &win;
    }

    pub fn getSize(_: *Self) !lib.Size {
        var size = c.winsize{};
        if (c.ioctl(std.io.getStdOut().handle, c.TIOCGWINSZ, &size) != 0) return error.IOCtlError;
        return lib.Size{
            .w = size.ws_col,
            .h = size.ws_row,
        };
    }
};

pub const Window = struct {
    const Self = @This();

    quad: Quad,
    buffer: std.ArrayList(Char),
    alloc: std.mem.Allocator,

    cursor: Pos,
    wrap: WrapBehaviour = .Wrap,

    pub fn init(alloc: std.mem.Allocator, quad: Quad) !Window {
        return Window{
            .quad = quad,
            .buffer = std.ArrayList(u8).init(alloc),
            .alloc = alloc,
        };
    }

    fn writeWindow(self: *Self, win: *Window) !void {
        for (try win.buffer.toOwnedSlice(), 0..) |char, idx| {
            const x = idx % win.quad.w + win.quad.x;
            const y = @divFloor(idx, win.quad.w) + win.quad.y;
            if (self.quad.w > x or self.quad.h < y) continue;
            self.buffer.items[y * self.quad.w + x] = char;
        }
    }

    fn writeCharAt(self: *Self, pos: Pos, char: Char) !void {
        self.buffer.items[pos.y * self.quad.w + pos.x] = char;
    }

    fn writeChar(self: *Self, char: Char) void {
        self.buffer.items[self.cursor.y * self.quad.w + self.cursor.x] = char;
        self.advanceCursor();
    }

    fn advanceCursor(self: *Self) void {
        self.cursor.x += 1;
        self.cursor.x %= self.quad.w;
        if (self.cursor.x == 0) {
            self.cursor.y += 1;
            self.cursor.y %= self.quad.h;
        }
    }

    pub fn writeAll(self: *Self, bytes: []const u8) void {
        for (bytes) |char| {
            self.writeChar(char);
        }
    }

    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        const bytes = try std.fmt.allocPrint(self.alloc, fmt, args);
        self.writeAll(bytes);
    }
};

pub const Char = struct {
    char: u8,
    fg: Color,
    bg: Color,
};

pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
};

pub const WrapBehaviour = enum {
    Wrap,
    Nowrap,
};

pub const CursorType = enum {
    Block,
    Line,
    Underline,
};
