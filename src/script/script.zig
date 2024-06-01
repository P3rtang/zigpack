const std = @import("std");
const str = @import("string").str;

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
    stdout: ?*std.io.AnyWriter = null,
    stderr: ?*std.io.AnyWriter = null,
    collect_options: CollectOptions = CollectOptions{},
    arena: std.heap.ArenaAllocator,
    envMap: ?std.process.EnvMap = null,

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

    pub fn collectOutput(self: *Script, stdout: *std.io.AnyWriter, stderr: *std.io.AnyWriter, options: CollectOptions) !void {
        self.stdout = stdout;
        self.stderr = stderr;
        self.collect_options = options;
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

    pub fn exec(self: *Script) !void {
        var iter = try self.scriptContent();

        var stdout_buf = std.ArrayList(u8).init(self.arena.allocator());
        var stderr_buf = std.ArrayList(u8).init(self.arena.allocator());

        var child: ?std.process.Child = try iter.next();
        while (child != null) : (child = try iter.next()) {
            child.?.stdout_behavior = .Pipe;
            child.?.stderr_behavior = .Pipe;

            if (self.envMap) |env| {
                child.?.env_map = &env;
            }

            try child.?.spawn();
            try child.?.collectOutput(&stdout_buf, &stderr_buf, 4096);
            _ = try child.?.wait();

            if (self.stdout) |w| {
                try w.writeAll(try stdout_buf.toOwnedSlice());
            }
            if (self.stderr) |w| {
                try w.writeAll(try stderr_buf.toOwnedSlice());
            }
        }
    }
};

pub const ScriptIter = struct {
    index: usize = 0,
    count: usize = 0,
    content: []ScriptToken,
    envMap: ?std.process.EnvMap = null,
    alloc: std.heap.ArenaAllocator,

    pub fn init(alloc: std.mem.Allocator, content: []const u8, options: struct { env: ?std.process.EnvMap = null }) !ScriptIter {
        var arena = std.heap.ArenaAllocator.init(alloc);
        var tokens = std.ArrayList(ScriptToken).init(arena.allocator());

        var values = std.ArrayList(u8).init(arena.allocator());
        var kind: ?TokenKind = null;
        var i: usize = 0;

        while (i < content.len) : (i += 1) {
            switch (content[i]) {
                '\n' => {
                    if (kind) |k| {
                        try addToken(&tokens, k, try values.toOwnedSlice());
                    }
                    try tokens.append(.{ .NewLine = '\n' });
                    kind = .NewLine;
                },

                ' ' => {
                    if (kind) |k| {
                        try addToken(&tokens, k, try values.toOwnedSlice());
                    }
                    try tokens.append(.{ .Space = ' ' });
                    kind = .Space;
                },

                '"' => {
                    i += 1;
                    while (content[i] != '"') : (i += 1) {
                        if (content[i] == '\\') {
                            i += 1;
                        }
                        try values.append(content[i]);
                    }
                    kind = .DoubleQuote;
                },

                '\\' => {
                    i += 1;
                    try values.append(content[i]);
                    kind = .Word;
                },

                '$' => {
                    var key = std.ArrayList(u8).init(arena.allocator());
                    kind = .Word;
                    i += 1;
                    while (std.ascii.isAlphabetic(content[i])) : (i += 1) {
                        try key.append(content[i]);
                    }

                    if (options.env) |env| {
                        if (env.get(key.items)) |val| {
                            try values.appendSlice(val);
                        } else {
                            std.log.warn("Unknown Environment variable {s}", .{key.items});
                            return error.UnknownEnvVar;
                        }
                    } else {
                        return error.NoEnvironment;
                    }
                    i -= 1;
                },

                else => |char| {
                    try values.append(char);
                    if (kind == null) {
                        if (std.ascii.isDigit(char)) {
                            kind = .Value;
                        }
                        kind = .Word;
                        continue;
                    }
                    switch (kind.?) {
                        .Word => {},
                        .Value => {
                            if (!std.ascii.isDigit(char)) {
                                return error.InvalidExpression;
                            }
                        },
                        else => {
                            if (std.ascii.isDigit(char)) {
                                kind = .Value;
                            }
                            kind = .Word;
                        },
                    }
                },
            }
        }

        if (kind) |k| {
            switch (k) {
                .NewLine, .Space => {},
                else => try addToken(&tokens, k, try values.toOwnedSlice()),
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

    fn addToken(list: *std.ArrayList(ScriptToken), kind: TokenKind, value: []const u8) !void {
        switch (kind) {
            .Word => {
                try list.append(.{ .Word = value });
            },
            .Value => {
                try list.append(.{ .Value = try std.fmt.parseInt(i32, value, 10) });
            },
            .DoubleQuote => {
                try list.append(.{ .DoubleQuote = value });
            },
            .Space => {
                try list.append(.{ .Space = ' ' });
            },
            .NewLine => {
                try list.append(.{ .NewLine = '\n' });
            },
        }
    }

    pub fn deinit(self: ScriptIter) void {
        self.alloc.deinit();
    }

    pub fn next(self: *ScriptIter) !?std.process.Child {
        var args = std.ArrayList([]const u8).init(self.alloc.allocator());

        while (self.count < self.content.len) : (self.count += 1) {
            switch (self.content[self.count]) {
                .Word => |val| try args.append(val),
                .Value => |val| try args.append(try std.fmt.allocPrint(self.alloc.allocator(), "{d}", .{val})),
                .DoubleQuote => |val| try args.append(try std.fmt.allocPrint(self.alloc.allocator(), "{s}", .{val})),
                .Space => {},
                .NewLine => {
                    self.count += 1;
                    break;
                },
            }
        }
        if (args.items.len > 0) {
            return std.process.Child.init(try args.toOwnedSlice(), self.alloc.allocator());
        } else {
            return null;
        }
    }
};

const ScriptToken = union(TokenKind) {
    Word: []const u8,
    Value: i32,
    NewLine: u8,
    Space: u8,
    DoubleQuote: []const u8,
};

const TokenKind = enum {
    Word,
    Value,
    NewLine,
    Space,
    DoubleQuote,
};

const CollectOptions = struct {
    Verbose: bool = false,
};
