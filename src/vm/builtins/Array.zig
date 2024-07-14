const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("array_push"), Code.Value.Object.NativeFunction.init(2, &arrayPush));
    try vm.globals.put(try Atom.new("array_pop"), Code.Value.Object.NativeFunction.init(1, &arrayPop));
    try vm.globals.put(try Atom.new("array_reverse"), Code.Value.Object.NativeFunction.init(1, &arrayReverse));
    try vm.globals.put(try Atom.new("foreach"), Code.Value.Object.NativeFunction.init(2, &foreach));
    try vm.globals.put(try Atom.new("length"), Code.Value.Object.NativeFunction.init(1, &length));
    try vm.globals.put(try Atom.new("contains"), Code.Value.Object.NativeFunction.init(2, &contains));
}

fn arrayPush(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
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

fn arrayPop(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .array)) {
        return Code.Value{ .none = {} };
    }

    const array = arguments[0].object.array;

    return array.values.popOrNull() orelse Code.Value{ .none = {} };
}

fn arrayReverse(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
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

fn foreach(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[1] == .object and arguments[1].object == .function)) {
        return Code.Value{ .none = {} };
    }

    const callback = arguments[1].object.function;
    const iterable = arguments[0];

    switch (iterable) {
        .object => switch (iterable.object) {
            .array => {
                const array = arguments[0].object.array;

                for (0..array.values.items.len) |i| {
                    const args = [1]Code.Value{array.values.items[i]};
                    _ = callback.call(vm, &args);
                }
            },

            .map => {
                const map = arguments[0].object.map;
                var map_iter = map.inner.iterator();

                while (map_iter.next()) |entry| {
                    const args = [2]Code.Value{ entry.key_ptr.*, entry.value_ptr.* };
                    _ = callback.call(vm, &args);
                }
            },

            .string => {
                const str = arguments[0].object.string;
                for (0..str.content.len) |i| {
                    const char = str.content[i];
                    const args = [1]Code.Value{.{ .object = .{ .string = .{ .content = &[1]u8{char} } } }};
                    _ = callback.call(vm, &args);
                }
            },

            else => {},
        },

        else => {},
    }

    return Code.Value{ .none = {} };
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

            .map => {
                return Code.Value{ .boolean = target.object.map.inner.contains(value) };
            },

            else => {},
        },

        else => {},
    }

    return Code.Value{ .none = {} };
}
