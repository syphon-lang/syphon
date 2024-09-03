const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("array_push"), try Code.Value.NativeFunction.init(vm.allocator, 2, &arrayPush));
    try vm.globals.put(try Atom.new("array_pop"), try Code.Value.NativeFunction.init(vm.allocator, 1, &arrayPop));
}

fn arrayPush(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] != .array) {
        return .none;
    }

    const array = arguments[0].array;

    const value = arguments[1];

    array.inner.append(value) catch return .none;

    return .none;
}

fn arrayPop(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] != .array) {
        return .none;
    }

    const array = arguments[0].array;

    return array.inner.popOrNull() orelse .none;
}
