const std = @import("std");

const Self = @This();
var allocator = std.heap.GeneralPurposeAllocator(.{}){};

severity: Severity,
location: std.builtin.SourceLocation,
message: std.ArrayList(u8),

pub fn info(loc: std.builtin.SourceLocation, msg: []const u8) Self {
    var message = std.ArrayList(u8).init(allocator.allocator());
    message.appendSlice(msg) catch {};

    return Self{
        .location = loc,
        .severity = .Info,
        .message = message,
    };
}

pub fn infoFmt(loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) Self {
    var message = std.ArrayList(u8).init(allocator.allocator());
    message.writer().print(fmt, args) catch {};

    return Self{
        .location = loc,
        .severity = .Info,
        .message = message,
    };
}

pub fn fatal(loc: std.builtin.SourceLocation, msg: []const u8) Self {
    var message = std.ArrayList(u8).init(allocator.allocator());
    message.appendSlice(msg) catch {};

    return Self{
        .location = loc,
        .severity = .Fatal,
        .message = message,
    };
}

pub fn fatalFmt(loc: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) Self {
    var message = std.ArrayList(u8).init(allocator.allocator());
    message.writer().print(fmt, args) catch {};

    return Self{
        .location = loc,
        .severity = .Fatal,
        .message = message,
    };
}

pub fn allocPrint(self: *Self, alloc: std.mem.Allocator) ![]const u8 {
    const severityRepr = switch (self.severity) {
        .Debug => "DEBUG",
        .Info => "INFO",
        .Warning => "WARN",
        .Error => "ERROR",
        .Fatal => "FATAL",
    };

    if (self.message.items.len > 0) {
        return try std.fmt.allocPrint(alloc, "{s}:{d}: [{s}] {s}\n", .{ self.location.file, self.location.line, severityRepr, try self.message.toOwnedSlice() });
    } else {
        return try std.fmt.allocPrint(alloc, "{s}:{d}: [{s}]\n", .{ self.location.file, self.location.line, severityRepr });
    }
}

pub fn print(self: Self) void {
    var this = self;
    const repr = this.allocPrint(allocator.allocator()) catch return;

    if (self.severity == .Fatal) {
        std.debug.panic("{s}\n", .{repr});
    }

    std.debug.print("{s}\n", .{repr});
    allocator.allocator().free(repr);
}

const Severity = enum {
    Debug,
    Info,
    Warning,
    Error,
    Fatal,
};
