const std = @import("std");
const tui = @import("tui");
const UI = tui.UI;

pub const TestUI = struct {
    const Self = @This();

    ui: UI,

    is_running: bool = false,
    update_delay: u32 = 30,

    update_timer: i64 = 0,

    input_state: tui.InputState,

    input_list: std.ArrayList([]const u8),

    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !TestUI {
        const ui = try UI.init(alloc);
        const input_state = tui.InputState{
            .hasFocus = true,
            .input = std.ArrayList(u8).init(alloc),
        };

        return Self{
            .ui = ui,
            .input_state = input_state,
            .input_list = std.ArrayList([]const u8).init(alloc),
            .alloc = alloc,
        };
    }

    fn deinit(self: *Self) void {
        self.is_running = false;
        self.input_state.input.deinit();
        self.input_list.deinit();
        self.ui.deinit();
    }

    pub fn update(self: *Self) !void {
        const term_size = try self.ui.term.?.getSize();

        const layout = try tui.Layout.init(&self.ui, .Horz);
        try self.ui.beginWidget(layout);
        {
            const layout_left = try tui.Layout.init(&self.ui, .Vert);
            try self.ui.beginWidget(layout_left);
            {
                var layout_keys = try tui.Layout.init(&self.ui, .Horz);
                layout_keys.setBorder(.Rounded);
                try self.ui.beginWidget(layout_keys);
                {
                    const input = try tui.Input(InputKeyHandler).init(&self.ui, &self.input_state, 24);
                    var key_handler = InputKeyHandler{
                        .runner = self,
                        .onKeyFn = input_on_key,
                    };
                    input.key_handler = &key_handler;
                    try self.ui.beginWidget(input);
                    try self.ui.endWidget();
                }
                try self.ui.endWidget();

                var layout_list = try tui.Layout.init(&self.ui, .Horz);
                layout_list.setBorder(.Rounded);
                try self.ui.beginWidget(layout_list);
                {
                    const list = try tui.List.init(
                        &self.ui,
                        self.input_list.items,
                        .{ .w = 24, .h = @divFloor(term_size.h, 2) },
                    );
                    try self.ui.beginWidget(list);
                    try self.ui.endWidget();
                }
                try self.ui.endWidget();

                var layout_debug = try tui.Layout.init(&self.ui, .Horz);
                layout_debug.setBorder(.Rounded);
                try self.ui.beginWidget(layout_debug);
                {
                    const timer_text = try tui.TextBox.init(
                        &self.ui,
                        try std.fmt.allocPrint(self.alloc, "update timer: {d:.3}μms", .{@as(f64, @floatFromInt(self.update_timer)) / 1000.0}),
                        .{ .w = 24, .h = @divFloor(term_size.h, 3) },
                    );
                    try self.ui.beginWidget(timer_text);
                    try self.ui.endWidget();
                }
                try self.ui.endWidget();
            }
            try self.ui.endWidget();
        }
        try self.ui.endWidget();
    }

    fn input_on_key(self: *Self, key: tui.Key) !void {
        switch (key) {
            .ENTER => {
                if (self.input_state.input.items.len > 0) {
                    try self.input_list.append(try self.input_state.input.toOwnedSlice());
                }
            },
            .ESC => self.input_state.hasFocus = false,
            else => {},
        }
    }

    pub fn run(self: *Self) !void {
        self.is_running = true;
        while (self.is_running) {
            std.time.sleep(self.update_delay * std.time.ns_per_ms);

            const start = std.time.microTimestamp();
            try self.update();
            self.update_timer = std.time.microTimestamp() - start;

            while (try self.ui.term.?.pollKey()) |char| {
                switch (char) {
                    .CHAR => |code| {
                        switch (code) {
                            3, 'q' => {
                                self.deinit();
                                return;
                            },
                            else => {},
                        }
                    },
                    // tab
                    .TAB => self.input_state.hasFocus = true,
                    // 13 => {
                    //     try self.key_list.append('\n');
                    // },
                    // 1, 2, 4...8, 10...12, 14...26 => {
                    //     try self.key_list.appendSlice("ctrl+");
                    // },
                    else => {},
                }
            }
        }
    }
};

pub const InputKeyHandler = struct {
    const Self = @This();
    runner: *TestUI,
    onKeyFn: *const fn (*TestUI, tui.Key) anyerror!void,

    pub fn onKey(self: *const Self, key: tui.Key) !void {
        try self.onKeyFn(self.runner, key);
    }
};
