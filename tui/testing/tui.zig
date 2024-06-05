const std = @import("std");
const tui = @import("tui");

test "widget_interface" {
    const alloc = std.testing.allocator;
    var ui = tui.UI.initStub(alloc);
    defer ui.deinit();
    try std.testing.expectEqualDeep(tui.Quad{}, ui.widget.quad);

    {
        var button = tui.Button.withText("Click");
        button.setPadding(.{ .left = 2, .right = 2 });
        try ui.beginWidget(&button.widget);
        try ui.endWidget();

        const quad: tui.Quad = .{ .x = 0, .y = 0, .w = 9, .h = 1 };
        try std.testing.expectEqualDeep(quad, ui.widget.quad);
    }

    {
        var textBox = tui.TextBox.init("", .{ .w = 20, .h = 10 });
        try ui.beginWidget(&textBox.widget);
        try ui.endWidget();
        const quad: tui.Quad = .{ .w = 20, .h = 11 };
        try std.testing.expectEqualDeep(quad, ui.widget.quad);
    }
}

test "layout_border" {
    const alloc = std.testing.allocator;
    {
        var ui = tui.UI.initStub(alloc);
        defer ui.deinit();

        var layout = tui.Layout.init();
        try ui.beginWidget(&layout.widget);
        {
            {
                var textBox = tui.TextBox.init("", .{ .w = 40, .h = 10 });
                try ui.beginWidget(&textBox.widget);
                try ui.endWidget();
            }
            {
                var textBox = tui.TextBox.init("", .{ .w = 40, .h = 10 });
                try ui.beginWidget(&textBox.widget);
                try ui.endWidget();
            }
        }
        try ui.endWidget();

        try std.testing.expectEqualDeep(tui.Quad{ .x = 0, .y = 0, .w = 40, .h = 20 }, layout.widget.quad);
    }
    {
        var ui = tui.UI.initStub(alloc);
        defer ui.deinit();

        var layout = tui.Layout.init();
        layout.widget.setBorder(.Rounded);
        try ui.beginWidget(&layout.widget);
        {
            {
                var textBox = tui.TextBox.init("", .{ .w = 40, .h = 10 });
                try ui.beginWidget(&textBox.widget);
                try ui.endWidget();
            }
            {
                var textBox = tui.TextBox.init("", .{ .w = 40, .h = 10 });
                try ui.beginWidget(&textBox.widget);
                try ui.endWidget();
            }
        }
        try ui.endWidget();

        try std.testing.expectEqualDeep(tui.Quad{ .x = 0, .y = 0, .w = 42, .h = 22 }, layout.widget.quad);
    }
}
