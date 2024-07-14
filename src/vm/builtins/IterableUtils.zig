const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("foreach"), Code.Value.Object.NativeFunction.init(2, &foreach));
    try vm.globals.put(try Atom.new("length"), Code.Value.Object.NativeFunction.init(1, &length));
    try vm.globals.put(try Atom.new("contains"), Code.Value.Object.NativeFunction.init(2, &contains));
}

fn foreach(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[1] == .object and arguments[1].object == .function)) {
        return Code.Value{ .none = {} };
    }

    const iterable = arguments[0];

    const callback = arguments[1].object.function;

    switch (iterable) {
        .object => switch (iterable.object) {
            .array => {
                const array = arguments[0].object.array;

                for (0..array.values.items.len) |i| {
                    _ = callback.call(vm, array.values.items[i .. i + 1]);
                }
            },

            .map => {
                const map = arguments[0].object.map;

                var map_entry_iterator = map.inner.iterator();

                while (map_entry_iterator.next()) |map_entry| {
                    _ = callback.call(vm, &.{ map_entry.key_ptr.*, map_entry.value_ptr.* });
                }
            },

            .string => {
                const string = arguments[0].object.string;

                for (0..string.content.len) |i| {
                    _ = callback.call(vm, &.{.{ .object = .{ .string = .{ .content = string.content[i .. i + 1] } } }});
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
