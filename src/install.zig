const std = @import("std");
const tui = @import("tui");
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("stdio.h");
});

pub const WindowData = struct {
    mutex: std.Thread.Mutex,
    step: usize,
    steps: []const []const u8,
};

pub const InstallWindow = struct {
    const Self = @This();

    stdout_buf: *std.ArrayList(u8),

    data: *WindowData,

    ui: tui.UI,

    is_running: bool = false,
    update_delay: u32 = 30,

    pub fn init(alloc: std.mem.Allocator, stdoutBuf: *std.ArrayList(u8), data: *WindowData) !InstallWindow {
        return Self{
            .ui = try tui.UI.init(alloc),
            .stdout_buf = stdoutBuf,
            .data = data,
        };
    }

    pub fn deinit(self: *Self) void {
        self.is_running = false;
        self.ui.deinit();
    }

    pub fn update(self: *Self) !void {
        var layout = tui.Layout.init();
        layout.layoutDirection = .Horz;
        try self.ui.beginWidget(&layout.widget);
        {
            var layout_steps = tui.Layout.init();
            layout_steps.widget.setBorder(.Rounded);
            try self.ui.beginWidget(&layout_steps.widget);
            {
                self.data.mutex.lock();
                defer self.data.mutex.unlock();
                var step_list = tui.List.init(.{ .w = 40, .h = 40 }, self.data.steps);
                step_list.setPadding(tui.Padding.uniformTerm(1));
                step_list.setHighlight(self.data.step, .{ .HighLight = .{ .red = 85, .green = 255, .blue = 255 } });
                try self.ui.beginWidget(&step_list.widget);
                try self.ui.endWidget();
            }
            try self.ui.endWidget();

            var layout_output = tui.Layout.init();
            layout_output.widget.setBorder(.Rounded);
            try self.ui.beginWidget(&layout_output.widget);
            {
                var textBox = tui.TextBox.init(self.stdout_buf.items, .{ .h = 40, .w = 100 });
                try self.ui.beginWidget(&textBox.widget);
                try self.ui.endWidget();
            }
            try self.ui.endWidget();
        }
        try self.ui.endWidget();
    }

    pub fn run(self: *Self) !void {
        self.is_running = true;
        while (self.is_running) {
            try self.update();

            std.time.sleep(self.update_delay * std.time.ns_per_ms);

            if (try self.ui.term.?.pollChar()) |char| {
                switch (char) {
                    'q' => self.deinit(),
                    else => {},
                }
            }
        }
    }
};
