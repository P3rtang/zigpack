const std = @import("std");
const tui = @import("lib.zig");
const KeyCode = tui.KeyCode;
const Widget = tui.Widget;
const UI = tui.UI;

pub fn CursorWidget(comptime widget: Widget) type {
    return struct {
        pub usingnamespace Widget;
        const Self = @This();

        widget: Widget = .{
            .quadFn = widget.quadFn,

            .availablePosFn = widget.availablePosFn,
            .setPosFn = widget.setPosFn,

            .setPaddingFn = widget.setPaddingFn,

            .addWidgetFn = widget.addWidgetFn,
            .drawFn = draw,

            .hasChildren = widget.hasChildren,
            .quad = widget.quad,
            .padding = widget.padding,
        },

        drawFn: *const fn (*Widget) anyerror!void,
        hasFocus: bool = true,
        cursor: tui.Pos = tui.Pos{},

        fn draw(w: *Widget) !void {
            const self = w.castWidget(Self);

            try self.drawFn(&self.widget);
            try widget.drawFn(&self.widget);

            if (w.term == null) return;
            const cursor = try w.term.?.cursor();

            if (self.hasFocus) {
                try cursor.move(.{ .x = self.cursor.x, .y = self.cursor.y });
                try cursor.show();
                try cursor.setShape(.Line);
            } else {
                try cursor.hide();
            }
        }

        fn castCW(self: *Self, comptime T: type) *T {
            return @fieldParentPtr("widget", self);
        }
    };
}

pub const InputState = struct {
    hasFocus: bool = false,
    input: std.ArrayList(u8),
};

pub fn Input(comptime KeyHandler: type) type {
    return struct {
        const Self = @This();
        const CW = CursorWidget(Widget{});
        pub usingnamespace CW;

        widget: CW = .{
            .drawFn = draw,
        },

        state: *InputState,
        key_handler: ?*const KeyHandler = null,

        pub fn init(ui: *UI, state: *InputState, width: usize) !*Self {
            var self = try ui.arena.allocator().create(Self);
            self.* = Self{ .state = state };
            self.setAnyQuad(tui.Quad{ .w = width, .h = 1 });
            self.widget.hasFocus = state.hasFocus;
            return self;
        }

        pub fn getWidget(self: *Self) *Widget {
            return &self.widget.widget;
        }

        fn draw(w: *Widget) !void {
            const cw = w.castWidget(CW);
            const self = cw.castCW(Self);

            var input = &self.state.input;

            if (w.term == null) return;

            const cursor = try w.term.?.cursor();

            if (self.state.hasFocus) {
                while (try w.term.?.pollKey()) |char| {
                    switch (char) {
                        .BACKSPACE, .DEL => _ = input.popOrNull(),
                        .CHAR => |code| {
                            switch (code) {
                                32...126 => try input.append(code),
                                else => {
                                    try input.appendSlice(try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{code}));
                                },
                            }
                        },
                        else => {},
                    }
                    if (self.key_handler) |kh| try kh.onKey(char);
                }
            }

            if (input.items.len < w.quad.w + 1) {
                cw.cursor = tui.Pos{ .x = w.quad.x + input.items.len, .y = w.quad.y };
                try cursor.move(.{ .x = w.quad.x, .y = w.quad.y });
                try w.term.?.write(input.items);
            } else {
                cw.cursor = tui.Pos{ .x = w.quad.x + w.quad.w - 1, .y = w.quad.y };
                try cursor.move(.{ .x = w.quad.x, .y = w.quad.y });
                try w.term.?.write(input.items[input.items.len - w.quad.w + 1 ..]);
            }
        }
    };
}
