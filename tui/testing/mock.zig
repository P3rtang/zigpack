const std = @import("std");
const tui = @import("tui");

pub fn MockTerm(comptime X: usize, comptime Y: usize) type {
    return struct {
        const Self = @This();

        arena: std.heap.ArenaAllocator,
        buffer: [X * Y]u8 = [_]u8{' '} ** (X * Y),
        cursor_pos: tui.Pos = .{},

        keys: std.DoublyLinkedList(tui.Key),

        pub fn init(alloc: std.mem.Allocator) Self {
            const arena = std.heap.ArenaAllocator.init(alloc);
            const buffer: [X * Y]u8 = undefined;

            return Self{
                .arena = arena,
                .buffer = buffer,
                .keys = std.DoublyLinkedList(tui.Key){},
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn term(self: *Self) tui.Term {
            return tui.Term{
                .arena = &self.arena,
                .context = self,
                .getCursorFn = getCursor,
                .pollKeyFn = pollKey,
                .writeFn = writeOpaque,
            };
        }

        fn write(self: *Self, bytes: []const u8) !void {
            const pos = self.cursor_pos.y * X + self.cursor_pos.x;

            if (pos + bytes.len >= self.buffer.len) {
                const split = self.buffer.len - pos;
                const rest = bytes.len - split;

                @memcpy(self.buffer[pos..self.buffer.len], bytes[0..split]);
                @memcpy(self.buffer[0..rest], bytes[split..bytes.len]);
            } else {
                @memcpy(self.buffer[pos .. pos + bytes.len], bytes);
            }
        }

        fn writeOpaque(ptr: *anyopaque, bytes: []const u8) !void {
            const self: *Self = @alignCast(@ptrCast(ptr));
            try self.write(bytes);
        }

        fn printOpaque(ptr: *anyopaque, comptime fmt: []const u8, args: anytype) !void {
            const self: *Self = @alignCast(@ptrCast(ptr));
            try self.write(ptr, try std.fmt.allocPrint(self.arena.allocator(), fmt, args));
        }

        fn getCursor(ptr: *anyopaque, t: *tui.Term) !tui.Cursor {
            const self: *Self = @alignCast(@ptrCast(ptr));
            return tui.Cursor{
                .context = self,
                .term = t,
                .getPos = getCursorPos,
            };
        }

        fn getCursorPos(ptr: *anyopaque) tui.Pos {
            const self: *Self = @alignCast(@ptrCast(ptr));
            return self.cursor_pos;
        }

        fn moveCursor(self: *Self, pos: tui.pos) void {
            self.cursor_pos = pos;
        }

        fn pollKey(ptr: *anyopaque) !?tui.Key {
            const self: *Self = @alignCast(@ptrCast(ptr));

            if (self.keys.popFirst()) |node| {
                return node.data;
            }
            return null;
        }

        pub fn simulateKey(self: *Self, key: tui.Key) void {
            self.keys.append(key);
        }
    };
}
