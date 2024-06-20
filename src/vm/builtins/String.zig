const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("ord", Code.Value.Object.NativeFunction.init(1, &ord));
    try vm.globals.put("chr", Code.Value.Object.NativeFunction.init(1, &chr));
}

fn ord(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .string and arguments[0].object.string.content.len == 1)) {
        return Code.Value{ .none = {} };
    }

    return Code.Value{ .int = @intCast(arguments[0].object.string.content[0]) };
}

fn chr(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] == .int) {
        return Code.Value{ .none = {} };
    }

    return Code.Value{ .object = .{ .string = .{ .content = &.{@intCast(arguments[0].int)} } } };
}
