const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("pi", .{ .float = std.math.pi });
    try exports.put("e", .{ .float = std.math.e });
    try exports.put("phi", .{ .float = std.math.phi });
    try exports.put("tau", .{ .float = std.math.tau });

    try exports.put("sqrt", try Code.Value.NativeFunction.init(vm.allocator, 1, &sqrt));
    try exports.put("sin", try Code.Value.NativeFunction.init(vm.allocator, 1, &sin));
    try exports.put("cos", try Code.Value.NativeFunction.init(vm.allocator, 1, &cos));
    try exports.put("tan", try Code.Value.NativeFunction.init(vm.allocator, 1, &tan));
    try exports.put("abs", try Code.Value.NativeFunction.init(vm.allocator, 1, &abs));

    return Code.Value.Map.fromStringHashMap(vm.allocator, exports);
}

fn sqrt(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const cast = @import("cast.zig");

    const value = cast.toFloat(vm, arguments);

    return Code.Value{ .float = @sqrt(value.float) };
}

fn sin(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const cast = @import("cast.zig");

    const value = cast.toFloat(vm, arguments);

    return Code.Value{ .float = @sin(value.float) };
}

fn cos(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const cast = @import("cast.zig");

    const value = cast.toFloat(vm, arguments);

    return Code.Value{ .float = @cos(value.float) };
}

fn tan(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const cast = @import("cast.zig");

    const value = cast.toFloat(vm, arguments);

    return Code.Value{ .float = @tan(value.float) };
}

fn abs(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const cast = @import("cast.zig");

    const value = cast.toFloat(vm, arguments);

    return Code.Value{ .float = @abs(value.float) };
}
