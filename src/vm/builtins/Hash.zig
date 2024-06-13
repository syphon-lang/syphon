const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("hash", .{ .object = .{ .native_function = .{ .name = "hash", .required_arguments_count = 1, .call = &hash } } });
}

fn hash(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    if (!Code.Value.HashContext.hashable(value)) {
        return Code.Value{ .none = {} };
    }

    const hash_context = Code.Value.HashContext{};

    @setRuntimeSafety(false);

    return Code.Value{ .int = @intCast(hash_context.hash(value)) };
}
