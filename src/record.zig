const std = @import("std");
const tui = @import("tui");
const s = @import("script");

pub const RecordUI = struct {
    const Self = @This();

    ui: tui.UI,
    update_interval: u32 = 30 * std.time.ns_per_ms,
    is_running: bool = false,
    input_state: tui.InputState,

    script: std.ArrayList([]const u8),
    output_stream: std.ArrayList(u8),

    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !RecordUI {
        const ui = try tui.UI.init(alloc);

        return Self{
            .ui = ui,
            .input_state = tui.InputState{ .input = std.ArrayList(u8).init(alloc), .hasFocus = true },
            .script = std.ArrayList([]const u8).init(alloc),
            .output_stream = std.ArrayList(u8).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        self.input_state.input.deinit();
        self.script.deinit();
        self.ui.deinit();
    }

    pub fn run(self: *Self) !void {
        self.is_running = true;
        while (self.is_running) {
            try self.update();

            std.time.sleep(self.update_interval);
        }
    }

    fn update(self: *Self) !void {
        const main_layout = try tui.Layout.init(&self.ui, .Horz);
        try self.ui.beginWidget(main_layout);
        {
            try self.left_layout();
            try self.right_layout();
        }
        try self.ui.endWidget();

        if (!self.input_state.hasFocus) {
            while (try self.ui.term.?.pollKey()) |key| {
                try self.handle_key(key);
            }
        }
    }

    fn left_layout(self: *Self) !void {
        const term_size = try self.ui.term.?.getSize();

        const layout = try tui.Layout.init(&self.ui, .Vert);
        try self.ui.beginWidget(layout);
        {
            var cmd_layout = try tui.Layout.init(&self.ui, .Horz);
            cmd_layout.setBorder(.Rounded);
            try self.ui.beginWidget(cmd_layout);
            {
                const input_type = try tui.TextBox.init(&self.ui, "$", .{ .w = 2, .h = 1 });
                try self.ui.beginWidget(input_type);
                try self.ui.endWidget();

                var input = try tui.Input(InputKeyHandler).init(&self.ui, &self.input_state, @divFloor(term_size.w, 2) - 3);
                const key_handler = InputKeyHandler{ .runner = self, .onKeyFn = handle_key };
                input.key_handler = &key_handler;
                try self.ui.beginWidget(input);
                try self.ui.endWidget();
            }
            try self.ui.endWidget();

            var script_layout = try tui.Layout.init(&self.ui, .Horz);
            script_layout.setBorder(.Rounded);
            script_layout.setPadding(tui.Padding.uniformTerm(1));
            try self.ui.beginWidget(script_layout);
            {
                const script_text = try tui.List.init(
                    &self.ui,
                    self.script.items,
                    .{ .w = @divFloor(term_size.w, 2) - 5, .h = term_size.h },
                );
                try self.ui.beginWidget(script_text);
                try self.ui.endWidget();
            }
            try self.ui.endWidget();
        }
        try self.ui.endWidget();
    }

    fn right_layout(self: *Self) !void {
        const term_size = try self.ui.term.?.getSize();

        const layout = try tui.Layout.init(&self.ui, .Horz);
        layout.setBorder(.Rounded);
        try self.ui.beginWidget(layout);
        {
            const output_buffer = try tui.TextBox.init(
                &self.ui,
                self.output_stream.items,
                .{ .w = @divFloor(term_size.w, 2) - 2, .h = term_size.h - 2 },
            );
            try self.ui.beginWidget(output_buffer);
            try self.ui.endWidget();
        }
        try self.ui.endWidget();
    }

    fn handle_key(self: *Self, key: tui.Key) !void {
        switch (key) {
            .CTRLC => self.is_running = false,
            .ENTER => {
                var arena = std.heap.ArenaAllocator.init(self.alloc);
                defer arena.deinit();

                const script_iter = s.parser.Tokenizer.init(&arena, self.input_state.input.items);
                const process_iter = try s.ProcessIter.init(&arena, script_iter.peekable()).flat_err();

                var runner = s.ScriptRunner.init(self.alloc, process_iter);

                var writer = self.output_stream.writer().any();
                runner.collectOutput(&writer, &writer, .{});

                runner.exec() catch |err| {
                    try self.output_stream.writer().print("{!}", .{err});
                };
            },
            .ESC => self.input_state.hasFocus = false,
            .CHAR => |c| {
                if (!self.input_state.hasFocus) {
                    switch (c) {
                        'i' => self.input_state.hasFocus = true,
                        'q' => self.is_running = false,
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
};

const InputKeyHandler = struct {
    const Self = @This();
    runner: *RecordUI,
    onKeyFn: *const fn (*RecordUI, tui.Key) anyerror!void,

    pub fn onKey(self: *const Self, key: tui.Key) !void {
        try self.onKeyFn(self.runner, key);
    }
};
