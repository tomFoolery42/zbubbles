const std = @import("std");

pub fn MessageQueue(comptime T: type, comptime max_size: u32) type {
    return struct {
        const Self = @This();
        queue:      std.fifo.LinearFifo(T, .{.Static = max_size}),
        condition:  std.Thread.Condition,
        mutex:      std.Thread.Mutex,

        pub fn init() Self {
            return .{
                .queue = std.fifo.LinearFifo(T, .{.Static = max_size}).init(),
                .condition = .{},
                .mutex = .{}
            };
        }

        pub fn deinit(self: *Self) void {
            self.kill();
            self.queue.deinit();
        }

        pub fn get(self: *Self) ?T {
            if (self.queue.readableLength() == 0) {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.condition.wait(&self.mutex);
            }

            return self.queue.readItem();
        }

        pub fn next(self: *Self) ?T {
            return self.queue.readItem();
        }

        pub fn put(self: *Self, item: T) !void {
            try self.queue.writeItem(item);
            self.condition.signal();
        }

        pub fn kill(self: *Self) void {
            self.condition.signal();
        }
    };
}
