const std = @import("std");
const tui = @import("tui");
const MockTerm = @import("mock.zig").MockTerm;

const alloc = std.testing.allocator;
test "default-grid" {
    var mock_term = MockTerm(200, 100).init(alloc);
    var ui = try tui.UI.init(alloc, mock_term.term());

    defer {
        mock_term.deinit();
        ui.deinit();
    }

    const grid = try tui.Grid(2, 2).init(&ui);

    const layout_1 = try tui.Layout.init(&ui, .Horz);
    const layout_2 = try tui.Layout.init(&ui, .Horz);
    const layout_3 = try tui.Layout.init(&ui, .Horz);
    const layout_4 = try tui.Layout.init(&ui, .Horz);

    try grid.insert(.{ .position = .{ .row = 0, .col = 0 }, .widget = layout_1.getWidget() });
    try grid.insert(.{ .position = .{ .row = 0, .col = 1 }, .widget = layout_2.getWidget() });
    try grid.insert(.{ .position = .{ .row = 1, .col = 0 }, .widget = layout_3.getWidget() });
    try grid.insert(.{ .position = .{ .row = 1, .col = 1 }, .widget = layout_4.getWidget() });

    try ui.beginWidget(grid);
    try ui.endWidget();

    std.debug.print("{s}", .{mock_term.buffer});
}
