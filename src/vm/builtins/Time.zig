const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("time", .{ .object = .{ .native_function = .{ .name = "time", .required_arguments_count = 0, .call = &time } } });
}

pub fn time(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = arguments;

    const now_time = std.time.Instant.now() catch |err| switch (err) {
        error.Unsupported => unreachable,
    };

    const elapsed_time = now_time.since(vm.start_time);

    return VirtualMachine.Code.Value{ .int = @intCast(elapsed_time) };
}