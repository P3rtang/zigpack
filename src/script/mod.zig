// TODO: refactor split file
const std = @import("std");
const str = @import("string").str;
const debug = @import("debug");
const Iterator = @import("utils").Iterator;
const IteratorBox = @import("utils").IteratorBox;
pub const parser = @import("parser.zig");
pub const ProcessIter = @import("process.zig");
pub const ScriptRunner = @import("runner.zig");

pub usingnamespace parser;

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

    pub fn scriptContent(self: *Script) !*IteratorBox(std.ChildProcess) {
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

        const token_iter = parser.Tokenizer.init(&self.arena, try content.toOwnedSlice());
        const process_iter = ProcessIter.init(&self.arena, token_iter.peekable());

        return try process_iter.flat_err();
    }

    fn currentStep(self: *Script) usize {
        if (self.script_iter) |si| {
            return si.index;
        } else {
            return 0;
        }
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
