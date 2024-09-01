const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("string_split"), try Code.Value.NativeFunction.init(vm.allocator, 2, &stringSplit));
    try vm.globals.put(try Atom.new("string_upper"), try Code.Value.NativeFunction.init(vm.allocator, 1, &stringUpper));
    try vm.globals.put(try Atom.new("string_lower"), try Code.Value.NativeFunction.init(vm.allocator, 1, &stringLower));
}

fn stringSplit(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .string) {
        return .none;
    }

    if (arguments[1] != .string) {
        return .none;
    }

    const string = arguments[0].string.content;
    const delimiter = arguments[1].string.content;

    var new_strings = std.ArrayList([]const u8).init(vm.allocator);

    if (delimiter.len == 0) {
        for (0..string.len) |i| {
            new_strings.append(string[i .. i + 1]) catch return .none;
        }
    } else {
        var new_string_iterator = std.mem.splitSequence(u8, string, delimiter);

        while (new_string_iterator.next()) |new_string| {
            new_strings.append(new_string) catch return .none;
        }
    }

    return Code.Value.Array.fromStringSlices(vm.allocator, new_strings.items) catch .none;
}

fn stringUpper(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .string) {
        return .none;
    }

    const string = arguments[0].string;
    var new_string = std.ArrayList(u8).init(vm.allocator);

    for (0..string.content.len) |i| {
        const char = string.content[i];
        const new_char = std.ascii.toUpper(char);
        new_string.append(new_char) catch new_string.append(new_char) catch continue;
    }

    return Code.Value{ .string = .{ .content = new_string.items } };
}

fn stringLower(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .string) {
        return .none;
    }

    const string = arguments[0].string;
    var new_string = std.ArrayList(u8).init(vm.allocator);

    for (0..string.content.len) |i| {
        const char = string.content[i];
        const new_char = std.ascii.toLower(char);
        new_string.append(new_char) catch new_string.append(new_char) catch continue;
    }

    return Code.Value{ .string = .{ .content = new_string.items } };
}
