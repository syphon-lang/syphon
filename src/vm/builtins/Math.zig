const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.gpa);

    try exports.put("pi", .{ .float = std.math.pi });
    try exports.put("e", .{ .float = std.math.e });
    try exports.put("phi", .{ .float = std.math.phi });
    try exports.put("tau", .{ .float = std.math.tau });

    try exports.put("sqrt", Code.Value.Object.NativeFunction.init(1, &sqrt));
    try exports.put("sin", Code.Value.Object.NativeFunction.init(1, &sin));
    try exports.put("cos", Code.Value.Object.NativeFunction.init(1, &cos));
    try exports.put("tan", Code.Value.Object.NativeFunction.init(1, &tan));

    return Code.Value.Object.Map.fromStringHashMap(vm.gpa, exports);
}

fn sqrt(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Type = @import("Type.zig");

    const value = Type.toFloat(vm, arguments);

    return Code.Value{ .float = @sqrt(value.float) };
}

fn sin(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Type = @import("Type.zig");

    const value = Type.toFloat(vm, arguments);

    return Code.Value{ .float = @sin(value.float) };
}

fn cos(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Type = @import("Type.zig");

    const value = Type.toFloat(vm, arguments);

    return Code.Value{ .float = @cos(value.float) };
}

fn tan(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Type = @import("Type.zig");

    const value = Type.toFloat(vm, arguments);

    return Code.Value{ .float = @tan(value.float) };
}
