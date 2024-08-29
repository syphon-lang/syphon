const std = @import("std");

const Driver = @import("Driver.zig");
const gc = @import("gc.zig");

pub fn main() u8 {
    const allocator = gc.allocator();

    var arg_iterator = std.process.argsWithAllocator(allocator) catch |err| {
        std.debug.print("{s}\n", .{Driver.errorDescription(err)});

        return 1;
    };

    var driver = Driver.init(allocator);

    return driver.run(&arg_iterator);
}
