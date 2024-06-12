const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!VirtualMachine.Code.Value {
    var globals = std.StringHashMap(VirtualMachine.Code.Value).init(vm.gpa);

    try globals.put("pi", .{ .float = std.math.pi });

    return VirtualMachine.Code.Value.Object.Map.fromStringHashMap(vm.gpa, globals);
}
