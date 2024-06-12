const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(gpa: std.mem.Allocator) std.mem.Allocator.Error!VirtualMachine.Code.Value {
    var exports = std.StringHashMap(VirtualMachine.Code.Value).init(gpa);

    try exports.put("pi", .{ .float = std.math.pi });

    return VirtualMachine.Code.Value.Object.Map.fromStringHashMap(gpa, exports);
}
