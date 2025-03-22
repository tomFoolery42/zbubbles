const Button = @import("button.zig").Button;
//const Image = @import("image.zig").Image;
const internal = @import("internal.zig");
const VirticalView = @import("virtical.zig").VirticalView;

const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;


const BLACK: vaxis.Cell.Color = .{.rgb = .{0, 0, 0}};
const BLUE: vaxis.Cell.Color = .{.rgb = .{34, 148, 251}};
const GRAY: vaxis.Cell.Color = .{.rgb = .{116, 116, 116}};
const WHITE: vaxis.Cell.Color = .{.rgb = .{255, 255, 255}};
const input_winow_split = 0.8;
const split_split = 0.1;
const main_window_split = 0.93;

fn scale(max: u16, scaler: f32) u16 {
    const max_float: f32 = @floatFromInt(max);
    return @intFromFloat(max_float * scaler);
}

pub const Model = @This();

const MessageType = union(enum) {
    Buffer:     vxfw.Text,
    Label:      vxfw.Text,
    Text:       vxfw.Text,
    Image:      vxfw.Text,
    Reaction:   vxfw.Text,
};

fn Label(from_me: bool, contact: *internal.Contact) MessageType {
    if (from_me == true) {
        return .{
            .Label = .{.style = .{.bg = BLACK, .fg = WHITE}, .text = contact.display_name, .text_align = .right},
        };
    }
    else {
        return .{
            .Label = .{.style = .{.bg = BLACK, .fg = WHITE}, .text = contact.display_name, .text_align = .left},
        };
    }
}
fn Text(from_me: bool, text: []const u8) MessageType {
    if (from_me == true) {
        return .{
            .Text = .{.style = .{.bg = BLUE, .fg = WHITE}, .text = text, .text_align = .right},
//            .Text = .{
//                .text = &.{
//                    .{.style = .{.bg = BLUE, .fg = WHITE}, .text = text},
//                    .{.style = .{.bg = BLACK, .fg = BLACK}, .text = "     "},
//                },
//                .text_align = .right,
//            },
        };
    }
    else {
        return .{
            .Text = .{.style = .{.bg = GRAY, .fg = WHITE}, .text = text, .text_align = .left},
//            .Text = .{
//                .text = &.{
//                    .{.style = .{.bg = GRAY, .fg = WHITE}, .text = text},
//                    .{.style = .{.bg = BLACK, .fg = BLACK}, .text  = "     "},
//                },
//                .text_align = .left,
//            },
        };
    }
}
fn Image(from_me: bool) MessageType {
    if (from_me == true) {
        return .{
            .Image = .{.style = .{.bg = BLUE, .fg = WHITE}, .text  = "<==Image==>", .text_align = .right},
        };
    }
    else {
        return .{
            .Image = .{.style = .{.bg = GRAY, .fg = WHITE}, .text  = "<==Image==>", .text_align = .left},
        };
    }
}
fn Buffer() MessageType {
    return .{
        .Buffer = .{.style = .{.bg = BLACK, .fg = BLACK}, .text = "     "},
    };
}

alloc:              std.mem.Allocator,
chats_side_list:    std.ArrayList(vxfw.Text),
input:              vxfw.TextField,
input_window:       vxfw.SplitView,
messages_list:      std.ArrayList(MessageType),
messages_view:      vxfw.ListView,
send:               Button,
main_split:         vxfw.SplitView,
chats_side_view:    vxfw.ListView,
main_window:        VirticalView,
ucd:                *vaxis.Unicode,

pub fn init(alloc: std.mem.Allocator) !*Model {
    const model = try alloc.create(Model);
    const ucd = try alloc.create(vaxis.Unicode);
    ucd.* = try vaxis.Unicode.init(alloc);

    model.* = .{
        .alloc              = alloc,
        .chats_side_list    = try std.ArrayList(vxfw.Text).initCapacity(alloc, 20),
        .input              = vxfw.TextField.init(alloc, ucd),
        .input_window       = .{.lhs = undefined, .rhs = undefined, .width = 50},
        .messages_list      = try std.ArrayList(MessageType).initCapacity(alloc, 1500),
        .messages_view      = .{.children = .{.builder = vxfw.ListView.Builder{.userdata = model, .buildFn = Model.messageListBuilder}}},
        .send               = .{.label = "Send", .onClick = undefined, .userdata = undefined, .style = .{.default = .{.bg = BLUE}}},
        .main_split         = .{.lhs = undefined, .rhs = undefined, .width = 30},
        .chats_side_view    = .{.children = .{.builder = vxfw.ListView.Builder{.userdata = model, .buildFn = Model.chatListBuilder}}},
        .main_window        = .{.lhs = undefined, .rhs = undefined, .height = 50},
        .ucd                = ucd,
    };

    model.input_window.lhs = model.input.widget();
    model.input_window.rhs = model.send.widget();
    model.main_window.lhs = model.messages_view.widget();
    model.main_window.rhs = model.input_window.widget();
    model.main_split.lhs = model.chats_side_view.widget();
    model.main_split.rhs = model.main_window.widget();

    return model;
}

pub fn deinit(self: *Model) void {
    self.chats_side_list.deinit();
    self.input.deinit();
    self.messages_list.deinit();
    self.ucd.deinit();
    self.alloc.destroy(self.ucd);
    self.alloc.destroy(self);
}

pub fn chatListAdd(self: *Model, chat: internal.Chat) !void {
    const bg = if (chat.hasUnread() == true) BLUE else BLACK;
    try self.chats_side_list.append(.{.style = .{.bg = bg, .fg = WHITE}, .text = chat.display_name});
}

fn chatListBuilder(ptr: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
    const self: *const Model = @ptrCast(@alignCast(ptr));
    if (idx >= self.chats_side_list.items.len) return null;

    return self.chats_side_list.items[idx].widget();
}

pub fn redraw(self: *Model, ctx: vaxis.vxfw.DrawContext) !void {
    self.main_window.height = scale(ctx.max.height.?, main_window_split);
    self.main_split.width = scale(ctx.max.width.?, split_split);
    self.input_window.width = scale(ctx.max.width.?, input_winow_split);
}

pub fn resize(self: *Model, winsize: vaxis.Winsize) !void {
    self.main_window.height = scale(winsize.rows, main_window_split);
    self.main_split.width = scale(winsize.cols, split_split);
    self.input_window.width = scale(winsize.cols, input_winow_split);

}

pub fn mainChatRebuild(self: *Model, chat: *internal.Chat) !void {
    self.messages_list.clearRetainingCapacity();

    for (chat.messages.items, 0..chat.messages.items.len) |message, index| {
        const last_message_sender = if (index > 0) chat.messages.items[index-1].contact.display_name else "";
        const needs_label = std.mem.eql(u8, last_message_sender, message.contact.display_name) == false;
        try self.messageAdd(message, needs_label);
    }

    // view cursor handled by message add
}

pub fn messageAdd(self: *Model, new_message: internal.Message, needs_label: bool) !void {
    if (needs_label == true) {
        try self.messages_list.append(Buffer());
        try self.messages_list.append(Buffer());
        try self.messages_list.append(Label(new_message.from_me, new_message.contact));
    }

    for (new_message.attachments) |attachment| {
        _ = attachment;
        try self.messages_list.append(Image(new_message.from_me));
    }

    try self.messages_list.append(Text(new_message.from_me, new_message.text));


    self.messages_view.cursor = @intCast(self.messages_list.items.len - 1);
    self.messages_view.ensureScroll();
}

fn messageListBuilder(ptr: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
    const self: *const Model = @ptrCast(@alignCast(ptr));
    if (idx >= self.messages_list.items.len) return null;

    return switch (self.messages_list.items[idx]) {
        .Buffer     => |*buffer| buffer.widget(),
        .Label      => |*label| label.widget(),
        .Text       => |*text| text.widget(),
        .Image      => |*image| image.widget(),
        .Reaction   => |*reaction| reaction.widget(),
    };
}

pub fn widget(self: *Model) vxfw.Widget {
    return .{
        .userdata       = self,
        .eventHandler   = Model.eventHandle,
        .drawFn         = Model.drawHandle,
    };
}
