const client = @import("client.zig");
const internal = @import("internal.zig");
const ui = @import("ui.zig");
const schema = @import("schema.zig");
const Webhook = @import("webhook.zig").Webhook;

const std = @import("std");


const Config = struct {
    host:           []const u8,
    contacts_file:  []const u8,
    password:       []const u8,
};

fn config_load(alloc: std.mem.Allocator, config_file: []const u8) !std.json.Parsed(Config) {
    var file = try std.fs.cwd().openFile(config_file, .{});
    defer file.close();

    const json = try file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(json);
    return try std.json.parseFromSlice(Config, alloc, json, .{.allocate = .alloc_always, .ignore_unknown_fields = true});
}

fn contacts_load(alloc: std.mem.Allocator, contacts_file: []const u8) !internal.Contacts {
    var file = try std.fs.cwd().openFile(contacts_file, .{});
    defer file.close();

    const json = try file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(json);
    const list = try std.json.parseFromSliceLeaky([]internal.Contact, alloc, json, .{.allocate = .alloc_always, .ignore_unknown_fields = true});
    errdefer alloc.free(list);

    return internal.Contacts.fromOwnedSlice(alloc, list);
}

fn webhook_listen(webhook: *Webhook) void {
    webhook.listen() catch {};
}

fn data_sync(alloc: std.mem.Allocator, sync: *client.Sync, ui_queue: *ui.Queue, sync_queue: *client.Queue) !void {
    var running = true;
    try sync.initialSync(); // catch |err| {std.debug.print("initial sync failed? {any}\n", .{err});};
    var webhook = try Webhook.init(alloc, ui_queue);

    var webhook_handle = try std.Thread.spawn(.{}, webhook_listen, .{&webhook});
    defer webhook_handle.join();

    while (running) {
        if (sync_queue.get()) |event| {
            defer alloc.destroy(event);
            switch (event.*) {
                .Bail       => {
                    std.debug.print("sync bailing\n", .{});
                    running = false;
                },
                .Message    => |message| {
                    defer alloc.free(message.message);
                    _ = sync.send(message) catch |err| {
                        std.debug.print("got error while sending:\n\n{any}\n", .{err});
                    };
                },
                .Read => |chat_guid| {
                    sync.readMark(chat_guid) catch |err| {
                        std.debug.print("failed to mark chat {s} as read {any}\n", .{chat_guid, err});
                    };
                },
                .TypingStart => |chat_guid| {
                    sync.typingIndicate(chat_guid, true) catch |err| {
                        std.debug.print("failed to start typing indicator {any}\n", .{err});
                    };
                },
                .TypingStop => |chat_guid| {
                    sync.typingIndicate(chat_guid, false) catch |err| {
                        std.debug.print("failed to stop typing indicator {any}\n", .{err});
                    };
                },
            }
        }
    }
    webhook.deinit();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    var thread_safe_arena: std.heap.ThreadSafeAllocator = .{
        .child_allocator = gpa.allocator(),
    };
    const alloc = thread_safe_arena.allocator();
//    const alloc = gpa.allocator();

    var ui_queue = ui.Queue.init();
    defer ui_queue.deinit();
    var sync_queue = client.Queue.init();
    defer sync_queue.deinit();
    errdefer sync_queue.deinit();

    const config = try config_load(alloc, "config.json");
    defer config.deinit();
    var contacts = try contacts_load(alloc, config.value.contacts_file);
    defer contacts.deinit();

    var interface = try ui.Ui.init(alloc, &contacts, &ui_queue, &sync_queue);
    defer interface.deinit();
    var sync = try client.Sync.init(alloc, config.value.host, config.value.password, &contacts, &ui_queue, &sync_queue);
    defer sync.deinit();
    try sync.verify();


    var sync_handle = try std.Thread.spawn(.{}, data_sync, .{alloc, &sync, &ui_queue, &sync_queue});
    defer sync_handle.join();

    try interface.run(.{.framerate = 60});
    std.debug.print("interface bailed. Quitting\n", .{});
    const bail = try alloc.create(client.Event);
    bail.* = .Bail;
    try sync_queue.put(bail);
}
