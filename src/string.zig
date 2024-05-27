const std = @import("std");

const strError = error{
    AllocError,
};

pub const str = struct {
    len: usize = 0,
    content: []u8 = &.{},

    alloc: std.mem.Allocator,

    pub fn initUnsafe() str {}

    pub fn init(alloc: std.mem.Allocator) str {
        return str{ .alloc = alloc };
    }

    pub fn fromSlice(alloc: std.mem.Allocator, content: []const u8) str {
        var s = str{ .alloc = alloc };
        s.add(content);
        return s;
    }

    pub fn deinit(self: str) void {
        self.alloc.free(self.content);
    }

    pub fn len(self: *str) usize {
        return self.content.len;
    }

    pub fn isEmpty(self: *str) bool {
        return self.content.len == 0;
    }

    pub fn add(self: *str, value: []const u8) void {
        if (self.alloc.resize(self.content, self.len + value.len)) {
            self.content.len += value.len;
            @memcpy(self.content[self.len..], value);
        } else {
            var buf = self.alloc.alloc(u8, self.len + value.len) catch |err| std.debug.panic("Out of Memory: {any}\n", .{err});
            @memcpy(buf[0..self.len], self.content);
            @memcpy(buf[self.len..], value);
            self.alloc.free(self.content);
            self.content = buf;
        }
        self.len += value.len;
    }

    pub fn addFmt(self: *str, comptime fmt: []const u8, args: anytype) !void {
        var newBuf = try std.fmt.allocPrint(self.alloc, fmt, args);

        self.add(newBuf);
        self.alloc.free(newBuf);
    }

    pub fn toSlice(self: *str) []const u8 {
        var content = self.content;
        self.content = self.alloc.alloc(u8, 0) catch |err| std.debug.panic("Out of Memory: {any}\n", .{err});
        self.len = 0;
        return content;
    }

    pub fn asSlice(self: *str) []const u8 {
        return self.content;
    }

    pub fn clear(self: *str) !void {
        if (!self.alloc.resize(self.content, 0)) {
            self.alloc.free(self.content);
            self.content = try self.alloc.alloc(u8, 0);
        }

        self.content.len = 0;
        self.len = 0;
    }

    pub fn format(self: str, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll(self.content);
    }
};
