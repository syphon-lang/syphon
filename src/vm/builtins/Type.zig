const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("typeof", .{ .object = .{ .native_function = .{ .name = "typeof", .required_arguments_count = 1, .call = &typeof } } });
}

fn typeof(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    const value = arguments[0];

    const typeof_value = switch (value) {
        .none => "none",
        .int => "int",
        .float => "float",
        .boolean => "boolean",
        .object => switch (value.object) {
            .string => "string",
            .array => "array",
            .function, .native_function => "function",
        },
    };

    const typeof_value_interned = vm.gc.intern(typeof_value) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory\n", .{});
            std.process.exit(1);
        },
    };

    return VirtualMachine.Code.Value{ .object = .{ .string = .{ .content = typeof_value_interned } } };
}
