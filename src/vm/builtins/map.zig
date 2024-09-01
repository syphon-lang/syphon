const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("map_keys"), Code.Value.Object.NativeFunction.init(1, &mapKeys));
    try vm.globals.put(try Atom.new("map_from_keys"), Code.Value.Object.NativeFunction.init(1, &mapFromKeys));
    try vm.globals.put(try Atom.new("map_values"), Code.Value.Object.NativeFunction.init(1, &mapValues));
}

fn mapKeys(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .map)) {
        return .none;
    }

    const map = arguments[0].object.map;

    var keys = std.ArrayList(Code.Value).initCapacity(vm.allocator, map.inner.count()) catch |err| switch (err) {
        else => {
            return .none;
        },
    };

    for (map.inner.keys()) |map_key| {
        keys.appendAssumeCapacity(map_key);
    }

    return Code.Value.Object.Array.init(vm.allocator, keys) catch |err| switch (err) {
        else => {
            return .none;
        },
    };
}

fn mapFromKeys(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .array)) {
        return .none;
    }

    const keys = arguments[0].object.array;

    var inner = Code.Value.Object.Map.Inner.init(vm.allocator);

    for (keys.inner.items) |key| {
        const value = .none;

        inner.put(key, value) catch return .none;
    }

    const map = Code.Value.Object.Map.init(vm.allocator, inner) catch return .none;

    return map;
}

fn mapValues(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .map)) {
        return .none;
    }

    const map = arguments[0].object.map;

    var values = std.ArrayList(Code.Value).initCapacity(vm.allocator, map.inner.count()) catch |err| switch (err) {
        else => {
            return .none;
        },
    };

    for (map.inner.values()) |map_value| {
        values.appendAssumeCapacity(map_value);
    }

    return Code.Value.Object.Array.init(vm.allocator, values) catch |err| switch (err) {
        else => {
            return .none;
        },
    };
}
