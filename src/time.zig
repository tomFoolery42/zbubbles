const std = @import("std");


pub const Month = [12][]const u8 {
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
};

pub const DateTime = @This();

alloc:  std.mem.Allocator,
year:   u32,
month:  u8, //u4,
day:    u8, //u5,
hour:   u8, //u4,
minute: u8, //u6,
second: u8, //u6,
str:    []const u8,


pub fn as_str(self: DateTime) []const u8 {
    return self.str;
}

pub fn deinit(self: *DateTime) void {
    self.alloc.free(self.str);
}

pub fn fromApple(alloc: std.mem.Allocator, secs: u64) !DateTime {
    return from(alloc, secs + std.time.epoch.ios);
}

pub fn now(alloc: std.mem.Allocator) !DateTime {
    return from(alloc, std.time.timestamp());
}

pub fn from(alloc: std.mem.Allocator, secs: u64) !DateTime {
    const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = secs };
    const epoch_day     = epoch_seconds.getEpochDay();
    const day_seconds   = epoch_seconds.getDaySeconds();
    const year_day      = epoch_day.calculateYearDay();
    const month_day     = year_day.calculateMonthDay();

    const secs_so_far   = day_seconds.secs;
    const second: u6    = @truncate(secs_so_far % 60);
    const minute: u6    = @truncate((secs_so_far % 3600) / 60);
    const hour: u4      = @truncate(secs_so_far / 3600);

    return .{
        .alloc  = alloc,
        .year   = year_day.year + 1970,
        .month  = month_day.month.numeric(),
        .day    = month_day.day_index,
        .hour   = hour,
        .minute = minute,
        .second = second,
        .str    = try std.fmt.allocPrint(alloc, "{s} {d:0>2} - {d:0>2}:{d:0>2}:{d:0>2}", .{Month[month_day.month.numeric()-1], month_day.day_index, hour, minute, second}),
    };
}
