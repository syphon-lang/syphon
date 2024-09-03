const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("range"), try Code.Value.NativeFunction.init(vm.allocator, null, &range));
    try vm.globals.put(try Atom.new("reverse"), try Code.Value.NativeFunction.init(vm.allocator, 1, &reverse));
    try vm.globals.put(try Atom.new("filter"), try Code.Value.NativeFunction.init(vm.allocator, 2, &filter));
    try vm.globals.put(try Atom.new("transform"), try Code.Value.NativeFunction.init(vm.allocator, 2, &transform));
    try vm.globals.put(try Atom.new("foreach"), try Code.Value.NativeFunction.init(vm.allocator, 2, &foreach));
    try vm.globals.put(try Atom.new("length"), try Code.Value.NativeFunction.init(vm.allocator, 1, &length));
    try vm.globals.put(try Atom.new("contains"), try Code.Value.NativeFunction.init(vm.allocator, 2, &contains));
}

fn range(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const cast = @import("cast.zig");

    if (arguments.len < 1 or arguments.len > 3) {
        return .none;
    }

    var start: i64 = 0;
    var end: i64 = 1;
    var step: i64 = 1;

    switch (arguments.len) {
        1 => {
            const first_argument_casted = cast.toInt(vm, arguments[0..1]);
            if (first_argument_casted == .none) return first_argument_casted;
            end = first_argument_casted.int;
        },

        2 => {
            const first_argument_casted = cast.toInt(vm, arguments[0..1]);
            if (first_argument_casted == .none) return first_argument_casted;
            start = first_argument_casted.int;

            const second_argument_casted = cast.toInt(vm, arguments[1..2]);
            if (second_argument_casted == .none) return second_argument_casted;
            end = second_argument_casted.int;
        },

        3 => {
            const first_argument_casted = cast.toInt(vm, arguments[0..1]);
            if (first_argument_casted == .none) return first_argument_casted;
            start = first_argument_casted.int;

            const second_argument_casted = cast.toInt(vm, arguments[1..2]);
            if (second_argument_casted == .none) return second_argument_casted;
            end = second_argument_casted.int;

            const third_argument_casted = cast.toInt(vm, arguments[2..3]);
            if (third_argument_casted == .none) return third_argument_casted;
            step = third_argument_casted.int;

            if (step == 0) return .none;
        },

        else => unreachable,
    }

    var range_array = std.ArrayList(Code.Value).init(vm.allocator);

    var i: i64 = start;

    while (i < end) : (i += step) {
        range_array.append(Code.Value{ .int = i }) catch return .none;
    }

    return Code.Value.Array.init(vm.allocator, range_array) catch .none;
}

fn reverse(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    switch (arguments[0]) {
        .array => {
            const array = arguments[0].array;

            var new_array = std.ArrayList(Code.Value).initCapacity(vm.allocator, array.inner.items.len) catch return .none;

            var i = array.inner.items.len;
            while (i > 0) {
                i -= 1;
                new_array.append(array.inner.items[i]) catch return .none;
            }
            return Code.Value.Array.init(vm.allocator, new_array) catch .none;
        },

        .string => {
            const string = arguments[0].string;

            var new_string = std.ArrayList(u8).initCapacity(vm.allocator, string.content.len) catch return .none;

            var i = string.content.len;
            while (i > 0) {
                i -= 1;
                new_string.append(string.content[i]) catch return .none;
            }

            return Code.Value{ .string = .{ .content = new_string.items } };
        },

        else => {},
    }

    return .none;
}

fn filter(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[1] != .closure) {
        return .none;
    }

    const iterable = arguments[0];
    const callback = arguments[1].closure;

    switch (iterable) {
        .array => {
            if (callback.function.parameters.len != 1) return .none;

            const array = arguments[0].array;
            var new_array = std.ArrayList(Code.Value).init(vm.allocator);

            for (0..array.inner.items.len) |i| {
                const return_value = callback.call(vm, &.{array.inner.items[i]});

                switch (return_value) {
                    .boolean => {
                        if (return_value != .boolean) continue;
                        if (!return_value.boolean) continue;

                        new_array.append(array.inner.items[i]) catch return .none;
                    },

                    else => {},
                }
            }

            return Code.Value.Array.init(vm.allocator, new_array) catch .none;
        },

        .string => {
            if (callback.function.parameters.len != 1) return .none;

            const string = arguments[0].string;
            var new_string = std.ArrayList(u8).init(vm.allocator);

            for (0..string.content.len) |i| {
                const return_value = callback.call(vm, &.{.{ .string = .{ .content = string.content[i .. i + 1] } }});

                switch (return_value) {
                    .boolean => {
                        if (return_value != .boolean) continue;
                        if (!return_value.boolean) continue;

                        new_string.append(string.content[i]) catch return .none;
                    },

                    else => {},
                }
            }

            return Code.Value{ .string = .{ .content = new_string.items } };
        },

        .map => {
            if (callback.function.parameters.len != 2) return .none;

            const map = arguments[0].map;
            var new_map = Code.Value.Map.Inner.init(vm.allocator);

            var map_entry_iterator = map.inner.iterator();

            while (map_entry_iterator.next()) |map_entry| {
                const return_value = callback.call(vm, &.{ map_entry.key_ptr.*, map_entry.value_ptr.* });

                switch (return_value) {
                    .boolean => {
                        if (return_value != .boolean) continue;
                        if (!return_value.boolean) continue;

                        new_map.put(map_entry.key_ptr.*, map_entry.value_ptr.*) catch return .none;
                    },

                    else => {},
                }
            }

            return Code.Value.Map.init(vm.allocator, new_map) catch .none;
        },

        else => {},
    }

    return .none;
}

fn transform(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[1] != .closure) {
        return .none;
    }

    const iterable = arguments[0];
    const callback = arguments[1].closure;

    switch (iterable) {
        .array => {
            if (callback.function.parameters.len != 1) return .none;

            const array = arguments[0].array;
            var new_array = std.ArrayList(Code.Value).init(vm.allocator);

            for (0..array.inner.items.len) |i| {
                const return_value = callback.call(vm, &.{array.inner.items[i]});

                new_array.append(return_value) catch return .none;
            }

            return Code.Value.Array.init(vm.allocator, new_array) catch .none;
        },

        .string => {
            if (callback.function.parameters.len != 1) return .none;

            const string = arguments[0].string;
            var new_string = std.ArrayList(u8).init(vm.allocator);

            for (0..string.content.len) |i| {
                const return_value = callback.call(vm, &.{.{ .string = .{ .content = string.content[i .. i + 1] } }});

                if (return_value == .string) {
                    new_string.appendSlice(return_value.string.content) catch return .none;
                } else {
                    new_string.append(string.content[i]) catch return .none;
                }
            }

            return Code.Value{ .string = .{ .content = new_string.items } };
        },

        .map => {
            if (callback.function.parameters.len != 2) return .none;

            const map = arguments[0].map;
            var new_map = Code.Value.Map.Inner.init(vm.allocator);

            var map_entry_iterator = map.inner.iterator();

            while (map_entry_iterator.next()) |map_entry| {
                var new_map_entry: []const Code.Value = &.{ map_entry.key_ptr.*, map_entry.value_ptr.* };

                const return_value = callback.call(vm, new_map_entry);

                if (return_value == .array and return_value.array.inner.items.len == 2) {
                    new_map_entry = return_value.array.inner.items;
                }

                new_map.put(new_map_entry[0], new_map_entry[1]) catch return .none;
            }

            return Code.Value.Map.init(vm.allocator, new_map) catch .none;
        },

        else => {},
    }

    return .none;
}

fn foreach(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[1] != .closure) {
        return .none;
    }

    const iterable = arguments[0];
    const callback = arguments[1].closure;

    switch (iterable) {
        .array => {
            if (callback.function.parameters.len != 1) return .none;

            const array = arguments[0].array;

            for (0..array.inner.items.len) |i| {
                _ = callback.call(vm, array.inner.items[i .. i + 1]);
            }
        },

        .string => {
            if (callback.function.parameters.len != 1) return .none;

            const string = arguments[0].string;

            for (0..string.content.len) |i| {
                _ = callback.call(vm, &.{.{ .string = .{ .content = string.content[i .. i + 1] } }});
            }
        },

        .map => {
            if (callback.function.parameters.len != 2) return .none;

            const map = arguments[0].map;

            var map_entry_iterator = map.inner.iterator();

            while (map_entry_iterator.next()) |map_entry| {
                _ = callback.call(vm, &.{ map_entry.key_ptr.*, map_entry.value_ptr.* });
            }
        },

        else => {},
    }

    return .none;
}

fn length(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    switch (value) {
        .array => return Code.Value{ .int = @intCast(value.array.inner.items.len) },
        .string => return Code.Value{ .int = @intCast(value.string.content.len) },
        .map => return Code.Value{ .int = @intCast(value.map.inner.count()) },

        else => {},
    }

    return .none;
}

fn contains(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const target = arguments[0];
    const value = arguments[1];

    switch (target) {
        .array => {
            for (target.array.inner.items) |other_value| {
                if (value.eql(other_value, false)) {
                    return Code.Value{ .boolean = true };
                }
            }

            return Code.Value{ .boolean = false };
        },

        .string => {
            if (value == .string) {
                return Code.Value{ .boolean = false };
            }

            if (value.string.content.len > target.string.content.len) {
                return Code.Value{ .boolean = false };
            }

            for (0..target.string.content.len) |i| {
                if (std.mem.startsWith(u8, target.string.content[i..], value.string.content)) {
                    return Code.Value{ .boolean = true };
                }
            }

            return Code.Value{ .boolean = false };
        },

        .map => {
            return Code.Value{ .boolean = target.map.inner.contains(value) };
        },

        else => {},
    }

    return .none;
}
