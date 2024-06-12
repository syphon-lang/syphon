const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("array_push", .{ .object = .{ .native_function = .{ .name = "array_push", .required_arguments_count = 2, .call = &array_push } } });
    try vm.globals.put("array_pop", .{ .object = .{ .native_function = .{ .name = "array_pop", .required_arguments_count = 1, .call = &array_pop } } });
    try vm.globals.put("len", .{ .object = .{ .native_function = .{ .name = "len", .required_arguments_count = 1, .call = &len } } });
}

fn array_push(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .array)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const array = arguments[0].object.array;

    const value = arguments[1];

    array.values.append(value) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory\n", .{});
            std.process.exit(1);
        },
    };

    return VirtualMachine.Code.Value{ .none = {} };
}

fn array_pop(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .array)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const array = arguments[0].object.array;

    return array.values.popOrNull() orelse VirtualMachine.Code.Value{ .none = {} };
}

fn len(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = vm;

    const value = arguments[0];

    switch (value) {
        .object => switch (value.object) {
            .array => return VirtualMachine.Code.Value{ .int = @intCast(value.object.array.values.items.len) },
            .string => return VirtualMachine.Code.Value{ .int = @intCast(value.object.string.content.len) },
            .map => return VirtualMachine.Code.Value{ .int = @intCast(value.object.map.inner.count()) },

            else => {},
        },

        else => {},
    }

    return VirtualMachine.Code.Value{ .none = {} };
}
