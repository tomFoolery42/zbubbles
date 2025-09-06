const internal = @import("internal.zig");
const MessageQueue = @import("message_queue.zig").MessageQueue;
const ui = @import("ui.zig");
const schema = @import("schema.zig");

const std = @import("std");


const CHAT_REQUEST              = "chat/query";
const PING                      = "ping";
const TEXT_REQUEST              = "message/text";

const Allocator = std.mem.Allocator;
pub const Event = union(enum) {
    Bail,
    Message:        schema.TextRequest,
    Read:           String,
    TypingStart:    String,
    TypingStop:     String,
};
pub const Queue = MessageQueue(*Event, 100);
const String = []const u8;
pub const Sync = @This();

alloc:      Allocator,
contacts:   *internal.Contacts,
host:       String,
client:     std.http.Client,
log:        std.fs.File,
password:   String,
ui_queue:   *ui.Queue,
sync_queue: *Queue,

pub fn init(base: Allocator, host: String, password: String, contacts: *internal.Contacts, ui_queue: *ui.Queue, sync_queue: *Queue) !Sync {
    return .{
        .alloc      = base,
        .contacts   = contacts,
        .host       = host,
        .client     = std.http.Client{.allocator = base},
        .log        = try std.fs.cwd().createFile("client.log", .{}),
        .password   = password,
        .ui_queue   = ui_queue,
        .sync_queue = sync_queue,
    };
}

pub fn deinit(self: *Sync) void {
    self.log.close();
}

fn chatsGet(self: *Sync) !schema.Response([]schema.Chat) {
    const chat_url = try std.fmt.allocPrint(self.alloc, "{s}/{s}?password={s}", .{self.host, CHAT_REQUEST, self.password});
    defer self.alloc.free(chat_url);
    const url = try std.Uri.parse(chat_url);
    var server_buffer: [1024]u8 = undefined;
    var request = try self.client.open(
        .POST,
        url,
        .{.keep_alive = false, .server_header_buffer = &server_buffer, .headers = .{.content_type = .{.override = "application/json"}}}
    );
    defer request.deinit();
    errdefer request.deinit();
    request.transfer_encoding = .chunked;

    const chat_request = schema.ChatRequest{.limit = 1000, .offset = 0, .with = .{}, .sort = "lastmessage"};
    try request.send();
    try std.json.stringify(chat_request, .{}, request.writer());
    try request.finish();
    try request.wait();
    const json = try request.reader().readAllAlloc(self.alloc, std.math.maxInt(usize));
    defer self.alloc.free(json);
    try self.log.writer().print("chats: {s}\n", .{json});
    const chats = try std.json.parseFromSliceLeaky(schema.Response([]schema.Chat), self.alloc, json, .{.allocate = .alloc_always, .ignore_unknown_fields = true});

    return chats;
}

pub fn initialSync(self: *Sync) !void {
    const response = try self.chatsGet();
    defer self.alloc.destroy(&response);
    for (response.data) |chat| {
        const new_event = try self.alloc.create(ui.Event);
        new_event.* = .{.Chat = chat};
        try self.ui_queue.put(new_event);

        if (self.messagesGet(chat.guid, null)) |messages| {
            const bulk_ptr = try self.alloc.create(ui.Event);
            bulk_ptr.* = .{.BulkMessage = .{.chat_guid = chat.guid, .messages = messages}};
            try self.ui_queue.put(bulk_ptr);
        }
        else |err| {try self.log.writer().print("failed to parse for {s}. Error: {s}\n", .{chat.guid, std.json.fmt(err, .{})});}
    }
}

pub fn messagesGet(self: *Sync, guid: String, after_date: ?u64) ![]schema.Message {
    const chat_request = if (after_date) |after| try std.fmt.allocPrint(self.alloc, "{s}/chat/{s}/message?password={s}&limit={d}&after={d}", .{ //&with=attachment", .{
        self.host,
        guid,
        self.password,
        1000,
        after+1,
    }) else try std.fmt.allocPrint(self.alloc, "{s}/chat/{s}/message?password={s}&limit={d}", .{ //&with=attachment", .{
        self.host,
        guid,
        self.password,
        1000,
    });
    defer self.alloc.free(chat_request);
    const url = try std.Uri.parse(chat_request);
    var server_buffer: [1024]u8 = undefined;
    var request = try self.client.open(.GET, url, .{.keep_alive = false, .server_header_buffer = &server_buffer});
    defer request.deinit();

    try request.send();
    try request.wait();
    const json = try request.reader().readAllAlloc(self.alloc, std.math.maxInt(usize));
    defer self.alloc.free(json);
    const list = std.json.parseFromSliceLeaky(schema.Response([]schema.Message), self.alloc, json, .{.allocate = .alloc_always, .ignore_unknown_fields = true}) catch |err| {
        try self.log.writer().print("new message: {s}\n", .{json});
        return err;
    };

    return list.data;
}

pub fn readMark(self: *Sync, chat_guid: String) !void {
    const alloc = self.alloc;
    const read_url = try std.fmt.allocPrint(alloc, "{s}/chat/{s}/read?password={s}", .{self.host, chat_guid, self.password});
    defer alloc.free(read_url);
    const url = try std.Uri.parse(read_url);
    var server_buffer: [1024]u8 = undefined;
    var request = try self.client.open(
        .POST,
        url,
        .{.keep_alive = false, .server_header_buffer = &server_buffer, .headers = .{.content_type = .{.override = "application/json"}}},
    );
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();
    const json = try request.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(json);
    const response = std.json.parseFromSlice(schema.ResponseEmpty(), alloc, json, .{.ignore_unknown_fields = true}) catch |err| {
        std.debug.print("failed to parse {s}\n", .{json});
        std.debug.print("error: {any}\n", .{err});
        return;
    };
    defer response.deinit();
}

pub fn send(self: *Sync, text_request: schema.TextRequest) !bool {
    const alloc = self.alloc;
    const send_url = try std.fmt.allocPrint(alloc, "{s}/{s}?password={s}", .{self.host, TEXT_REQUEST, self.password});
    defer alloc.free(send_url);
    const url = try std.Uri.parse(send_url);
    var server_buffer: [1024]u8 = undefined;
    var request = try self.client.open(
        .POST,
        url,
        .{.keep_alive = false, .server_header_buffer = &server_buffer, .headers = .{.content_type = .{.override = "application/json"}}},
    );
    defer request.deinit();
    request.transfer_encoding = .chunked;

    try request.send();
    try std.json.stringify(text_request, .{}, request.writer());
    try request.finish();
    try request.wait();

    const json = try request.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(json);
    const parsed = std.json.parseFromSlice(schema.Response(schema.Message), alloc, json, .{.ignore_unknown_fields = true}) catch |err| {
        std.debug.print("failed to send message: {any}\n", .{err});
        return false;
    };
    defer parsed.deinit();

    return true;
}

pub fn typingIndicate(self: *Sync, chat_guid: String, typing: bool) !void {
    const alloc = self.alloc;
    const request_type: std.http.Method = if (typing) .POST else .DELETE;
    const typing_request = try std.fmt.allocPrint(alloc, "{s}/chat/{s}/typing?password={s}", .{self.host, chat_guid, self.password});
    defer alloc.free(typing_request);
    const url = try std.Uri.parse(typing_request);
    var server_buffer: [1024]u8 = undefined;
    var request = try self.client.open(
        request_type,
        url,
        .{.keep_alive = false, .server_header_buffer = &server_buffer, .headers = .{.content_type = .{.override = "application/json"}}}
    );
    defer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();
    const json = try request.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(json);
    const parsed = try std.json.parseFromSlice(schema.ResponseEmpty(), alloc, json, .{.ignore_unknown_fields = true});
    defer parsed.deinit();
}

pub fn verify(self: *Sync) !void {
    const alloc = self.alloc;
    const ping_request = try std.fmt.allocPrint(alloc, "{s}/{s}?password={s}", .{self.host, PING, self.password});
    defer alloc.free(ping_request);
    const url = try std.Uri.parse(ping_request);
    var server_buffer: [1024]u8 = undefined;
    var request = try self.client.open(.GET, url, .{.keep_alive = false, .server_header_buffer = &server_buffer,});
    defer request.deinit();
    errdefer request.deinit();

    try request.send();
    try request.finish();
    try request.wait();
    const json = try request.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(json);
    // should make it so if it fails (such as cant log in) then the function will fail and quit
    const parsed = try std.json.parseFromSlice(schema.Response(String), alloc, json, .{.ignore_unknown_fields = true});
    defer parsed.deinit();
}
