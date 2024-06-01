const std = @import("std");
const tui = @import("tui");
const c = @cImport(@cInclude("termios.h"));

pub const InstallWindow = struct {
    const Self = @This();

    stdout_buf: *std.ArrayList(u8),
    ui: tui.UI,

    is_running: bool = false,
    update_delay: u32 = 30,

    pub fn init(alloc: std.mem.Allocator, stdoutBuf: *std.ArrayList(u8)) InstallWindow {
        return Self{
            .ui = tui.UI.init(alloc),
            .stdout_buf = stdoutBuf,
        };
    }

    pub fn deinit(self: *Self) void {
        self.is_running = false;
        self.ui.deinit();
    }

    pub fn update(self: *Self) !void {
        var layout = tui.Layout.init();
        layout.widget.setBorder(.Rounded);
        try self.ui.beginWidget(&layout.widget);
        {
            var textBox = tui.TextBox.init(self.stdout_buf.items, .{ .h = 40, .w = 100 });
            try self.ui.beginWidget(&textBox.widget);
            try self.ui.endWidget();
        }
        try self.ui.endWidget();
    }

    pub fn run(self: *Self) !void {
        self.is_running = true;
        while (self.is_running) {
            try self.update();

            if (try std.io.getStdIn().reader().readByte() != 0) {
                self.deinit();
            }
        }
    }
};