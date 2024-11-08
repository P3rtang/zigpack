const std = @import("std");
const super = @import("mod.zig");

const Self = @This();

tty: std.fs.File = std.fs.cwd().openFile("/dev/tty", std.fs.File.OpenFlags{ .mode = .read_write }) catch |err| std.debug.panic("{}", .{err}),
arena: std.heap.ArenaAllocator,

pub fn init(alloc: std.mem.Allocator) Self {
    return Self{
        .arena = std.heap.ArenaAllocator.init(alloc),
    };
}

pub fn term(self: *Self) super.Term {
    super.Term{
        .context = self,
        .getHandle = getHandle,
        .getCursorFn = getCursor,
    };
}

pub fn getHandle(self: *Self) i32 {
    self.tty.handle;
}

pub fn getCursor(self: *Self, t: *super.Term) !super.Cursor {
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

    return super.Cursor{
        .pos = .{ .x = try std.fmt.parseInt(usize, x, 10), .y = try std.fmt.parseInt(usize, y, 10) },
        .term = t,
    };
}
