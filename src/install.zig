const std = @import("std");
const tui = @import("tui");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("termios.h");
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
        const term_size = if (self.ui.term) |*term| try term.getSize() else tui.Size{};

        const layout = try tui.Layout.init(&self.ui, .Horz);
        try self.ui.beginWidget(layout);
        {
            var layout_steps = try tui.Layout.init(&self.ui, .Horz);
            layout_steps.setBorder(.Rounded);

            try self.ui.beginWidget(layout_steps);
            {
                self.data.mutex.lock();
                defer self.data.mutex.unlock();

                var step_list = try tui.List.init(&self.ui, .{ .w = @divFloor(term_size.w, 4), .h = term_size.h }, self.data.steps);
                step_list.setPadding(tui.Padding.uniformTerm(1));
                step_list.setHighlight(self.data.step, .{ .HighLight = .{ .red = 85, .green = 255, .blue = 255 } });

                try self.ui.beginWidget(step_list);
                try self.ui.endWidget();
            }
            try self.ui.endWidget();

            var layout_output = try tui.Layout.init(&self.ui, .Horz);
            layout_output.setPadding(tui.Padding.uniformTerm(1));
            layout_output.setBorder(.Rounded);
            try self.ui.beginWidget(layout_output);
            {
                const textBox = try tui.TextBox.init(&self.ui, self.stdout_buf.items, .{ .w = term_size.w - @divFloor(term_size.w, 4), .h = term_size.h });
                try self.ui.beginWidget(textBox);
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
