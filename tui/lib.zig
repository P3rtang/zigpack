const std = @import("std");
const Term = @import("term.zig").Term;
const Window = @import("term.zig").Window;
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("termios.h");
});
usingnamespace @import("term.zig");

const WidgetError = error{
    CannotHaveChild,
};

const Widget = struct {
    const Self = @This();

    quadFn: *const fn (*Widget) Quad = getQuad,
    setQuadFn: *const fn (*Widget, Quad) void = setQuad,

    availablePosFn: *const fn (*Widget) WidgetError!Pos = availablePosDefault,
    setPosFn: *const fn (*Widget, Pos) void = setPos,

    setPaddingFn: *const fn (*Widget, Padding) void = setPaddingDefault,

    addWidgetFn: *const fn (*Widget, *Widget) anyerror!void = addWidgetDefault,
    drawFn: *const fn (*Widget) anyerror!void = drawDefault,

    hasChildren: bool = false,
    quad: Quad = Quad{},
    padding: Padding = .{},
    term: ?*Term = undefined,

    fn draw(self: *Widget) !void {
        try self.drawFn(self);
    }

    fn getQuad(self: *Widget) Quad {
        return self.quad;
    }

    fn setQuad(self: *Widget, q: Quad) void {
        self.quad = q;
    }

    fn availablePos(self: *Widget) !Pos {
        return try self.availablePosFn(self);
    }

    fn availablePosDefault(self: *Widget) !Pos {
        if (!self.hasChildren) return error.CannotHaveChild;
        return Pos{};
    }

    fn setPos(self: *Widget, pos: Pos) void {
        self.quad.x = pos.x;
        self.quad.y = pos.y;
    }

    fn addWidget(self: *Widget, child: *Widget) !void {
        if (!self.hasChildren) return error.CannotHaveChild;
        try self.addWidgetFn(self, child);
    }

    fn addWidgetDefault(self: *Widget, child: *Widget) !void {
        if (!self.hasChildren) return error.CannotHaveChild;

        const this_quad = self.quad;
        const child_quad = child.quad;
        self.setQuad(Quad{
            .x = this_quad.x,
            .y = this_quad.y,
            .w = @max(this_quad.w, child_quad.w),
            .h = this_quad.h + child_quad.h,
        });
    }

    fn drawDefault(_: *Widget) !void {}

    fn getPaddedQuad(self: *Widget) Quad {
        return Quad{
            .x = self.quad.x + self.padding.left,
            .y = self.quad.y + self.padding.top,
            .w = self.quad.w - self.padding.left - self.padding.right,
            .h = self.quad.h - self.padding.top - self.padding.bottom,
        };
    }

    fn setPaddingDefault(self: *Widget, padding: Padding) void {
        self.padding = padding;
    }

    pub fn setPadding(widget: anytype, padding: Padding) void {
        const self = widget.getWidget();

        self.quad.w = @max(padding.left + padding.right, self.quad.w);
        self.quad.h = @max(padding.top + padding.bottom, self.quad.h);
        self.setPaddingFn(self, padding);
    }

    fn cast_w(self: *Widget, comptime T: type) *T {
        const parent: *T = @fieldParentPtr("widget", self);
        return parent;
    }
};

pub fn BorderedWidget(comptime widget: Widget) type {
    const bw = struct {
        pub usingnamespace Widget;
        const Self = @This();

        widget: Widget = .{
            .quadFn = widget.quadFn,
            .setQuadFn = widget.setQuadFn,

            .availablePosFn = availablePos,
            .setPosFn = widget.setPosFn,

            .setPaddingFn = widget.setPaddingFn,

            .addWidgetFn = widget.addWidgetFn,
            .drawFn = draw,

            .hasChildren = widget.hasChildren,
            .quad = widget.quad,
            .padding = widget.padding,
        },

        drawFn: *const fn (*Widget) anyerror!void = widget.drawFn,
        availablePosFn: *const fn (*Widget) WidgetError!Pos,
        border: BorderStyle,

        fn draw(w: *Widget) !void {
            const self = w.cast_w(Self);
            w.setQuad(self.border.extendQuad(w.getQuad()));
            try self.border.draw(&self.widget);
            try self.drawFn(&self.widget);
        }

        fn cast(self: *Self, comptime T: type) *T {
            return @fieldParentPtr("widget", self);
        }

        fn getBorder(w: *Widget) BorderStyle {
            const self = w.cast_w(Self);
            return self.border;
        }

        pub fn setBorder(w: anytype, border: BorderStyle) void {
            const wid = w.getWidget();
            const self = wid.cast_w(Self);
            self.border = border;
        }

        fn availablePos(w: *Widget) !Pos {
            const self = w.cast_w(Self);
            var pos = try self.availablePosFn(&self.widget);
            if (self.border != .None) {
                pos.x += 1;
                pos.y += 1;
            }
            return pos;
        }
    };

    return bw;
}

const BorderStyle = enum {
    None,
    Rounded,

    fn draw(self: BorderStyle, widget: *Widget) !void {
        const quad = widget.getQuad();
        if (widget.term) |term| {
            switch (self) {
                .Rounded => {
                    try term.drawHorzLine(.{ .x = quad.x, .y = quad.y }, quad.w);
                    try term.drawHorzLine(.{ .x = quad.x, .y = quad.y + quad.h - 1 }, quad.w);
                    try term.drawVertLine(.{ .x = quad.x, .y = quad.y }, quad.h);
                    try term.drawVertLine(.{ .x = quad.x + quad.w - 1, .y = quad.y }, quad.h);
                    try term.move(quad.x, quad.y);
                    try term.writeAll("╭");
                    try term.move(quad.x + quad.w - 1, quad.y);
                    try term.writeAll("╮");
                    try term.move(quad.x, quad.y + quad.h - 1);
                    try term.writeAll("╰");
                    try term.move(quad.x + quad.w - 1, quad.y + quad.h - 1);
                    try term.writeAll("╯");
                },
                .None => {},
            }
        }
    }

    fn extendQuad(self: BorderStyle, quad: Quad) Quad {
        switch (self) {
            .None => return quad,
            else => return Quad{ .x = quad.x, .y = quad.y, .w = quad.w + 2, .h = quad.h + 2 },
        }
    }
};

const Direction = enum {
    Horz,
    Vert,
};

pub const Quad = struct {
    x: usize = 0,
    y: usize = 0,
    w: usize = 0,
    h: usize = 0,
};

pub const Pos = struct {
    x: usize = 0,
    y: usize = 0,
};

pub const Size = struct {
    w: usize = 0,
    h: usize = 0,
};

pub const Padding = struct {
    left: usize = 0,
    top: usize = 0,
    right: usize = 0,
    bottom: usize = 0,

    pub fn uniform(pad: usize) Padding {
        return Padding{
            .left = pad,
            .top = pad,
            .right = pad,
            .bottom = pad,
        };
    }

    pub fn uniformTerm(pad: usize) Padding {
        return Padding{
            .left = pad * 2,
            .top = pad,
            .right = pad * 2,
            .bottom = pad,
        };
    }
};

pub const UI = struct {
    const Self = @This();

    background: ?usize,
    border: BorderStyle,

    cursor: ?Pos = null,
    term: ?Term = null,

    widget: Widget = Widget{
        .hasChildren = true,
        .drawFn = draw,

        .availablePosFn = availablePos,
        .setPosFn = undefined,
    },

    widgets: std.DoublyLinkedList(*Widget),

    arena: std.heap.ArenaAllocator,

    pub fn init(alloc: std.mem.Allocator) !Self {
        var term = try Term.init(alloc);
        try term.intoRaw();
        try term.clearTerm();
        try term.move(1, 1);
        return UI{
            .background = @intCast(0xff00ff),
            .border = .None,
            .widgets = std.DoublyLinkedList(*Widget){},
            .arena = std.heap.ArenaAllocator.init(alloc),
            .term = term,
        };
    }

    pub fn initStub(alloc: std.mem.Allocator) Self {
        return UI{
            .background = @intCast(0xff00ff),
            .border = .None,
            .widgets = std.DoublyLinkedList(*Widget){},
            .arena = std.heap.ArenaAllocator.init(alloc),
        };
    }

    pub fn deinit(self: Self) void {
        if (self.term) |*t| t.deinit();
        self.arena.deinit();
    }

    fn availablePos(w: *Widget) !Pos {
        const self = w.cast_w(Self);
        switch (self.border) {
            .None => return .{ .x = 0, .y = 0 },
            else => return .{ .x = 1, .y = 1 },
        }
    }

    fn setPos(_: *Widget) void {
        unreachable;
    }

    pub fn draw(w: *Widget) !void {
        const self = w.cast_w(Self);
        if (self.term) |*term| {
            try term.flush();
        }
    }

    pub fn beginWidget(self: *Self, widget: anytype) !void {
        const pos = blk: {
            if (self.widgets.last) |last| {
                if (!last.data.hasChildren) {
                    return error.CannotHaveChild;
                }

                break :blk try last.data.availablePos();
            } else {
                break :blk Pos{ .x = 0, .y = 0 };
            }
        };

        var w = widget.getWidget();
        w.setPos(pos);
        if (self.term) |*t| w.term = t;
        const new_node = try self.arena.allocator().create(std.DoublyLinkedList(*Widget).Node);
        new_node.* = std.DoublyLinkedList(*Widget).Node{ .prev = self.widgets.last, .data = w };
        self.widgets.append(new_node);
    }

    pub fn endWidget(self: *Self) !void {
        var widget = self.widgets.pop().?;
        defer self.arena.allocator().destroy(widget);
        try widget.data.draw();

        if (self.widgets.last) |last| {
            if (!last.data.hasChildren) {
                return error.CannotHaveChild;
            }
            try last.data.addWidget(widget.data);
            return;
        }

        try self.widget.addWidget(widget.data);
        try self.widget.draw();
    }
};

pub const Layout = struct {
    const BW = BorderedWidget(.{
        .hasChildren = true,
    });
    pub usingnamespace BW;

    const Self = @This();

    layoutDirection: Direction = .Vert,

    widget: BW = .{
        .availablePosFn = availablePos,
        .border = .None,
    },

    pub fn init(ui: *UI, direction: Direction) !*Layout {
        const self = try ui.arena.allocator().create(Self);
        self.* = Self{ .layoutDirection = direction };

        return self;
    }

    fn draw(_: *Widget) !void {}

    pub fn getWidget(self: *Self) *Widget {
        return &self.widget.widget;
    }

    fn availablePos(w: *Widget) !Pos {
        const bw = w.cast_w(BW);
        const self = bw.cast(Self);

        const quad = w.getPaddedQuad();
        return blk: {
            switch (self.layoutDirection) {
                .Horz => break :blk .{ .x = quad.x + quad.w, .y = quad.y },
                .Vert => break :blk .{ .x = quad.x, .y = quad.y + quad.h },
            }
        };
    }
};

pub const DebugLayout = struct {
    const Self = @This();
    layout: Layout = Layout{ .quad = .{ .w = 20, .h = 1 } },

    pub fn init() DebugLayout {
        var this = DebugLayout{};
        this.layout.widget.drawFn = draw;
        return this;
    }

    pub fn draw(w: *Widget) !void {
        const layout = w.cast_w(Layout);
        try Layout.draw(w);

        try w.term.move(layout.quad.x + 1, layout.quad.y);
        try w.term.print("x={}, y={}, w={}, h={}", .{ layout.quad.x, layout.quad.y, layout.quad.w, layout.quad.h });
    }
};

pub const TextBox = struct {
    const Self = @This();

    text: []const u8 = "",

    widget: Widget = .{
        .drawFn = draw,
    },

    pub fn init(ui: *UI, text: []const u8, size: struct { w: usize, h: usize }) !*TextBox {
        var self = try ui.arena.allocator().create(Self);
        self.* = Self{ .text = text };
        self.widget.setQuad(Quad{ .w = size.w, .h = size.h });
        return self;
    }

    fn draw(w: *Widget) !void {
        const self = w.cast_w(Self);

        if (std.mem.eql(u8, self.text, "")) {
            return;
        }

        var lines = std.mem.splitScalar(u8, self.text, '\n');

        var idx: usize = 0;
        while (lines.next()) |line| : (idx += 1) {
            if (w.term) |term| {
                try term.move(w.getQuad().x, w.getQuad().y + idx);
                var split_r = std.mem.splitBackwardsScalar(u8, line, '\r');
                try term.writeAll(split_r.next().?);
            }
        }
    }

    fn getWidget(self: *Self) *Widget {
        return &self.widget;
    }
};

pub const Button = struct {
    const Self = @This();

    quad: Quad,
    text: []const u8,

    widget: Widget = .{
        .drawFn = draw,

        .quadFn = quad,
        .setQuadFn = setQuad,
        .availablePosFn = availablePos,
        .setPosFn = setPos,
        .padding = .{ .left = 1, .right = 1 },
    },

    pub fn withText(text: []const u8) Button {
        return Button{ .text = text, .quad = Quad{ .w = @intCast(text.len), .h = 1 } };
    }

    fn draw(w: *Widget) !void {
        const self = w.cast_w(Self);
        _ = self; // autofix
    }

    fn quad(w: *Widget) Quad {
        const self: *Button = @fieldParentPtr("widget", w);
        return self.quad;
    }

    fn setQuad(w: *Widget, q: Quad) void {
        const self: *Self = @fieldParentPtr("widget", w);
        self.quad = q;
    }

    fn availablePos(_: *Widget) Pos {
        unreachable;
    }

    fn setPos(w: *Widget, pos: Pos) void {
        const self = w.cast_w(Self);
        self.quad.x = pos.x;
        self.quad.y = pos.y;
    }
};

pub const List = struct {
    const Self = @This();

    content: []const []const u8,
    selection: usize = 0,
    selection_style: SelectStyle = .{ .None = {} },

    widget: Widget = Widget{
        .drawFn = draw,
        .availablePosFn = undefined,
    },

    pub fn init(ui: *UI, size: Size, content: []const []const u8) !*List {
        const list = try ui.arena.allocator().create(Self);
        list.* = List{ .content = content };
        list.widget.quad = Quad{ .w = size.w, .h = size.h };
        return list;
    }

    pub fn setPadding(self: *Self, padding: Padding) void {
        self.widget.padding = padding;
    }

    pub fn setHighlight(self: *Self, idx: usize, style: SelectStyle) void {
        self.selection = idx;
        self.selection_style = style;
    }

    fn draw(w: *Widget) !void {
        const self = w.cast_w(Self);

        const pad_quad = w.getPaddedQuad();

        for (self.content, 0..) |item, idx| {
            // return when dropping below the padding at the bottom
            if (idx > pad_quad.h) return;

            try w.term.?.move(pad_quad.x, pad_quad.y + idx);

            if (idx == self.selection) {
                switch (self.selection_style) {
                    .HighLight => |color| try w.term.?.print("\x1b[38;2;{};{};{}m> ", .{ color.red, color.green, color.blue }),
                    .None => try w.term.?.writeAll("> "),
                }
            } else {
                try w.term.?.writeAll("  ");
            }

            try w.term.?.print("{s}\x1b[39;49m", .{item[0..@min(pad_quad.w, item.len)]});
        }
    }

    fn getWidget(self: *Self) *Widget {
        return &self.widget;
    }
};

pub const SelectStyle = union(SelectStyleTag) {
    None: void,
    HighLight: Color,
};

pub const SelectStyleTag = enum {
    None,
    HighLight,
};

pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
};
