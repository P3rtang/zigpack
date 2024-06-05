const std = @import("std");
const str = @import("string").str;
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("fcntl.h");
    @cInclude("pty.h");
    @cInclude("unistd.h");
    @cInclude("sys/wait.h");
    @cInclude("sys/types.h");
});

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

pub const ScriptRunner = struct {
    const Self = @This();

    stdout: ?*std.io.AnyWriter = null,
    stderr: ?*std.io.AnyWriter = null,
    collect_options: CollectOptions = CollectOptions{},

    step: usize = 0,
    steps: []const []const u8,
    iterator: *ScriptIter,

    pub fn init(iter: *ScriptIter) !Self {
        var iterator = iter;
        const steps = try iterator.steps();
        iterator.reset();
        return Self{
            .steps = steps,
            .iterator = iterator,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.iterator.deinit();
    }

    pub fn collectOutput(self: *Self, stdout: *std.io.AnyWriter, stderr: *std.io.AnyWriter, options: CollectOptions) void {
        self.stdout = stdout;
        self.stderr = stderr;
        self.collect_options = options;
    }

    pub fn execNext(self: *Self) !void {
        var alloc = std.heap.GeneralPurposeAllocator(.{}){};

        if (try self.iterator.next()) |child| {
            const pipes = try std.posix.pipe2(.{ .NONBLOCK = true });
            const pid = std.os.linux.fork();

            if (pid == 0) {
                std.posix.close(pipes[0]);
                try std.posix.dup2(pipes[1], std.posix.STDERR_FILENO);
                try std.posix.dup2(pipes[1], std.posix.STDOUT_FILENO);

                var t = std.ArrayList(?[*:0]const u8).init(alloc.allocator());
                defer t.deinit();

                for (child.argv[0..]) |arg| {
                    var null_arg: [:0]u8 = try alloc.allocator().allocSentinel(u8, arg.len, 0);
                    @memcpy(null_arg[0..arg.len], arg);
                    try t.append(null_arg);
                }

                const args: [*:null]?[*:0]const u8 = try t.toOwnedSliceSentinel(null);
                const result = std.posix.execvpeZ(args[0].?, args, &.{null});
                std.debug.panic("Child ERROR: {}", .{result});
            } else {
                try self.forkParent(0, pipes);
            }
        } else {
            return error.EndOfScript;
        }

        if (alloc.detectLeaks()) return error.MemoryLeaked;
    }

    fn forkParent(self: *Self, childPid: i32, pipes: [2]i32) !void {
        std.posix.close(pipes[1]);
        while (true) {
            std.time.sleep(5 * std.time.ns_per_ms);
            var buf: [16000]u8 = undefined;

            const size = std.posix.read(pipes[0], &buf) catch |err| switch (err) {
                error.WouldBlock => continue,
                else => return err,
            };

            if (size == 0) {
                break;
            }

            try self.stderr.?.writeAll(&buf);
        }

        const result = std.posix.waitpid(childPid, 0);
        self.step += 1;
        if (result.status != 0) std.debug.panic("Parent ERROR: {}", .{result});
    }

    pub fn exec(self: *Self) !void {
        while (blk: {
            self.execNext() catch |err| switch (err) {
                error.EndOfScript => break :blk false,
                else => return err,
            };
            break :blk true;
        }) {}
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

        while (self.index < self.content.len) : (self.index += 1) {
            switch (self.content[self.index]) {
                .Word => |val| try args.append(val),
                .Value => |val| try args.append(try std.fmt.allocPrint(self.alloc.allocator(), "{d}", .{val})),
                .DoubleQuote => |val| try args.append(try std.fmt.allocPrint(self.alloc.allocator(), "{s}", .{val})),
                .Space => {},
                .NewLine => {
                    self.index += 1;
                    break;
                },
            }
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
