const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("string_split"), Code.Value.Object.NativeFunction.init(2, &stringSplit));
    try vm.globals.put(try Atom.new("ord"), Code.Value.Object.NativeFunction.init(1, &ord));
    try vm.globals.put(try Atom.new("chr"), Code.Value.Object.NativeFunction.init(1, &chr));
}

fn stringSplit(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    if (!(arguments[1] == .object and arguments[1].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const string = arguments[0].object.string.content;
    const delimiter = arguments[1].object.string.content;

    var new_strings = std.ArrayList([]const u8).init(vm.allocator);

    if (delimiter.len == 0) {
        for (0..string.len) |i| {
            new_strings.append(string[i .. i + 1]) catch |err| switch (err) {
                else => return Code.Value{ .none = {} },
            };
        }
    } else {
        var new_string_iterator = std.mem.splitSequence(u8, string, delimiter);

        while (new_string_iterator.next()) |new_string| {
            new_strings.append(new_string) catch |err| switch (err) {
                else => return Code.Value{ .none = {} },
            };
        }
    }

    return Code.Value.Object.Array.fromStringSlices(vm.allocator, new_strings.items) catch Code.Value{ .none = {} };
}

fn ord(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .string and arguments[0].object.string.content.len == 1)) {
        return Code.Value{ .none = {} };
    }

    return Code.Value{ .int = @intCast(arguments[0].object.string.content[0]) };
}

fn chr(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return Code.Value{ .none = {} };
    }

    const content_on_heap = vm.allocator.alloc(u8, 1) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    content_on_heap[0] = @intCast(arguments[0].int);

    return Code.Value{ .object = .{ .string = .{ .content = content_on_heap } } };
}
