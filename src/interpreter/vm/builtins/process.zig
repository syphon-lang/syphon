const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("exit"), try Code.Value.NativeFunction.init(vm.allocator, 1, &exit));
}

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("argv", try Code.Value.Array.fromStringSlices(vm.allocator, vm.argv));

    const env_map = std.process.getEnvMap(vm.allocator) catch std.process.EnvMap.init(vm.allocator);

    try exports.put("env", Code.Value.Map.fromEnvMap(vm.allocator, env_map) catch .none);

    return Code.Value.Map.fromStringHashMap(vm.allocator, exports);
}

fn exit(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const status_code = arguments[0];

    switch (status_code) {
        .int => std.process.exit(@intCast(std.math.mod(i64, status_code.int, 256) catch std.process.exit(1))),

        else => std.process.exit(1),
    }
}
