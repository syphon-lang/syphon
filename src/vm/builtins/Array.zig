const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("array_push"), Code.Value.Object.NativeFunction.init(2, &array_push));
    try vm.globals.put(try Atom.new("array_pop"), Code.Value.Object.NativeFunction.init(1, &array_pop));
    try vm.globals.put(try Atom.new("array_reverse"), Code.Value.Object.NativeFunction.init(1, &array_reverse));
    try vm.globals.put(try Atom.new("length"), Code.Value.Object.NativeFunction.init(1, &length));
    try vm.globals.put(try Atom.new("contains"), Code.Value.Object.NativeFunction.init(2, &contains));
}

fn array_push(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .array)) {
        return Code.Value{ .none = {} };
    }

    const array = arguments[0].object.array;

    const value = arguments[1];

    array.values.append(value) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .none = {} };
}

fn array_pop(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .array)) {
        return Code.Value{ .none = {} };
    }

    const array = arguments[0].object.array;

    return array.values.popOrNull() orelse Code.Value{ .none = {} };
}

fn array_reverse(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .array)) {
        return Code.Value{ .none = {} };
    }

    const array = arguments[0].object.array;

    var new_array = std.ArrayList(Code.Value).initCapacity(vm.allocator, array.values.items.len) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    for (0..array.values.items.len) |i| {
        new_array.appendAssumeCapacity(array.values.items[array.values.items.len - 1 - i]);
    }

    return Code.Value.Object.Array.init(vm.allocator, new_array) catch Code.Value{ .none = {} };
}

fn length(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    switch (value) {
        .object => switch (value.object) {
            .array => return Code.Value{ .int = @bitCast(value.object.array.values.items.len) },
            .string => return Code.Value{ .int = @bitCast(value.object.string.content.len) },
            .map => return Code.Value{ .int = @intCast(value.object.map.inner.count()) },

            else => {},
        },

        else => {},
    }

    return Code.Value{ .none = {} };
}

fn contains(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const target = arguments[0];
    const value = arguments[1];

    switch (target) {
        .object => switch (target.object) {
            .array => {
                for (target.object.array.values.items) |other_value| {
                    if (value.eql(other_value, false)) {
                        return Code.Value{ .boolean = true };
                    }
                }

                return Code.Value{ .boolean = false };
            },

            .string => {
                if (!(value == .object and value.object == .string)) {
                    return Code.Value{ .boolean = false };
                }

                if (value.object.string.content.len > target.object.string.content.len) {
                    return Code.Value{ .boolean = false };
                }

                for (0..target.object.string.content.len) |i| {
                    if (std.mem.startsWith(u8, target.object.string.content[i..], value.object.string.content)) {
                        return Code.Value{ .boolean = true };
                    }
                }

                return Code.Value{ .boolean = false };
            },

            else => {},
        },

        else => {},
    }

    return Code.Value{ .none = {} };
}
