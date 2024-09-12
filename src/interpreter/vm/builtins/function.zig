const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("call"), try Code.Value.NativeFunction.init(vm.allocator, 2, &call));
    try vm.globals.put(try Atom.new("get_parameters"), try Code.Value.NativeFunction.init(vm.allocator, 1, &getParameters));
}

fn getParameters(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .closure) {
        return .none;
    }

    const function = arguments[0].closure;
    var function_arguments = std.ArrayList(Code.Value).initCapacity(vm.allocator, function.function.parameters.len) catch unreachable;

    for (function.function.parameters) |arg| {
        function_arguments.append(.{ .string = .{ .content = arg.toName() } }) catch unreachable;
    }

    return Code.Value.Array.init(vm.allocator, function_arguments) catch .none;
}

fn call(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .closure or arguments[1] != .array) {
        return .none;
    }

    const function = arguments[0].closure;
    const function_arguments = arguments[1].array;

    return function.call(vm, function_arguments.inner.items);
}
