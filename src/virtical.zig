const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

const vxfw = vaxis.vxfw;

pub const VirticalView = @This();

lhs: vxfw.Widget,
rhs: vxfw.Widget,
constrain: enum { lhs, rhs } = .lhs,
style: vaxis.Style = .{},
/// min width for the constrained side
min_height: u16 = 0,
/// max width for the constrained side
max_height: ?u16 = null,
/// Target width to draw at
height: u16,

/// Used to calculate mouse events when our constraint is rhs
last_max_height: ?u16 = null,

/// Statically allocated children
children: [2]vxfw.SubSurface = undefined,

// State
pressed: bool = false,
mouse_set: bool = false,

pub fn widget(self: *const VirticalView) vxfw.Widget {
    return .{
        .userdata = @constCast(self),
        .eventHandler = typeErasedEventHandler,
        .drawFn = typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *VirticalView = @ptrCast(@alignCast(ptr));
    switch (event) {
        .mouse_leave => {
            self.pressed = false;
            return;
        },
        .mouse => {},
        else => return,
    }
    const mouse = event.mouse;

    const separator_col: u16 = switch (self.constrain) {
        .lhs => self.height,
        .rhs => if (self.last_max_height) |max|
            max -| self.height -| 1
        else {
            ctx.redraw = true;
            return;
        },
    };

    // If we are on the separator, we always set the mouse shape
    if (mouse.col == separator_col) {
        try ctx.setMouseShape(.@"ew-resize");
        self.mouse_set = true;
        // Set pressed state if we are a left click
        if (mouse.type == .press and mouse.button == .left) {
            self.pressed = true;
        }
    } else if (self.mouse_set) {
        // If we have set the mouse state and *aren't* over the separator, default the mouse state
        try ctx.setMouseShape(.default);
        self.mouse_set = false;
    }

    // On release, we reset state
    if (mouse.type == .release) {
        self.pressed = false;
        self.mouse_set = false;
        try ctx.setMouseShape(.default);
    }

    // If pressed, we always keep the mouse shape and we update the width
    if (self.pressed) {
        try ctx.setMouseShape(.@"ew-resize");
        switch (self.constrain) {
            .lhs => {
                self.height = @max(self.min_height, mouse.col);
                if (self.max_height) |max| {
                    self.height = @min(self.height, max);
                }
            },
            .rhs => {
                const last_max = self.last_max_height orelse return;
                self.height = @min(last_max -| self.min_height, last_max -| mouse.col -| 1);
                if (self.max_height) |max| {
                    self.height = @max(self.height, max);
                }
            },
        }
        ctx.consume_event = true;
    }
}

fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *VirticalView = @ptrCast(@alignCast(ptr));
    // Fills entire space
    const max = ctx.max.size();
    // Constrain width to the max
    self.height = @min(self.height, max.height);
    self.last_max_height = max.height;

    // The constrained side is equal to the width
    const constrained_min: vxfw.Size = .{ .width = max.width, .height = self.height };
    const constrained_max = vxfw.MaxSize.fromSize(constrained_min);

    const unconstrained_min: vxfw.Size = .{ .width = max.width, .height = max.height -| self.height -| 1 };
    const unconstrained_max = vxfw.MaxSize.fromSize(unconstrained_min);

    var children = try std.ArrayList(vxfw.SubSurface).initCapacity(ctx.arena, 2);

    switch (self.constrain) {
        .lhs => {
            if (constrained_max.width.? > 0 and constrained_max.height.? > 0) {
                const lhs_ctx = ctx.withConstraints(constrained_min, constrained_max);
                const lhs_surface = try self.lhs.draw(lhs_ctx);
                children.appendAssumeCapacity(.{
                    .surface = lhs_surface,
                    .origin = .{ .row = 0, .col = 0 },
                });
            }
            if (unconstrained_max.width.? > 0 and unconstrained_max.height.? > 0) {
                const rhs_ctx = ctx.withConstraints(unconstrained_min, unconstrained_max);
                const rhs_surface = try self.rhs.draw(rhs_ctx);
                children.appendAssumeCapacity(.{
                    .surface = rhs_surface,
                    .origin = .{ .row = self.height + 1, .col = 0 },
                });
            }
            var surface = try vxfw.Surface.initWithChildren(
                ctx.arena,
                self.widget(),
                max,
                children.items,
            );
            for (0..max.height) |row| {
                surface.writeCell(self.height, @intCast(row), .{
                    .char = .{ .grapheme = "_", .width = 1 },
                    .style = self.style,
                });
            }
            return surface;
        },
        .rhs => {
            if (unconstrained_max.width.? > 0 and unconstrained_max.height.? > 0) {
                const lhs_ctx = ctx.withConstraints(unconstrained_min, unconstrained_max);
                const lhs_surface = try self.lhs.draw(lhs_ctx);
                children.appendAssumeCapacity(.{
                    .surface = lhs_surface,
                    .origin = .{ .row = 0, .col = 0 },
                });
            }
            if (constrained_max.width.? > 0 and constrained_max.height.? > 0) {
                const rhs_ctx = ctx.withConstraints(constrained_min, constrained_max);
                const rhs_surface = try self.rhs.draw(rhs_ctx);
                children.appendAssumeCapacity(.{
                    .surface = rhs_surface,
                    .origin = .{ .row = unconstrained_max.height.? + 1, .col = 0 },
                });
            }
            var surface = try vxfw.Surface.initWithChildren(
                ctx.arena,
                self.widget(),
                max,
                children.items,
            );
            for (0..max.height) |row| {
                surface.writeCell(max.height -| self.height -| 1, @intCast(row), .{
                    .char = .{ .grapheme = "_", .width = 1 },
                    .style = self.style,
                });
            }
            return surface;
        },
    }
}

test VirticalView {
    // Boiler plate draw context
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const ucd = try vaxis.Unicode.init(arena.allocator());
    vxfw.DrawContext.init(&ucd, .unicode);

    const draw_ctx: vxfw.DrawContext = .{
        .arena = arena.allocator(),
        .min = .{},
        .max = .{ .width = 16, .height = 16 },
        .cell_size = .{ .width = 10, .height = 20 },
    };

    // Create LHS and RHS widgets
    const lhs: vxfw.Text = .{ .text = "Left hand side" };
    const rhs: vxfw.Text = .{ .text = "Right hand side" };

    var split_view: VirticalView = .{
        .lhs = lhs.widget(),
        .rhs = rhs.widget(),
        .width = 8,
    };

    const split_widget = split_view.widget();
    {
        const surface = try split_widget.draw(draw_ctx);
        // SplitView expands to fill the space
        try std.testing.expectEqual(@as(vxfw.Size, .{ .width = 16, .height = 16 }), surface.size);
        // It has two children
        try std.testing.expectEqual(2, surface.children.len);
        // The left child should have a width = SplitView.width
        try std.testing.expectEqual(split_view.width, surface.children[0].surface.size.width);
    }

    // Send the widget a mouse press on the separator
    var mouse: vaxis.Mouse = .{
        // The separator is width + 1
        .col = split_view.width + 1,
        .row = 0,
        .type = .press,
        .button = .left,
        .mods = .{},
    };

    var ctx: vxfw.EventContext = .{
        .cmds = std.ArrayList(vxfw.Command).init(arena.allocator()),
    };
    try split_widget.handleEvent(&ctx, .{ .mouse = mouse });
    // We should get a command to change the mouse shape
    try std.testing.expect(ctx.cmds.items[0] == .set_mouse_shape);
    try std.testing.expect(ctx.redraw);
    try std.testing.expect(split_view.pressed);

    // If we move the mouse, we should update the width
    mouse.col = 2;
    mouse.type = .drag;
    try split_widget.handleEvent(&ctx, .{ .mouse = mouse });
    try std.testing.expect(ctx.redraw);
    try std.testing.expect(split_view.pressed);
    try std.testing.expectEqual(mouse.col - 1, split_view.width);
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
