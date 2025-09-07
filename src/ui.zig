const App = @import("app.zig");
const client = @import("client.zig");
const internal = @import("internal.zig");
const MessageQueue = @import("message_queue.zig").MessageQueue;
const Model = @import("model.zig").Model;
const schema = @import("schema.zig");

const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;


pub const Event = union(enum) {
    BulkMessage:    struct {chat_guid: []const u8, messages: []const *internal.Message},
    Chat:           *internal.Chat,
    Message:        *internal.Message,
    Quit,
};
const TypingNotice = struct {
    alloc:  std.mem.Allocator,
    active: bool,
    last:   i64,
    queue:  *client.Queue,

    fn init(alloc: std.mem.Allocator, queue: *client.Queue) TypingNotice {
        return .{
            .alloc = alloc,
            .active = false,
            .last = 0,
            .queue = queue,
        };
    }

    fn activate(self: *TypingNotice, chat_guid: []const u8) !void {
        const current = std.time.timestamp();
        if (self.active == false) {
            const typing_event = try self.alloc.create(client.Event);
            typing_event.* = .{.TypingStart = chat_guid};
            try self.queue.put(typing_event);
            self.active = true;
        }
        self.last = current;
    }

    fn try_stop(self: *TypingNotice, chat_guid: []const u8) !void {
        if (self.active == true and std.time.timestamp() - self.last > TYPING_TIMEOUT) {
            try self.stop(chat_guid);
        }
    }

    fn stop(self: *TypingNotice, chat_guid: []const u8) !void {
        if (self.active == true) {
            const typing_event = try self.alloc.create(client.Event);
            typing_event.* = .{.TypingStop = chat_guid};
            try self.queue.put(typing_event);
            self.active = false;
            self.last = 0;
        }
    }
};

const EventLoop = vaxis.Loop(Event);
pub const Queue = MessageQueue(*Event, 1000);
const Widget = vxfw.Widget;
const TYPING_TIMEOUT: i64 = std.time.ns_per_s * 5;
const MINUTES_5: u64 = 5 * 60 * 1000;

pub const Ui = @This();

alloc:          std.mem.Allocator,
active_chat:    ?*internal.Chat,
asset_path:     []const u8,
chats:          std.ArrayList(*internal.Chat),
children:       [1]vxfw.SubSurface = undefined,
contacts:       *internal.Contacts,
log:            std.fs.File,
model:          *Model,
ui_queue:       *Queue,
sync_queue:     *client.Queue,
typing_notice:  TypingNotice,

fn contains(contacts: []internal.Contact, contact: *internal.Contact) bool {
    for (contacts) |next_contact| {
        if (std.mem.eql(u8, next_contact.number, contact.number)) {
            return true;
        }
    }

    return false;
}

fn containsMessage(list: *internal.Chat, new_guid: []const u8) bool {
    for (list.messages.items) |next_message| {
        if (std.mem.eql(u8, next_message.guid, new_guid)) {
            return true;
        }
    }

    return false;
}

pub fn init(alloc: std.mem.Allocator, asset_path: []const u8, contacts: *internal.Contacts, ui_queue: *Queue, sync_queue: *client.Queue) !Ui {
    return .{
        .alloc          = alloc,
        .asset_path     = asset_path,
        .chats          = try std.ArrayList(*internal.Chat).initCapacity(alloc, 50),
        .contacts       = contacts,
        .model          = try Model.init(alloc),
        .log            = try std.fs.cwd().createFile("ui.log", .{}),
        .ui_queue       = ui_queue,
        .sync_queue     = sync_queue,
        .active_chat    = null,
        .typing_notice  = TypingNotice.init(alloc, sync_queue),
    };
}

pub fn deinit(self: *Ui) void {
    self.log.close();
    self.typing_notice.stop(self.active_chat.?.guid) catch {};
    self.model.deinit();
    for (self.chats.items) |next| {
        next.deinit();
    }
    self.chats.deinit();
}

pub fn drawHandle(ptr: *anyopaque, ctx: vaxis.vxfw.DrawContext) !vxfw.Surface {
    const self: *Ui = @ptrCast(@alignCast(ptr));

    try self.model.redraw(ctx);
    const surf = try self.model.main_split.widget().draw(ctx);
    self.children[0] = .{
        .surface = surf,
        .origin = .{ .row = 0, .col = 0 },
    };

    return .{
        .size = ctx.max.size(),
        .widget = self.widget(),
        .buffer = &.{},
        .children = &self.children,
    };
}

fn eventHandle(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    const self: *Ui = @ptrCast(@alignCast(ptr));

    switch (event) {
        .init => {
            self.model.send.userdata = self;
            self.model.input.onSubmit = Ui.onSend;
            self.model.input.userdata = self;
            ctx.redraw = true;
            ctx.consumeEvent();

            try ctx.tick(3000, self.widget());
        },
        .key_press => |key| {
            if (key.matches('c', .{ .ctrl = true })) {
                ctx.quit = true;
                ctx.consumeEvent();
                std.debug.print("should be bailing!\n", .{});
            }
            else if (key.matches(vaxis.Key.up, .{.ctrl = true})) {
                if (self.active_chat) |active_chat| {
                    try self.typing_notice.stop(active_chat.guid);

                    self.model.chats_side_view.prevItem(ctx);
                    self.active_chat.? = self.chats.items[self.model.chats_side_view.cursor];
                    try self.model.mainChatRebuild(self.active_chat.?);
                    self.active_chat.?.has_new = false;

                    try ctx.setTitle(self.active_chat.?.display_name);
                    ctx.redraw = true;
                    ctx.consumeEvent();
                }
            }
            else if (key.matches(vaxis.Key.down, .{.ctrl = true})) {
                if (self.active_chat) |active_chat| {
                    try self.typing_notice.stop(active_chat.guid);

                    self.model.chats_side_view.nextItem(ctx);
                    self.active_chat.? = self.chats.items[self.model.chats_side_view.cursor];
                    try self.model.mainChatRebuild(self.active_chat.?);
                    self.active_chat.?.has_new = false;

                    try ctx.setTitle(self.active_chat.?.display_name);
                    ctx.redraw = true;
                    ctx.consumeEvent();
                }
            }
            else {
                if (self.active_chat) |active_chat| {
                    try self.typing_notice.activate(active_chat.guid);
                }
                try self.model.input.handleEvent(ctx, event);
            }

            ctx.consumeEvent();
        },
        .mouse => {
            try self.model.send.handleEvent(ctx, event);
        },
        .tick => {
            if (self.active_chat) |active_chat| {
                try self.typing_notice.try_stop(active_chat.guid);
            }

            try ctx.tick(1000, self.widget());
            ctx.consumeEvent();
        },
        .app => |user_event| {
            const queue_event: *Event = @constCast(@ptrCast(@alignCast(user_event.data)));
                defer self.alloc.destroy(queue_event);
                switch (queue_event.*) {
                    .Chat => |chat| {
                        try self.log.writer().print("got new chat: {s}\n", .{chat.display_name});
                        try self.chats.append(chat);
                        try self.model.chatListAdd(chat);
                        if (self.active_chat == null) {
                            self.active_chat = chat;
                            try ctx.setTitle(chat.display_name);
                        }
                        ctx.redraw = true;
                    },
                    .Message => |message| {
                        for (self.chats.items) |next_chat| {
                            if (
                                std.mem.eql(u8, next_chat.guid, message.chat_guid) and
                                containsMessage(next_chat, message.guid) == false)
                            {
                                try next_chat.messages.append(message);
                                if (next_chat == self.active_chat) {
                                    const last_sender =
                                        if (next_chat.messages.items.len > 0) next_chat.messages.items[next_chat.messages.items.len - 1].contact.display_name
                                        else "unnamed";
                                    const needs_label = std.mem.eql(u8, last_sender, message.contact.display_name) == false;
                                    const needs_time = next_chat.messages.items[next_chat.messages.items.len - 2].date_created - message.date_created > MINUTES_5;
                                    try self.model.messageAdd(message, needs_label,needs_time);
                                    if (message.from_me == false) {
                                        const read = try self.alloc.create(client.Event);
                                        read.* = .{.Read = next_chat.guid};
                                        try self.sync_queue.put(read);
                                    }
                                }
                                else {
                                    next_chat.has_new = true;
                                }
                                ctx.redraw = true;
                                if (message.from_me == false) {
                                    _ = try std.process.Child.run(.{ .argv = &.{"mpv", "assets/Blow.aiff", "&"}, .allocator = self.alloc });
                                }
                            }
                        }
                    },
                    .BulkMessage => |bulk| {
                        defer self.alloc.free(bulk.messages);
                        var chat: ?*internal.Chat = null;
                        for (self.chats.items) |next_chat| {
                            if (std.mem.eql(u8, next_chat.guid, bulk.chat_guid)) {
                                chat = next_chat;
                            }
                        }
                        if (chat) |found| {
                            try found.messages.appendSlice(bulk.messages);
                            if (self.active_chat) |active_chat| {
                                if (std.mem.eql(u8, active_chat.guid, found.guid)) {
                                    try self.model.mainChatRebuild(self.active_chat.?);
                                }
                            }
                            ctx.redraw = true;
                        }
                    },
                    .Quit => ctx.quit = true,
                }
            ctx.consumeEvent();
        },
        .winsize => |winsize| {
            try self.model.resize(winsize);
            ctx.redraw = true;
            ctx.consumeEvent();
        },
        else => {},
    }
}

fn onSend(ptr: ?*anyopaque, _: *vxfw.EventContext, str: []const u8) !void {
    const self: *Ui = @ptrCast(@alignCast(ptr));

    if (str.len > 0) {
        const guid = self.chats.items[self.model.chats_side_view.cursor].guid;
        const event = try self.alloc.create(client.Event);
        event.* = .{.Message = .{.message = try self.alloc.dupe(u8, str), .chatGuid = guid}};
        try self.sync_queue.put(event);
        self.model.input.clearAndFree();
    } 
}

pub fn run(self: *Ui, opts: App.Options) !void {

    var appl = try App.init(self.alloc, self.ui_queue);
    defer appl.deinit();

    try appl.run(self.widget(), opts);
    std.debug.print("app bailing. Ui bailing too\n", .{});
}

pub fn widget(self: *Ui) vxfw.Widget {
    return .{
        .userdata       = self,
        .eventHandler   = Ui.eventHandle,
        .drawFn         = Ui.drawHandle,
    };
}
