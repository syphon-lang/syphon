const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("map_keys"), Code.Value.Object.NativeFunction.init(1, &map_keys));
    try vm.globals.put(try Atom.new("map_from_keys"), Code.Value.Object.NativeFunction.init(1, &map_from_keys));
    try vm.globals.put(try Atom.new("map_values"), Code.Value.Object.NativeFunction.init(1, &map_values));
    try vm.globals.put(try Atom.new("map_foreach"), Code.Value.Object.NativeFunction.init(2, &map_foreach));
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

fn map_from_keys(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .array)) {
        return Code.Value{ .none = {} };
    }

    const keys = arguments[0].object.array;

    var inner = Code.Value.Object.Map.Inner.init(vm.allocator);

    for (keys.values.items) |key| {
        const value = Code.Value{ .none = {} };

        inner.put(key, value) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };
    }

    const map = Code.Value.Object.Map.init(vm.allocator, inner) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return map;
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

fn map_foreach(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .map)) {
        return Code.Value{ .none = {} };
    }

    if (!(arguments[1] == .object and arguments[1].object == .function)) {
        return Code.Value{ .none = {} };
    }

    const map = arguments[0].object.map;
    const callback = arguments[1].object.function;

    var map_entry_iterator = map.inner.iterator();

    while (map_entry_iterator.next()) |map_entry| {
        vm.stack.append(map_entry.key_ptr.*) catch unreachable;
        vm.stack.append(map_entry.value_ptr.*) catch unreachable;

        const frame = &vm.frames.items[vm.frames.items.len - 1];

        const previous_frames_start = vm.frames_start;
        vm.frames_start = vm.frames.items.len;

        vm.callUserFunction(callback, frame) catch unreachable;

        vm.run() catch unreachable;

        vm.frames_start = previous_frames_start;

        _ = vm.stack.pop();
    }

    return Code.Value{ .none = {} };
}
