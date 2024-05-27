const std = @import("std");
const parse = @import("./mod.zig").parse;
const str = @import("./mod.zig").string.str;

pub const commandError = error{
    MissingArgument,
    UnrecogizedArgument,
    PrintUsage,
};

pub fn command(comptime T: type) type {
    return struct {
        const Self = @This();
        var a = std.heap.GeneralPurposeAllocator(.{}){};

        const cmdConfig = struct {
            use: []const u8,
            short: []const u8 = "",
            serve: ?*T = null,
        };

        alloc: std.mem.Allocator = a.allocator(),
        commands: std.StringHashMap(Self) = std.StringHashMap(Self).init(a.allocator()),

        args: std.ArrayList(Argument) = std.ArrayList(Argument).init(a.allocator()),
        argIndex: usize = 0,

        // TODO: think of using a hashmap with both the short and long flag as key
        flags: std.ArrayList(Flag) = std.ArrayList(Flag).init(a.allocator()),

        config: cmdConfig = .{ .use = "root" },

        usageStr: str = str.init(a.allocator()),

        pub fn init(alloc: std.mem.Allocator) Self {
            var cmd = Self{ .alloc = alloc };

            cmd.addFlag(.{ .use = "help", .short = "h", .comment = "Show this message" }) catch return cmd;

            return cmd;
        }

        pub fn deinit(self: *Self) void {
            self.commands.deinit();
            self.flags.deinit();
            self.args.deinit();
            self.usageStr.deinit();
        }

        pub fn execute(self: *Self) !void {
            var parser = try parse.Parser.new(self.alloc);
            defer parser.deinit();

            try self.executeWithParser(&parser);
        }

        pub fn executeWithParser(self: *Self, parser: *parse.Parser) commandError!void {
            if (parser.index == 0) {
                self.config.use = parser.next().?.content;
            }
            self.argIndex = 0;
            while (parser.next()) |token| {
                switch (token.kind) {
                    .argument => {
                        if (self.commands.getPtr(token.content)) |cmd| {
                            if (self.args.items.len > self.argIndex) {
                                return commandError.MissingArgument;
                            }
                            if (self.config.serve) |cb| {
                                var cback = cb;
                                cback.call(self);
                            }
                            try cmd.executeWithParser(parser);
                        } else if (self.args.items.len > self.argIndex) {
                            self.args.items[self.argIndex].value.String = token.content;
                            self.argIndex += 1;
                        } else {
                            std.debug.print(" \nunrecognized argument `{s}`\nIn command `{s}`\n", .{ token.content, self.config.use });
                            std.debug.print("{s}", .{self.usage() catch return commandError.PrintUsage});
                            return commandError.UnrecogizedArgument;
                        }
                    },
                    .flag => {
                        if (std.mem.eql(u8, token.content, "help")) {
                            std.debug.print("{s}", .{self.usage() catch return commandError.PrintUsage});
                            return;
                        }
                        for (self.flags.items, 0..) |f, idx| {
                            if (!std.mem.eql(u8, f.use, token.content)) {
                                continue;
                            }

                            if (parser.next()) |tok| {
                                const errInt: ?i32 = std.fmt.parseInt(i32, tok.content, 10) catch null;
                                if (errInt) |int| {
                                    self.flags.items.ptr[idx].value.Integer = int;
                                }
                            } else {
                                return commandError.MissingArgument;
                            }
                        }
                    },
                    .short_flag => {
                        if (std.mem.eql(u8, token.content, "h")) {
                            std.debug.print("{s}", .{self.usage() catch return commandError.PrintUsage});
                            return;
                        }
                        for (self.flags.items, 0..) |f, idx| {
                            if (f.short) |short| {
                                if (!std.mem.eql(u8, short, token.content)) {
                                    continue;
                                }
                            }

                            if (parser.next()) |tok| {
                                const errInt: ?i32 = std.fmt.parseInt(i32, tok.content, 10) catch null;
                                if (errInt) |int| {
                                    self.flags.items.ptr[idx].value.Integer = int;
                                }
                            } else {
                                return commandError.MissingArgument;
                            }
                        }
                    },
                    .dash_separator => {},
                    .Invalid => {},
                }
            }
            if (self.args.items.len > self.argIndex) {
                return commandError.MissingArgument;
            } else {
                if (self.args.items.len > self.argIndex) {
                    return commandError.MissingArgument;
                }
                if (self.config.serve) |cb| {
                    var cback = cb;
                    cback.call(self);
                }
            }
        }

        pub fn addCommand(self: *Self, config: cmdConfig) !*command(T) {
            var cmd = Self{ .alloc = self.alloc, .config = config };
            try self.commands.put(config.use, cmd);
            return self.commands.getPtr(config.use).?;
        }

        pub fn addArgument(self: *Self, name: []const u8, comptime argType: ArgType) !void {
            var arg = Argument{ .name = name, .value = argType };
            try self.args.append(arg);
        }

        pub fn getArgument(self: *Self, name: []const u8) ?*ArgType {
            for (self.args.items) |item| {
                if (std.mem.eql(u8, item.name, name)) {
                    var arg = item.value;
                    return &arg;
                }
            }
            return null;
        }

        pub fn addFlag(self: *Self, options: Flag) !void {
            try self.flags.append(options);
        }

        pub fn hasFlag(self: *Self, name: []const u8) bool {
            for (self.flags.items) |item| {
                if (std.mem.eql(u8, item.use, name)) {
                    return true;
                }
            }
            return false;
        }

        pub fn getFlag(self: *Self, name: []const u8) ?*FlagValue {
            for (self.flags.items) |item| {
                if (std.mem.eql(u8, item.use, name)) {
                    var f = item.value;
                    return &f;
                }
            }
            return null;
        }

        fn usageLine(self: *Self) ![]const u8 {
            const hasCmd = switch (self.commands.count()) {
                0 => "",
                else => " [command]",
            };
            const hasArg = switch (self.args.items.len) {
                0 => "",
                else => " <argument>",
            };

            return std.fmt.allocPrint(self.alloc, "{s}{s}{s}", .{ self.config.use, hasCmd, hasArg });
        }

        pub fn usage(self: *Self) ![]const u8 {
            try self.usageStr.clear();
            self.usageStr.add(" \n");
            if (self.config.short.len > 0) {
                try self.usageStr.addFmt("{s}\n\n", .{self.config.short});
            }

            self.usageStr.add("Usage:\n");
            const usageBuf = try self.usageLine();
            try self.usageStr.addFmt("  {s}\n\n", .{usageBuf});
            self.alloc.free(usageBuf);

            if (self.commands.count() > 0) {
                self.usageStr.add("Available Commands:\n");
                var cmdIter = self.commands.iterator();
                while (cmdIter.next()) |entry| {
                    try self.usageStr.addFmt("  {s}\n", .{entry.key_ptr.*});
                }
            }

            if (self.flags.items.len > 0) {
                self.usageStr.add("\nFlags:\n");
                for (self.flags.items) |flag| {
                    if (flag.short) |short| {
                        try self.usageStr.addFmt("  --{s} | -{s}", .{ flag.use, short });
                    } else {
                        try self.usageStr.addFmt("  --{s}", .{flag.use});
                    }

                    try self.usageStr.addFmt("\t{s}\n", .{flag.comment});
                }
            }

            self.usageStr.add("\n");

            self.usageStr = self.usageStr;
            return self.usageStr.toSlice();
        }
    };
}

const Flag = struct {
    use: []const u8,
    short: ?[]const u8 = null,
    value: FlagValue = .{ .None = {} },
    comment: []const u8 = "",

    fn hasArg(self: Flag) bool {
        return switch (@TypeOf(self.value)) {
            else => true,
        };
    }
};

const FlagValue = union {
    None: void,
    Boolean: bool,
    Integer: i32,
    String: []const u8,
};

pub const ArgType = union {
    Integer: i64,
    Float: f64,
    String: []const u8,
};

pub const Argument = struct {
    name: []const u8,
    comment: []const u8 = "",
    value: ArgType,
};
