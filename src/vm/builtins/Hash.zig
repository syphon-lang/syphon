const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("hash", .{ .object = .{ .native_function = .{ .name = "hash", .required_arguments_count = 1, .call = &hash } } });
}

pub fn hash(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = vm;

    const value = arguments[0];

    if (!VirtualMachine.Code.Value.HashContext.hashable(value)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const hash_context = VirtualMachine.Code.Value.HashContext{};

    @setRuntimeSafety(false);

    return VirtualMachine.Code.Value{ .int = @intCast(hash_context.hash(value)) };
}
