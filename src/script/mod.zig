// TODO: refactor split file
const std = @import("std");
const str = @import("string").str;
const debug = @import("debug");
pub const ScriptRunner = @import("runner.zig");

pub const ScriptData = struct {
    name: []const u8,
    description: []const u8 = "",
    comment: ?[]const u8 = "",
    script: u32,
    dependencies: [][]const u8 = &.{},
    build_dependencies: [][]const u8 = &.{},
    env: ?std.json.ArrayHashMap([]const u8) = null,
};

pub const Script = struct {
    data: ScriptData,
    script_directory: []const u8 = "./scripts",
    envMap: ?std.process.EnvMap = null,

    step: usize = 0,

    arena: std.heap.ArenaAllocator,

    pub fn init(alloc: std.mem.Allocator, data: ScriptData) !Script {
        var script = Script{
            .data = data,
            .arena = std.heap.ArenaAllocator.init(alloc),
        };

        if (script.data.env) |env| {
            var env_map = std.process.EnvMap.init(script.arena.allocator());

            var env_iter = env.map.iterator();
            while (env_iter.next()) |i| {
                try env_map.put(i.key_ptr.*, i.value_ptr.*);
            }
            script.envMap = env_map;
        }

        return script;
    }

    pub fn deinit(self: Script) void {
        self.steps.deinit();
        self.arena.deinit();
    }

    pub fn fromJSON(alloc: std.mem.Allocator, json: []const u8) !std.json.Parsed(Script) {
        const parsed = try std.json.parseFromSlice(ScriptData, alloc, json, .{});

        return std.json.Parsed(Script){
            .arena = parsed.arena,
            .value = try Script.init(parsed.arena.allocator(), parsed.value),
        };
    }

    pub fn fromJsonReader(alloc: std.mem.Allocator, reader: std.io.AnyReader) !Script {
        const json = try reader.readAllAlloc(alloc, 16392);
        const s = try Script.fromJSON(alloc, json);
        alloc.free(json);
        return s;
    }

    pub fn scriptDir(self: *Script, dir: []const u8) void {
        self.script_directory = dir;
    }

    pub fn scriptContent(self: *Script) !ScriptIter {
        const arena = self.arena.allocator();
        const dir_path = try std.fs.realpathAlloc(arena, self.script_directory);

        var dir = try std.fs.openDirAbsolute(dir_path, .{});
        defer dir.close();

        const file_name = try std.fmt.allocPrint(arena, "{}.sh", .{self.data.script});
        var file = try dir.openFile(file_name, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        const reader = buf_reader.reader();
        var content = std.ArrayList(u8).init(arena);
        try reader.readAllArrayList(&content, try file.getEndPos());

        const script_iter = try ScriptIter.init(self.arena.allocator(), try content.toOwnedSlice(), .{ .env = self.envMap });
        return script_iter;
    }

    fn currentStep(self: *Script) usize {
        if (self.script_iter) |si| {
            return si.index;
        } else {
            return 0;
        }
    }
};

pub const ScriptIter = struct {
    index: usize = 0,
    step: usize = 0,
    content: []ScriptToken,
    envMap: ?std.process.EnvMap = null,
    alloc: std.heap.ArenaAllocator,

    pub fn init(alloc: std.mem.Allocator, content: []const u8, options: struct { env: ?std.process.EnvMap = null }) !ScriptIter {
        var arena = std.heap.ArenaAllocator.init(alloc);
        var tokens = std.ArrayList(ScriptToken).init(arena.allocator());

        var values = std.ArrayList(u8).init(arena.allocator());
        var kind: ?TokenKind = null;
        var i: usize = 0;

        var line: usize = 0;
        var char: usize = 0;

        while (i < content.len) : (i += 1) {
            switch (content[i]) {
                '\n' => {
                    if (kind) |k| {
                        try addToken(
                            &tokens, k, try values.toOwnedSlice(),
                            .{ .line = line, .char = char, .file = null },
                        );
                    }
                    try tokens.append(.{ .NewLine = .{ 
                        .content = '\n',
                        .location = .{ .line = line, .char = char, .file = null },
                    }});
                    kind = .NewLine;
                    line += 1;
                },

                ' ' => {
                    if (kind) |k| {
                        try addToken(
                            &tokens, k, try values.toOwnedSlice(),
                            .{ .line = line, .char = char, .file = null },
                        );
                    }
                    try tokens.append(.{ .Space = .{
                        .content = ' ',
                        .location = .{ .line = line, .char = char, .file = null },
                    } });
                    kind = .Space;
                    char += 1;
                },

                '"' => {
                    i += 1;
                    while (content[i] != '"') : (i += 1) {
                        if (content[i] == '\\') {
                            i += 1;
                        }
                        try values.append(content[i]);
                        char += 1;
                    }
                    kind = .DoubleQuote;
                    char += 1;
                },

                // TODO: Add a separate token and move logic to token parser
                '$' => {
                    var key = std.ArrayList(u8).init(arena.allocator());
                    kind = .Word;
                    i += 1;
                    while (content.len > i and std.ascii.isAlphabetic(content[i])) : (i += 1) {
                        try key.append(content[i]);
                        char += 1;
                    }

                    if (options.env) |env| {
                        if (env.get(key.items)) |val| {
                            try values.appendSlice(val);
                        } else {
                            std.log.warn("Unknown Environment variable {s}", .{key.items});
                            return error.UnknownEnvVar;
                        }
                    } else if (std.posix.getenv(key.items)) |env| {
                        try values.appendSlice(env);
                    } else {
                        return error.NoEnvironment;
                    }
                    i -= 1;
                    char += 1;
                },

                // TODO: Add a separate token and move logic to token parser
                '~' => {
                    if (std.posix.getenv("HOME")) |home| {
                        kind = .Word;
                        try values.appendSlice(home);
                    } else {
                        return error.NoEnvironment;
                    }
                    char += 1;
                },

                '.' => {
                    if (kind == .Word) try addToken(
                        &tokens, kind.?, try values.toOwnedSlice(),
                        .{ .line = line, .char = char, .file = null },
                    );
                    try tokens.append(.{ .Dot = '.' });
                    kind = .Dot;
                    char += 1;
                },

                '/' => {
                    if (kind == .Word) try addToken(
                        &tokens, kind.?, try values.toOwnedSlice(),
                        .{ .line = line, .char = char, .file = null },
                    );
                    try tokens.append(.{ .Slash = '/' });
                    kind = .Slash;
                    char += 1;
                },

                '#' => {
                    if (kind == .Word) try addToken(
                        &tokens, kind.?, try values.toOwnedSlice(),
                        .{ .line = line, .char = char, .file = null },
                    );
                    kind = .Hash;
                    while (content.len > i and content[i] != '\n') : (i += 1) {}
                    char += 1;
                },

                '\x1b' => {
                    char += 1;
                    return error.NotImplemented;
                },

                else => |c| {
                    try values.append(c);
                    if (kind) |k| {
                        switch (k) {
                            .Word => {},
                            .Value => {
                                if (!std.ascii.isDigit(c)) {
                                    return error.InvalidExpression;
                                }
                            },
                            else => {
                                if (std.ascii.isDigit(c)) {
                                    kind = .Value;
                                }
                                kind = .Word;
                            },
                        }
                    } else {
                        if (std.ascii.isDigit(c)) {
                            kind = .Value;
                        }
                        kind = .Word;
                        continue;
                    }
                    char += 1;
                },
            }
        }

        if (kind) |k| {
            switch (k) {
                .NewLine, .Space => {},
                else => try addToken(
                    &tokens, k, try values.toOwnedSlice(),
                    .{ .line = line, .char = char, .file = null },
                ),
            }
        }

        return ScriptIter{
            .content = try tokens.toOwnedSlice(),
            .alloc = arena,
        };
    }

    fn setEnv(self: *ScriptIter, map: std.process.EnvMap) void {
        self.envMap = map;
    }

    fn addToken(list: *std.ArrayList(ScriptToken), kind: TokenKind, value: []const u8, location: Location) !void {
        switch (kind) {
            .Word => {
                try list.append(.{ .Word = .{ .content = value, .location = location } });
            },
            .Value => {
                try list.append(.{ .Value = .{ .content = try std.fmt.parseInt(i32, value, 10), .location = location, } });
            },
            .DoubleQuote => {
                try list.append(.{ .DoubleQuote = value });
            },
            .Space => {
                try list.append(.{ .Space = .{ .content = ' ', .location = location } });
            },
            .NewLine => {
                try list.append(.{ .NewLine = .{ .content = '\n', .location = location } });
            },
            .Dot => {
                try list.append(.{ .Dot = '.' });
            },
            .Slash => {
                try list.append(.{ .Slash = '/' });
            },
            .Hash => {
                try list.append(.{ .Hash = '#' });
            },
        }
    }

    pub fn deinit(self: ScriptIter) void {
        self.alloc.deinit();
    }

    pub fn next(self: *ScriptIter) !?std.process.Child {
        const args = try self.nextArgs();
        if (args) |a| {
            self.step += 1;
            return std.process.Child.init(a, self.alloc.allocator());
        } else {
            return null;
        }
    }

    pub fn nextArgs(self: *ScriptIter) !?[]const []const u8 {
        var args = std.ArrayList([]const u8).init(self.alloc.allocator());
        var argBuffer = std.ArrayList(u8).init(self.alloc.allocator());

        while (self.index < self.content.len) : (self.index += 1) {
            switch (self.content[self.index]) {
                .Word => |val| try argBuffer.appendSlice(val.content),
                .Value => |val| try argBuffer.appendSlice(try std.fmt.allocPrint(self.alloc.allocator(), "{d}", .{val.content})),
                .DoubleQuote => |val| try argBuffer.appendSlice(try std.fmt.allocPrint(self.alloc.allocator(), "{s}", .{val})),
                .Space => |_| {
                    const arg = try argBuffer.toOwnedSlice();
                    try args.append(arg);
                    continue;
                },
                .NewLine => {
                    if (argBuffer.items.len > 0) {
                        try args.append(try argBuffer.toOwnedSlice());
                    }
                    if (args.items.len > 0) {
                        break;
                    }
                },
                .Dot => {
                    if (args.items.len == 0 and self.content.len > self.index + 1 and self.content[self.index + 1] == .Slash) {
                        try argBuffer.appendSlice(try std.fs.cwd().realpathAlloc(self.alloc.allocator(), "."));
                    } else {
                        try argBuffer.append('.');
                    }
                },
                .Slash => {
                    try argBuffer.append('/');
                },
                .Hash => {},
            }
        }

        if (argBuffer.items.len > 0) {
            try args.append(argBuffer.items);
        }
        if (args.items.len > 0) {
            self.step += 1;
            return try args.toOwnedSlice();
        } else {
            return null;
        }
    }

    pub fn steps(self: *ScriptIter) ![]const []const u8 {
        var step_list = std.ArrayList([]const u8).init(self.alloc.allocator());

        var step = try self.nextArgs();
        while (step != null) : (step = try self.nextArgs()) {
            try step_list.append(step.?[0]);
        }

        return step_list.toOwnedSlice();
    }

    pub fn reset(self: *ScriptIter) void {
        self.index = 0;
    }
};

const Location = struct {
    line: usize,
    char: usize,
    file: ?[]const u8,
};

fn withLocation(comptime Content: type) type {
    return struct {
        content: Content,
        location: Location,

        const Self = @This();

        fn new(content: Content, line: usize, char: usize, file: ?[]const u8) Self {
            return .{ 
                .content = content,
                .location = .{ .line = line, .char = char, .file = file },
            };
        }
    };
}

// TODO: Store token location
const ScriptToken = union(TokenKind) {
    Word: withLocation([]const u8),
    Value: withLocation(i32),
    NewLine: withLocation(u8),
    Space: withLocation(u8),
    DoubleQuote: []const u8,
    Dot: u8,
    Slash: u8,
    Hash: u8,
};

const TokenKind = enum {
    Word,
    Value,
    NewLine,
    Space,
    DoubleQuote,
    Dot,
    Slash,
    Hash,
};

pub const CollectOptions = struct {
    Verbose: bool = false,
};
