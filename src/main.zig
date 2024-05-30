const std = @import("std");

const Driver = @import("Driver.zig");

pub fn main() u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    var arena_instance = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_instance.deinit();

    const allocator = arena_instance.allocator();

    var argiterator = std.process.argsWithAllocator(allocator) catch |err| {
        std.debug.print("{s}", .{Driver.errorDescription(err)});

        return 1;
    };

    var driver = Driver.init(allocator);

    return driver.run(&argiterator);
}
