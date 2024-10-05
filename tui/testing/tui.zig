const std = @import("std");
const tui = @import("tui");

test "widget_interface" {
    const alloc = std.testing.allocator;
    var ui = tui.UI.initStub(alloc);
    defer ui.deinit();
    try std.testing.expectEqualDeep(tui.Quad{}, ui.widget.quad);

    {
        const textBox = try tui.TextBox.init(&ui, "", .{ .w = 20, .h = 10 });
        try ui.beginWidget(textBox);
        try ui.endWidget();
        const quad: tui.Quad = .{ .w = 20, .h = 10 };
        try std.testing.expectEqualDeep(quad, ui.widget.quad);
    }
}

test "layout_border" {
    const alloc = std.testing.allocator;
    {
        var ui = tui.UI.initStub(alloc);
        defer ui.deinit();

        const layout = try tui.Layout.init(&ui, .Vert);
        try ui.beginWidget(layout);
        {
            {
                const textBox = try tui.TextBox.init(&ui, "", .{ .w = 40, .h = 10 });
                try ui.beginWidget(textBox);
                try ui.endWidget();
            }
            {
                const textBox = try tui.TextBox.init(&ui, "", .{ .w = 40, .h = 10 });
                try ui.beginWidget(textBox);
                try ui.endWidget();
            }
        }
        try ui.endWidget();

        try std.testing.expectEqualDeep(tui.Quad{ .x = 0, .y = 0, .w = 40, .h = 20 }, layout.getAnyQuad());
    }
    {
        var ui = tui.UI.initStub(alloc);
        defer ui.deinit();

        var layout = try tui.Layout.init(&ui, .Vert);
        layout.setBorder(.Rounded);
        try ui.beginWidget(layout);
        {
            {
                const textBox = try tui.TextBox.init(&ui, "", .{ .w = 40, .h = 10 });
                try ui.beginWidget(textBox);
                try ui.endWidget();
            }
            {
                const textBox = try tui.TextBox.init(&ui, "", .{ .w = 40, .h = 10 });
                try ui.beginWidget(textBox);
                try ui.endWidget();
            }
        }
        try ui.endWidget();

        try std.testing.expectEqualDeep(tui.Quad{ .x = 0, .y = 0, .w = 42, .h = 22 }, layout.getAnyQuad());
    }
}

test "textbox_height" {
    const InputKeyHandler = struct {
        const Self = @This();

        pub fn onKey(_: *const Self, _: tui.Key) !void {
            std.debug.panic("hello???", .{});
            unreachable;
        }
    };

    var ui = tui.UI.initStub(std.testing.allocator);
    defer ui.deinit();

    var input_state = tui.InputState{
        .input = std.ArrayList(u8).init(std.testing.allocator),
    };

    var layout = try tui.Layout.init(&ui, .Horz);
    layout.setBorder(.Rounded);
    try ui.beginWidget(layout);
    {
        const input_type = try tui.TextBox.init(&ui, "$", .{ .w = 1, .h = 1 });
        try ui.beginWidget(input_type);
        try ui.endWidget();

        const input = try tui.Input(InputKeyHandler).init(&ui, &input_state, 40);
        try ui.beginWidget(input);
        try ui.endWidget();
    }
    try ui.endWidget();

    try std.testing.expectEqualDeep(tui.Quad{ .w = 43, .h = 3 }, layout.getAnyQuad());
}
