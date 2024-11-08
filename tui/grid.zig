const std = @import("std");
const super = @import("lib.zig");

pub fn Grid(comptime R: usize, comptime C: usize) type {
    return struct {
        const Self = @This();

        const BW = super.BorderedWidget(super.Widget{ .hasChildren = true });
        usingnamespace BW;

        items: GridItems(R, C) = GridItems(R, C){},

        border: super.BorderStyle = .None,

        widget: BW = .{
            .drawFn = draw,
            .availablePosFn = availablePos,
            .addWidgetFn = addWidget,
        },

        pub fn init(ui: *super.UI) !*Self {
            const self = try ui.arena.allocator().create(Self);
            self.* = .{};
            return self;
        }

        fn draw(w: *super.Widget) !void {
            const bw = w.castWidget(BW);
            const self = bw.cast(Self);

            w.setQuad(self.border.extendQuad(w.getQuad()));
            try self.border.draw(self.getWidget());
        }

        pub fn getWidget(self: *Self) *super.Widget {
            return &self.widget.widget;
        }

        fn availablePos(w: *super.Widget) !super.Pos {
            // const self = w.castWidget(Self);
            const quad = w.getQuad();
            return .{ .x = quad.x, .y = quad.y };
        }

        fn addWidget(w: *super.Widget, child: *super.Widget) !void {
            const bw = w.castWidget(BW);
            const self = bw.cast(Self);
            _ = child;
            _ = self;
        }

        pub fn insert(self: *Self, widget: GridItemWidget) !void {
            try self.items.insert(widget);
        }
    };
}

pub const GridItemWidget = struct {
    position: struct { row: usize, col: usize },
    span: struct { row: usize = 1, col: usize = 1 } = .{},

    widget: *super.Widget,
};

pub fn GridItems(comptime R: usize, comptime C: usize) type {
    return struct {
        const Self = @This();

        position: usize = 0,
        children: [R * C]GridItemWidget = undefined,

        pub fn insert(self: *Self, widget: GridItemWidget) !void {
            const insert_index = self.position;
            self.position += widget.span.col * widget.span.row;

            if (self.position > R * C) {
                return error.ChildOutsideGrid;
            }

            self.children[insert_index] = widget;
        }
    };
}

const GridError = error{ChildOutsideGrid};
