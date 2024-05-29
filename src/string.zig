const std = @import("std");

const strError = error{
    AllocError,
};

pub const str = struct {
    cap: usize = 64,
    content: []u8,

    alloc: std.mem.Allocator,

    pub fn initUnsafe() str {}

    pub fn init(alloc: std.mem.Allocator) str {
        var content = alloc.alloc(u8, 64) catch |err| std.debug.panic("Out of Memory: {any}\n", .{err});
        content.len = 0;
        return str{ .alloc = alloc, .content = content };
    }

    pub fn fromSlice(alloc: std.mem.Allocator, content: []const u8) str {
        var s = str{ .alloc = alloc };
        s.add(content);
        return s;
    }

    pub fn deinit(self: str) void {
        self.alloc.free(self.content);
    }

    pub fn isEmpty(self: *str) bool {
        return self.content.len == 0;
    }

    pub fn grow(self: *str, size: usize) void {
        while (self.cap < size) {
            if (!self.alloc.resize(self.content, self.cap + self.cap / 2)) {
                var new_buf = self.alloc.alloc(u8, self.cap + self.cap / 2) catch |err| std.debug.panic("Out of Memory: {any}\n", .{err});
                @memcpy(new_buf[0..self.content.len], self.content);
                self.alloc.free(self.content);
                self.content.ptr = new_buf.ptr;
                self.cap = new_buf.len;
            }
        }
    }

    pub fn add(self: *str, value: []const u8) void {
        if (self.cap < self.content.len + value.len) {
            self.grow(self.content.len + value.len);
        }
        const old_len = self.content.len;
        self.content.len += value.len;
        @memcpy(self.content[old_len..self.content.len], value);
    }

    pub fn addFmt(self: *str, comptime fmt: []const u8, args: anytype) !void {
        const newBuf = try std.fmt.allocPrint(self.alloc, fmt, args);

        self.add(newBuf);
        self.alloc.free(newBuf);
    }

    pub fn toSlice(self: *str) []const u8 {
        const content = self.content;
        self.content = self.alloc.alloc(u8, 0) catch |err| std.debug.panic("Out of Memory: {any}\n", .{err});
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
    }

    pub fn format(self: str, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll(self.content);
    }
};
