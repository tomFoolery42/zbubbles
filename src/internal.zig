const schema = @import("schema.zig");

const std = @import("std");


pub const Allocator = struct {
    chat_pool:      std.heap.MemoryPool(Chat),
    message_pool:   std.heap.MemoryPool(Message),
};
pub const Contacts = std.ArrayList(Contact);

fn contactFind(alloc: std.mem.Allocator, contacts: *Contacts, participant: schema.Handle) !*Contact {
    for (contacts.items) |*next| {
        if (std.mem.eql(u8, next.number, participant.address) == true) {
            return next;
        }
    }

    try contacts.append(.{.display_name = try alloc.dupe(u8, participant.address), .number = try alloc.dupe(u8, participant.address)});
    return &contacts.items[contacts.items.len - 1];
}

fn find(alloc: std.mem.Allocator, contacts: *Contacts, participants: []schema.Handle) ![]Contact {
    var found_contacts = try alloc.alloc(Contact, participants.len);
    for (participants, 0..) |participant, i| {
        found_contacts[i] = (try contactFind(alloc, contacts, participant)).*;
    }

    return found_contacts;
}

pub const Attachment = struct {
    alloc:      std.mem.Allocator,
    data:       []const u8,
    guid:       []const u8,
    is_sticker: bool,
    mime_type:  []const u8,

    pub fn from(alloc: std.mem.Allocator, attachments: []schema.Attachment) ![]Attachment {
        var created: []Attachment = try alloc.alloc(Attachment, attachments.len);
        for (attachments, 0..) |attachment, i| {
            created[i] = .{
                .alloc = alloc,
                .data = try alloc.dupe(u8, attachment.data),
                .guid = try alloc.dupe(u8, attachment.guid),
                .is_sticker = attachment.isSticker,
                .mime_type = if (attachment.mimeType) |mimeType| try alloc.dupe(u8, mimeType) else "",
            };
        }

        return created;
    }

    pub fn deinit(self: *Attachment) void {
        self.alloc.free(self.data);
        self.alloc.free(self.guid);
        self.alloc.free(self.mime_type);
    }
};

pub const Chat = struct {
    display_name:   []const u8,
    guid:           []const u8,
    has_new:        bool,
    messages:       std.ArrayList(Message),
    participants:   []Contact,

    pub fn from(alloc: std.mem.Allocator, chat: schema.Chat, contacts: *Contacts) !Chat {
        const participants = try find(alloc, contacts, chat.participants);
        var display_name: []const u8 = undefined;
//        const display_name = if (participants.len == 1) try alloc.dupe(u8, participants[0].display_name) else try alloc.dupe(u8, chat.displayName);
        if (participants.len == 1) {
            display_name = try alloc.dupe(u8, participants[0].display_name);
        }
        else {
            if (chat.displayName.len > 0) {
                display_name = try alloc.dupe(u8, chat.displayName);
            }
            else {
                display_name = "unnamed chat";
            }
        }

        return .{
            .display_name   = display_name,
            .guid           = try alloc.dupe(u8, chat.guid),
            .has_new        = false,
            .messages       = try std.ArrayList(Message).initCapacity(alloc, 100),
            .participants   = try find(alloc, contacts, chat.participants),
        };
    }

    pub fn hasUnread(self: Chat) bool {
        for (self.messages.items) |message| {
            if (message.read == false) {
                return true;
            }
        }

        return false;
    }
};

pub const Contact = struct {
    display_name:   []const u8,
    number:         []const u8,

    pub fn jsonStringify(self: *const Contact, jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("display_name");
        try jws.print("{s}", .{self.display_name});

        try jws.objectField("number");
        try jws.print("{s}", .{self.number});

        try jws.endObject();
    }
};

pub const Message = struct {
    date_time:      []const u8,
    alloc:          std.mem.Allocator,
    attachments:    []Attachment,
    contact:        *Contact,
    date_created:   u64,
    from_me:        bool,
    guid:           []const u8,
    read:           bool,
    text:           []const u8,

    pub fn from(alloc: std.mem.Allocator, message: schema.Message, contacts: *Contacts) !Message {
        // first item in contacts is always me
        var contact = &contacts.items[0];
        if (message.handle) |handle| {
            if (message.isFromMe == false) {
                contact = try contactFind(alloc, contacts, handle);
            }
        }

        return .{
            .date_time      = "Some datetime",
            .alloc          = alloc,
            .attachments    = try Attachment.from(alloc, message.attachments),
            .contact        = contact,
            .date_created   = message.dateCreated,
            .from_me        = message.isFromMe,
            .guid           = try alloc.dupe(u8, message.guid),
            .read           = true,
            .text           = try alloc.dupe(u8, message.text),
        };
    }

    pub fn deinit(self: *Message) void {
        self.alloc.free(self.guid);
        self.alloc.free(self.text);
    }

    pub fn jsonStringify(self: *Contact, jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("contact");
        try jws.print("{s}", .{self.contact.number});

        try jws.objectField("date_created");
        try jws.write(self.date_created);

        try jws.objectField("guid");
        try jws.print("{s}", .{self.guid});

        try jws.objectField("text");
        try jws.write("{s}", .{self.text});

        try jws.endObject();
    }
};
