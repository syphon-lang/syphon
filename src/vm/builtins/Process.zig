const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("exit"), Code.Value.Object.NativeFunction.init(1, &exit));
}

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("argv", try Code.Value.Object.Array.fromStringSlices(vm.allocator, vm.argv));

    const env_map = std.process.getEnvMap(vm.allocator) catch |err| switch (err) {
        else => std.process.EnvMap.init(vm.allocator),
    };

    try exports.put("env", Code.Value.Object.Map.fromEnvMap(vm.allocator, env_map) catch Code.Value{ .none = {} });

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, exports);
}

fn exit(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const status_code = arguments[0];

    switch (status_code) {
        .int => std.process.exit(@intCast(std.math.mod(i64, status_code.int, 256) catch |err| switch (err) {
            else => std.process.exit(1),
        })),

        else => std.process.exit(1),
    }
}
