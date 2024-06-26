const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("map_keys", Code.Value.Object.NativeFunction.init(1, &map_keys));
    try vm.globals.put("map_values", Code.Value.Object.NativeFunction.init(1, &map_values));
}

fn map_keys(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .map)) {
        return Code.Value{ .none = {} };
    }

    const map = arguments[0].object.map;

    var keys = std.ArrayList(Code.Value).initCapacity(vm.allocator, map.inner.count()) catch |err| switch (err) {
        else => {
            return Code.Value{ .none = {} };
        },
    };

    var inner_key_iterator = map.inner.keyIterator();

    while (inner_key_iterator.next()) |inner_key| {
        keys.appendAssumeCapacity(inner_key.*);
    }

    return Code.Value.Object.Array.init(vm.allocator, keys) catch |err| switch (err) {
        else => {
            return Code.Value{ .none = {} };
        },
    };
}

fn map_values(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .map)) {
        return Code.Value{ .none = {} };
    }

    const map = arguments[0].object.map;

    var values = std.ArrayList(Code.Value).initCapacity(vm.allocator, map.inner.count()) catch |err| switch (err) {
        else => {
            return Code.Value{ .none = {} };
        },
    };

    var inner_value_iterator = map.inner.valueIterator();

    while (inner_value_iterator.next()) |inner_value| {
        values.appendAssumeCapacity(inner_value.*);
    }

    return Code.Value.Object.Array.init(vm.allocator, values) catch |err| switch (err) {
        else => {
            return Code.Value{ .none = {} };
        },
    };
}
