const std = @import("std");

pub fn StringHashMapRecorder(comptime V: type) type {
    return struct {
        allocator: std.mem.Allocator,

        snapshots: std.ArrayList(Inner),

        const Self = StringHashMapRecorder(V);

        const Inner = std.StringHashMap(V);

        const K = []const u8;

        pub fn initSnapshotsCapacity(allocator: std.mem.Allocator, snapshots_capacity: usize) std.mem.Allocator.Error!Self {
            return Self{
                .allocator = allocator,
                .snapshots = try std.ArrayList(Inner).initCapacity(allocator, snapshots_capacity),
            };
        }

        pub fn newSnapshot(self: *Self) void {
            self.snapshots.appendAssumeCapacity(Inner.init(self.allocator));
        }

        pub fn destroySnapshot(self: *Self) void {
            _ = self.snapshots.pop();
        }

        pub fn get(self: Self, key: K) ?V {
            var i = self.snapshots.items.len;

            while (i > 0) : (i -= 1) {
                if (self.snapshots.items[i - 1].get(key)) |value| {
                    return value;
                }
            }

            return null;
        }

        pub fn getFromLastSnapshot(self: Self, key: K) ?V {
            if (self.snapshots.items.len == 0) {
                return null;
            }

            return self.snapshots.getLast().get(key);
        }

        pub fn put(self: *Self, key: K, value: V) std.mem.Allocator.Error!void {
            if (self.snapshots.items.len == 0) {
                self.newSnapshot();
            }

            try self.snapshots.items[self.snapshots.items.len - 1].put(key, value);
        }
    };
}
