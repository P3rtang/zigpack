const std = @import("std");
const Term = @import("term.zig").Term;
const Window = @import("term.zig").Window;
const c = @cImport({
    @cInclude("termios.h");
});
usingnamespace @import("term.zig");

const Widget = struct {
    quadFn: *const fn (*Widget) Quad = getQuad,
    setQuadFn: *const fn (*Widget, Quad) void = setQuad,

    availablePosFn: *const fn (*Widget) Pos,
    setPosFn: *const fn (*Widget, Pos) void = setPos,

    getBorderFn: *const fn (*Widget) BorderStyle = getBorderDefault,
    setBorderFn: *const fn (*Widget, BorderStyle) void = undefined,

    addWidgetFn: *const fn (*Widget, *Widget) anyerror!void = addWidgetDefault,
    drawFn: *const fn (*Widget) anyerror!void,

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

    fn availablePos(self: *Widget) Pos {
        return self.availablePosFn(self);
    }

    fn setPos(self: *Widget, pos: Pos) void {
        self.quad.x = pos.x;
        self.quad.y = pos.y;
    }

    fn addWidget(self: *Widget, child: *Widget) !void {
        try self.addWidgetFn(self, child);
    }

    fn addWidgetDefault(self: *Widget, child: *Widget) !void {
        const this_quad = self.quad;
        const child_quad = child.quad;
        self.setQuad(Quad{
            .x = this_quad.x,
            .y = this_quad.y,
            .w = @max(this_quad.w, child_quad.w),
            .h = this_quad.h + child_quad.h,
        });
    }

    fn getBorder(self: *Widget) BorderStyle {
        return self.getBorderFn(self);
    }

    fn getBorderDefault(_: *Widget) BorderStyle {
        return .None;
    }

    pub fn setBorder(self: *Widget, border: BorderStyle) void {
        self.setBorderFn(self, border);
    }

    fn cast(self: *Widget, comptime T: type) *T {
        const parent: *T = @fieldParentPtr("widget", self);
        return parent;
    }
};

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
    x: u32 = 0,
    y: u32 = 0,
    w: u32 = 0,
    h: u32 = 0,
};

pub const Pos = struct {
    x: u32 = 0,
    y: u32 = 0,
};

pub const Padding = struct {
    left: u32 = 0,
    top: u32 = 0,
    right: u32 = 0,
    bottom: u32 = 0,
};

pub const UI = struct {
    const Self = @This();

    background: ?u32,
    border: BorderStyle,

    cursor: ?Pos = null,
    term: ?Term = null,

    widget: Widget = Widget{
        .hasChildren = true,
        .drawFn = draw,

        .availablePosFn = availablePos,
        .setPosFn = undefined,

        .getBorderFn = getBorder,
        .setBorderFn = setBorder,
    },
    widgets: std.ArrayListUnmanaged(*Widget),

    arena: std.heap.ArenaAllocator,

    pub fn init(alloc: std.mem.Allocator) !Self {
        var term = try Term.init(alloc);
        try term.intoRaw();
        try term.clearTerm();
        try term.move(1, 1);
        return UI{
            .background = @intCast(0xff00ff),
            .border = .None,
            .widgets = std.ArrayListUnmanaged(*Widget).initBuffer(&.{}),
            .arena = std.heap.ArenaAllocator.init(alloc),
            .term = term,
        };
    }

    pub fn initStub(alloc: std.mem.Allocator) Self {
        return UI{
            .background = @intCast(0xff00ff),
            .border = .None,
            .widgets = std.ArrayListUnmanaged(*Widget).initBuffer(&.{}),
            .arena = std.heap.ArenaAllocator.init(alloc),
        };
    }

    pub fn deinit(self: Self) void {
        if (self.term) |*t| t.deinit();
        self.arena.deinit();
    }

    fn availablePos(w: *Widget) Pos {
        const self = w.cast(Self);
        switch (self.border) {
            .None => return .{ .x = 0, .y = 0 },
            else => return .{ .x = 1, .y = 1 },
        }
    }

    fn setPos(_: *Widget) void {
        unreachable;
    }

    fn getBorder(w: *Widget) BorderStyle {
        const self = w.cast(Self);
        return self.border;
    }

    fn setBorder(w: *Widget, border: BorderStyle) void {
        const self = w.cast(Self);
        self.border = border;
    }

    pub fn draw(w: *Widget) !void {
        const self = w.cast(Self);
        if (self.term) |*term| {
            try term.flush();
        }
    }

    pub fn beginWidget(self: *Self, widget: *Widget) !void {
        const pos = blk: {
            if (self.widgets.getLastOrNull()) |last| {
                if (!last.hasChildren) {
                    return error.CannotHaveChild;
                }

                break :blk last.availablePos();
            } else {
                break :blk Pos{ .x = 0, .y = 0 };
            }
        };

        widget.setPos(pos);
        if (self.term) |*t| widget.term = t;
        try self.widgets.append(self.arena.allocator(), widget);
    }

    pub fn endWidget(self: *Self) !void {
        var widget = self.widgets.pop();
        try widget.draw();

        if (self.widgets.getLastOrNull()) |last| {
            if (!last.hasChildren) {
                return error.CannotHaveChild;
            }
            var last_widget = self.widgets.getLast();
            try last_widget.addWidget(widget);
            return;
        }

        try self.widget.addWidget(widget);
        try self.widget.draw();
    }
};

pub const Layout = struct {
    const Self = @This();

    border: BorderStyle = .None,

    layoutDirection: Direction = .Vert,

    widget: Widget = .{
        .hasChildren = true,
        .drawFn = draw,

        .availablePosFn = availablePos,
        .setPosFn = setPos,

        .getBorderFn = getBorder,
        .setBorderFn = setBorder,
    },

    pub fn init() Self {
        return Self{};
    }

    fn draw(w: *Widget) !void {
        const self = w.cast(Self);
        w.setQuad(self.border.extendQuad(w.getQuad()));

        if (w.term) |term| {
            var win = try term.newWindow(w.getQuad());
            win.
        }

        try self.border.draw(w);
    }

    fn availablePos(w: *Widget) Pos {
        const self = w.cast(Self);
        const quad = w.getQuad();
        var pos: Pos = blk: {
            switch (self.layoutDirection) {
                .Horz => break :blk .{ .x = quad.x + quad.w, .y = quad.y },
                .Vert => break :blk .{ .x = quad.x, .y = quad.y + quad.h },
            }
        };

        switch (self.border) {
            .None => {},
            else => {
                pos.x += 1;
                pos.y += 1;
            },
        }

        return pos;
    }

    fn setPos(w: *Widget, pos: Pos) void {
        const self = w.cast(Self);
        self.quad.x = pos.x;
        self.quad.y = pos.y;
    }

    fn getBorder(w: *Widget) BorderStyle {
        const self = w.cast(Self);
        return self.border;
    }

    fn setBorder(w: *Widget, border: BorderStyle) void {
        const self = w.cast(Self);
        self.border = border;
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
        const layout = w.cast(Layout);
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
        .availablePosFn = availablePos,
    },

    pub fn init(text: []const u8, size: struct { w: u32, h: u32 }) Self {
        var this = Self{ .text = text };
        this.widget.setQuad(Quad{ .w = size.w, .h = size.h });
        return this;
    }

    fn draw(w: *Widget) !void {
        const self = w.cast(Self);

        if (std.mem.eql(u8, self.text, "")) {
            return;
        }

        var lines = std.mem.splitScalar(u8, self.text, '\n');

        var idx: u32 = 0;
        while (lines.next()) |line| : (idx += 1) {
            if (w.term) |term| {
                try term.move(w.getQuad().x, w.getQuad().y + idx);
                var split_r = std.mem.splitBackwardsScalar(u8, line, '\r');
                try term.writeAll(split_r.next().?);
            }
        }
    }

    fn availablePos(_: *Widget) Pos {
        unreachable;
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
        const self = w.cast(Self);
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
        const self = w.cast(Self);
        self.quad.x = pos.x;
        self.quad.y = pos.y;
    }

    pub fn setPadding(self: *Self, padding: Padding) void {
        self.widget.padding = padding;
        self.widget.setQuad(Quad{
            .x = self.quad.x,
            .y = self.quad.y,
            .w = self.quad.w + padding.left + padding.right,
            .h = self.quad.h + padding.top + padding.bottom,
        });
    }
};

pub const List = struct {
    const Self = @This();
    widget: Widget = Widget{
        .drawFn = draw,
    },

    fn draw(w: *Widget) !void {
        _ = w; // autofix
    }
};
