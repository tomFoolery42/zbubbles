const ui = @import("ui.zig");
const schema = @import("schema.zig");

const std = @import("std");
const httpz = @import("httpz");

pub const Webhook = @This();

const Notification = struct {
    @"type": []const u8,
    data:   std.json.Value,
};
const Impl = struct {
    alloc:      std.mem.Allocator,
    log:        std.fs.File,
    ui_queue:   *ui.Queue,
};

alloc:      std.mem.Allocator,
impl:       *Impl,
ui_queue:   *ui.Queue,
server:     httpz.Server(*Impl),

// https://github.com/karlseguin/http.zig
pub fn init(alloc: std.mem.Allocator, ui_queue: *ui.Queue) !Webhook {
    const impl = try alloc.create(Impl);
    impl.* = .{
        .alloc = alloc,
        .log = try std.fs.cwd().createFile("webhook.log", .{}),
        .ui_queue = ui_queue
    };

    return .{
        .alloc = alloc,
        .impl = impl,
        .ui_queue = ui_queue,
        .server = try httpz.Server(*Impl).init(alloc, .{.address = "0.0.0.0", .port = 8484, .request = .{.max_form_count = 20}}, impl),
    };
}

pub fn deinit(self: *Webhook) void {
    std.debug.print("webhook bailing\n", .{});
    self.impl.log.close();
    self.alloc.destroy(self.impl);
    self.server.stop();
    self.server.deinit();
    std.debug.print("webhook bailed\n", .{});
}

pub fn listen(self: *Webhook) !void {
    var router = try self.server.router(.{});

    router.post("/notifications", Webhook.notificationHandle, .{});

    self.server.listen() catch {};
    std.debug.print("server bailed\n", .{});
}

fn notificationHandle(self: *Impl, req: *httpz.Request, _: *httpz.Response) !void {
    const writer = self.log.writer();
    if (req.body()) |buffer| {
        try writer.print("buffer: {s}\n", .{buffer});
        if (std.json.parseFromSlice(Notification, self.alloc, buffer, .{.ignore_unknown_fields = true})) |response| {
            defer response.deinit();
            const notification_type = response.value.type;
            const data = response.value.data;
            if (std.mem.eql(u8, notification_type, "chat-read-status-changed")) {
                const status = try std.json.parseFromValue(schema.ReadStatus, self.alloc, data, .{.ignore_unknown_fields = true});
                _ = status;
            }
            else if (std.mem.eql(u8, notification_type, "typing-indicator")) {
                
            }
            else if (std.mem.eql(u8, notification_type, "new-message")) { // or std.mem.eql(u8, notification_type, "updated-message")) {
                const message_ptr = try self.alloc.create(ui.Event);
                message_ptr.* = .{.Message = try std.json.parseFromValueLeaky(schema.Message, self.alloc, data, .{.ignore_unknown_fields = true})};
                try self.ui_queue.put(message_ptr);
            }
            else if (std.mem.eql(u8, notification_type, "new-chat")) {
                const chat_ptr = try self.alloc.create(ui.Event);
                chat_ptr.* = .{.Chat = try std.json.parseFromValueLeaky(schema.Chat, self.alloc, data, .{.ignore_unknown_fields = true})};
                try self.ui_queue.put(chat_ptr);
            }
            else {
                try writer.print("new notification type: {s}\n", .{buffer});
            }
        }
        else |err| {
            try writer.print("uncaught response: {any}\n", .{err});
            try writer.print("message handle request: {s}\n", .{buffer});
        }
    }
}
