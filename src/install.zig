const std = @import("std");
const tui = @import("tui");
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("stdio.h");
});

pub const InstallWindow = struct {
    const Self = @This();

    stdout_buf: *std.ArrayList(u8),
    ui: tui.UI,

    is_running: bool = false,
    update_delay: u32 = 30,

    pub fn init(alloc: std.mem.Allocator, stdoutBuf: *std.ArrayList(u8)) !InstallWindow {
        return Self{
            .ui = try tui.UI.init(alloc),
            .stdout_buf = stdoutBuf,
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
                var textBox = tui.TextBox.init("zig", .{ .h = 40, .w = 40 });
                try self.ui.beginWidget(&textBox.widget);
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
