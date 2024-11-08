const std = @import("std");
const lib = @import("lib.zig");
const Widget = lib.Widget;
const UI = lib.UI;
const Quad = lib.Quad;

pub const TextBox = struct {
    const Self = @This();
    usingnamespace Widget;

    text: []const u8 = "",
    wrap: WrapBehaviour = .Wrap,

    widget: Widget = .{
        .drawFn = draw,
    },

    pub fn init(ui: *UI, text: []const u8, size: struct { w: usize, h: usize }) !*TextBox {
        var self = try ui.arena.allocator().create(Self);
        self.* = Self{ .text = text };
        self.setAnyQuad(Quad{ .w = size.w, .h = size.h });
        return self;
    }

    fn draw(w: *Widget) !void {
        const self = w.castWidget(Self);

        if (std.mem.eql(u8, self.text, "")) {
            return;
        }

        if (w.term) |term| {
            const cursor = try term.cursor();
            const quad = w.getQuad();
            try cursor.move(.{ .x = quad.x, .y = quad.y });

            var row: usize = 0;
            var col: usize = 0;
            for (self.text) |char| {
                switch (char) {
                    '\n' => row += 1,
                    '\r' => {},
                    else => {
                        try term.write(&.{char});
                        if (col < quad.w - 1) {
                            col += 1;
                            continue;
                        } else {
                            row += 1;
                        }
                    },
                }
                col = 0;
                try cursor.move(.{ .x = quad.x, .y = quad.y + row });
            }
        }
    }

    pub fn getWidget(self: *Self) *Widget {
        return &self.widget;
    }
};

pub const WrapBehaviour = enum {
    Wrap,
    Nowrap,
};
