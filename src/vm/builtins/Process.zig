const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("exit", .{ .object = .{ .native_function = .{ .name = "exit", .required_arguments_count = 1, .call = &exit } } });
}

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!VirtualMachine.Code.Value {
    var exports = std.StringHashMap(VirtualMachine.Code.Value).init(vm.gpa);

    try exports.put("argv", try VirtualMachine.Code.Value.Object.Array.fromStringSlices(vm.gpa, vm.argv));

    return VirtualMachine.Code.Value.Object.Map.fromStringHashMap(vm.gpa, exports);
}

fn exit(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = vm;

    const status_code = arguments[0];

    switch (status_code) {
        .int => std.process.exit(@intCast(std.math.mod(i64, status_code.int, 256) catch |err| switch (err) {
            else => std.process.exit(1),
        })),

        else => std.process.exit(1),
    }
}
