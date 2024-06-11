const std = @import("std");

const GarbageCollector = @import("gc/GarbageCollector.zig");

const Driver = @import("Driver.zig");

pub fn main() u8 {
    const allocator = GarbageCollector.allocator();

    var args_iterator = std.process.argsWithAllocator(allocator) catch |err| {
        std.debug.print("{s}\n", .{Driver.errorDescription(err)});

        return 1;
    };

    var driver = Driver.init(allocator);

    return driver.run(&args_iterator);
}
