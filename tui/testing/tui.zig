const std = @import("std");
const tui = @import("tui");
const MockTerm = @import("mock.zig").MockTerm;

const alloc = std.testing.allocator;
test "widget_interface" {
    var mock_term = MockTerm(200, 100).init(alloc);
    var ui = try tui.UI.init(alloc, mock_term.term());

    defer {
        mock_term.deinit();
        ui.deinit();
    }

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
    {
        var mock_term = MockTerm(200, 100).init(alloc);
        var ui = try tui.UI.init(alloc, mock_term.term());

        defer {
            mock_term.deinit();
            ui.deinit();
        }

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
        var mock_term = MockTerm(200, 100).init(alloc);
        var ui = try tui.UI.init(alloc, mock_term.term());

        defer {
            mock_term.deinit();
            ui.deinit();
        }

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

    var mock_term = MockTerm(200, 100).init(alloc);
    var ui = try tui.UI.init(alloc, mock_term.term());

    defer {
        mock_term.deinit();
        ui.deinit();
    }

    var input_state = tui.InputState{
        .input = std.ArrayList(u8).init(alloc),
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
