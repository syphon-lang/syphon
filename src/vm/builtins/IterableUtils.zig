const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("filter"), Code.Value.Object.NativeFunction.init(2, &filter));
    try vm.globals.put(try Atom.new("transform"), Code.Value.Object.NativeFunction.init(2, &transform));
    try vm.globals.put(try Atom.new("foreach"), Code.Value.Object.NativeFunction.init(2, &foreach));
    try vm.globals.put(try Atom.new("length"), Code.Value.Object.NativeFunction.init(1, &length));
    try vm.globals.put(try Atom.new("contains"), Code.Value.Object.NativeFunction.init(2, &contains));
}

fn filter(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[1] == .object and arguments[1].object == .function)) {
        return Code.Value{ .none = {} };
    }

    const iterable = arguments[0];
    const callback = arguments[1].object.function;

    switch (iterable) {
        .object => switch (iterable.object) {
            .array => {
                if (callback.parameters.len != 1) return Code.Value{ .none = {} };

                const array = arguments[0].object.array;
                var new_array = std.ArrayList(Code.Value).init(vm.allocator);

                for (0..array.values.items.len) |i| {
                    const return_value = callback.call(vm, &.{array.values.items[i]});

                    switch (return_value) {
                        .boolean => {
                            if (return_value != .boolean) continue;
                            if (!return_value.boolean) continue;

                            new_array.append(array.values.items[i]) catch return Code.Value{ .none = {} };
                        },

                        else => {},
                    }
                }

                return Code.Value.Object.Array.init(vm.allocator, new_array) catch Code.Value{ .none = {} };
            },

            .string => {
                if (callback.parameters.len != 1) return Code.Value{ .none = {} };

                const string = arguments[0].object.string;
                var new_string = std.ArrayList(u8).init(vm.allocator);

                for (0..string.content.len) |i| {
                    const return_value = callback.call(vm, &.{.{ .object = .{ .string = .{ .content = string.content[i .. i + 1] } } }});

                    switch (return_value) {
                        .boolean => {
                            if (return_value != .boolean) continue;
                            if (!return_value.boolean) continue;

                            new_string.append(string.content[i]) catch return Code.Value{ .none = {} };
                        },

                        else => {},
                    }
                }

                return Code.Value{ .object = .{ .string = .{ .content = new_string.items } } };
            },

            .map => {
                if (callback.parameters.len != 2) return Code.Value{ .none = {} };

                const map = arguments[0].object.map;
                var new_map = Code.Value.Object.Map.Inner.init(vm.allocator);

                var map_entry_iterator = map.inner.iterator();

                while (map_entry_iterator.next()) |map_entry| {
                    const return_value = callback.call(vm, &.{ map_entry.key_ptr.*, map_entry.value_ptr.* });

                    switch (return_value) {
                        .boolean => {
                            if (return_value != .boolean) continue;
                            if (!return_value.boolean) continue;

                            new_map.put(map_entry.key_ptr.*, map_entry.value_ptr.*) catch return Code.Value{ .none = {} };
                        },

                        else => {},
                    }
                }

                return Code.Value.Object.Map.init(vm.allocator, new_map) catch Code.Value{ .none = {} };
            },

            else => {},
        },

        else => {},
    }
    return Code.Value{ .none = {} };
}

fn transform(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[1] == .object and arguments[1].object == .function)) {
        return Code.Value{ .none = {} };
    }

    const iterable = arguments[0];
    const callback = arguments[1].object.function;

    switch (iterable) {
        .object => switch (iterable.object) {
            .array => {
                if (callback.parameters.len != 1) return Code.Value{ .none = {} };

                const array = arguments[0].object.array;
                var new_array = std.ArrayList(Code.Value).init(vm.allocator);

                for (0..array.values.items.len) |i| {
                    const return_value = callback.call(vm, &.{array.values.items[i]});

                    new_array.append(return_value) catch return Code.Value{ .none = {} };
                }

                return Code.Value.Object.Array.init(vm.allocator, new_array) catch Code.Value{ .none = {} };
            },

            .string => {
                if (callback.parameters.len != 1) return Code.Value{ .none = {} };

                const string = arguments[0].object.string;
                var new_string = std.ArrayList(u8).init(vm.allocator);

                for (0..string.content.len) |i| {
                    const return_value = callback.call(vm, &.{.{ .object = .{ .string = .{ .content = string.content[i .. i + 1] } } }});

                    if ((return_value == .object and return_value.object == .string)) {
                        new_string.appendSlice(return_value.object.string.content) catch return Code.Value{ .none = {} };
                    } else {
                        new_string.append(string.content[i]) catch return Code.Value{ .none = {} };
                    }
                }

                return Code.Value{ .object = .{ .string = .{ .content = new_string.items } } };
            },

            .map => {
                if (callback.parameters.len != 2) return Code.Value{ .none = {} };

                const map = arguments[0].object.map;
                var new_map = Code.Value.Object.Map.Inner.init(vm.allocator);

                var map_entry_iterator = map.inner.iterator();

                while (map_entry_iterator.next()) |map_entry| {
                    var new_map_entry: []const Code.Value = &.{ map_entry.key_ptr.*, map_entry.value_ptr.* };

                    const return_value = callback.call(vm, new_map_entry);

                    if ((return_value == .object and return_value.object == .array) and (return_value.object.array.values.items.len == 2)) {
                        new_map_entry = return_value.object.array.values.items;
                    }

                    new_map.put(new_map_entry[0], new_map_entry[1]) catch return Code.Value{ .none = {} };
                }

                return Code.Value.Object.Map.init(vm.allocator, new_map) catch Code.Value{ .none = {} };
            },

            else => {},
        },

        else => {},
    }

    return Code.Value{ .none = {} };
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
                if (callback.parameters.len != 1) return Code.Value{ .none = {} };

                const array = arguments[0].object.array;

                for (0..array.values.items.len) |i| {
                    _ = callback.call(vm, array.values.items[i .. i + 1]);
                }
            },

            .string => {
                if (callback.parameters.len != 1) return Code.Value{ .none = {} };

                const string = arguments[0].object.string;

                for (0..string.content.len) |i| {
                    _ = callback.call(vm, &.{.{ .object = .{ .string = .{ .content = string.content[i .. i + 1] } } }});
                }
            },

            .map => {
                if (callback.parameters.len != 2) {
                    return Code.Value{ .none = {} };
                }

                const map = arguments[0].object.map;

                var map_entry_iterator = map.inner.iterator();

                while (map_entry_iterator.next()) |map_entry| {
                    _ = callback.call(vm, &.{ map_entry.key_ptr.*, map_entry.value_ptr.* });
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
            .array => return Code.Value{ .int = @intCast(value.object.array.values.items.len) },
            .string => return Code.Value{ .int = @intCast(value.object.string.content.len) },
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
