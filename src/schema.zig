const std = @import("std");


pub const ReadStatus = struct {
    chatGuid: []const u8,
    read: bool,
};

pub const Attachment = struct {
    guid:           []const u8 = "",
    data:           []const u8 = "",
    mimeType:       ?[]const u8 = "",
    isSticker:      bool = false,
};

pub const Chat = struct {
    guid:                   []const u8,
//    lastAddressedHandle:    []const u8 = "",
    participants:           []Handle = &.{},
//    chatIdentifier:         []const u8 = "",
//    isArchived:             bool = false,
    displayName:            []const u8,
//    groupId:                []const u8 = "",
};

pub const Message = struct {
    guid:           []const u8,
    text:           []const u8,
    handle:         ?Handle,
//    handleId:       ?u64,
//    attachments:    []Attachment = &.{},
    dateCreated:    u64 = 0,
//    dateRead:       u64 = 0,
//    dateDelivered:  ?u64 = 0,
//    isDelivered:    bool = false,
    isFromMe:       bool = false,
//    isArchived:     bool = false,
//    groupTitle:     ?[]const u8 = "",
//    isAutoReply:    bool = false,
//    isForward:      bool = false,
//    datePlayed:     ?u64 = 0,
//    isAudioMessage: bool = false,
//    replyToGuid:    []const u8,
    chats:          []Chat,
};

pub const ChatRequest = struct {
    limit:  u16,
    offset: u16,
    with:   [0][]const u8,
    sort:   []const u8,
};

pub const Handle = struct {
    address:            []const u8,
    //country:            []const u8,
    service:            []const u8 = "",
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
    method:                 []const u8 = "private-api",
    subject:                []const u8 = "",
    effectId:               []const u8 = "",
    selectedMessageGuid:    []const u8 = "",
};
