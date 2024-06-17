const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("time", Code.Value.Object.NativeFunction.init(0, &time));
}

pub fn time(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = arguments;

    const now_time = std.time.Instant.now() catch |err| switch (err) {
        error.Unsupported => unreachable,
    };

    const elapsed_time = now_time.since(vm.start_time);

    return Code.Value{ .int = @intCast(elapsed_time) };
}
