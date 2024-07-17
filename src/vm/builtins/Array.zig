const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("array_push"), Code.Value.Object.NativeFunction.init(2, &arrayPush));
    try vm.globals.put(try Atom.new("array_pop"), Code.Value.Object.NativeFunction.init(1, &arrayPop));
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
