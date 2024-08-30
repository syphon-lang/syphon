const std = @import("std");

const Cli = @import("Cli.zig");
const gc = @import("gc.zig");

pub fn main() u8 {
    const allocator = gc.allocator();

    var arg_iterator = std.process.argsWithAllocator(allocator) catch |err| {
        std.debug.print("{s}\n", .{Cli.errorDescription(err)});

        return 1;
    };

    const cli = Cli.parse(allocator, &arg_iterator) orelse return 1;

    return cli.run();
}
