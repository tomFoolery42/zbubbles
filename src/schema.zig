const std = @import("std");


pub const Allocator = struct {
    chat_pool:      std.heap.MemoryPool(Chat),
    message_pool:   std.heap.MemoryPool(Message),
    message_arena:  std.heap.ArenaAllocator,
};

pub const ReadStatus = struct {
    chatGuid: []const u8,
    read: bool,
};

pub const Attachment = struct {
    guid:           []const u8 = "",
//    messages:       [][]const u8 = &.{},
    data:           []const u8 = "",
//    uti:            []const u8,
    mimeType:       ?[]const u8 = "",
//    transferState:  u64 = 0,
//    totalBytes:     u64 = 0,
//    isOutgoing:     bool = false,
//    transferName:   []const u8 = "",
    isSticker:      bool = false,
//    hideAttachment: bool = false,
};

pub const Chat = struct {
    guid:                   []const u8,
    lastAddressedHandle:    []const u8 = "",
    participants:           []Handle = &.{},
    style:                  u64 = 0,
    chatIdentifier:         []const u8 = "",
    isArchived:             bool = false,
    displayName:            []const u8,
    groupId:                []const u8 = "",
    isFiltered:             bool = false,
//    messages:               ?[]Message,
};

pub const Message = struct {
    guid: []const u8, //"614739BA-3A54-4425-9BC8-0F6070370488"],
    text: []const u8, //"Just you wait. I got an awesome idea for a new one. Just dont know how to make it yet"],
    handle: ?Handle, // = .{.address = "null", .country = null, .uncanonicalizedId = null, .service = "null"}, //null,
//    handleId: u64,
//    otherHandle: u64,
    attachments: []Attachment = &.{},
    subject: ?[]const u8,
    dateCreated: u64, //1736995272029,
    dateRead: ?u64, //null,
    dateDelivered: ?u64, //1736995272387,
    isDelivered: bool, //true,
    isFromMe: bool, //true,
    hasDdResults: ?bool, //false,
    isArchived: ?bool, //false,
    groupTitle: ?[]const u8 = "", //null,
    hasPayloadData: bool, //false,
//    isDelayed: ?bool, //false,
    isAutoReply: ?bool = false, //false,
    isSystemMessage: ?bool = false, //false,
    isServiceMessage: ?bool = false, //false,
    isForward: ?bool = false, //false,
//    isCorrupt: bool = false, //false,
    datePlayed: ?u64 = null, //null,
//    cacheRoomnames: ?[]const u8, //null,
//    isSpam: bool = false, //false,
//    isExpired: bool = false, //false,
//    timeExpressiveSendPlayed: []const u8 = "", //null,
    isAudioMessage: ?bool = false, //false,
//    shareStatus: ?u64, //0,
//    shareDirection: ?u64, //0,
//    wasDeliveredQuietly: bool = false, //false,
//    didNotifyRecipient: bool = false, //false,
    chats: []Chat = &.{},
//    payloadData: ?[]const u8, //null,
//    dateEdited: ?[]const u8, //null,
//    dateRetracted: ?[]const u8, //null,
};

pub const ChatRequest = struct {
    limit:  u16,
    offset: u16,
    with:   [0][]const u8,
    sort:   []const u8,
};

pub const Handle = struct {
    address:            []const u8,
    country:            ?[]const u8,
    uncanonicalizedId:  ?[]const u8,
    service:            []const u8,
};

pub fn Response(comptime T: type) type {
    return struct {
        status:     u16,
        message:    []const u8,
        data:       T,
    };
}

pub fn ResponseEmpty() type {
    return struct {
        status:     u16,
        message:    []const u8,
    };
}

pub const TextRequest = struct {
    chatGuid:               []const u8,
    tempGuid:               []const u8 = "614739BA-3A54-4425-9BC8-0F6070370438",
    message:                []const u8,
    method:                 []const u8 = "private-api", //apple-script
    subject:                []const u8 = "",
    effectId:               []const u8 = "",
    selectedMessageGuid:    []const u8 = "",
};
