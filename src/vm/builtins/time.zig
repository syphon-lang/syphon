const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("now", try Code.Value.NativeFunction.init(vm.allocator, 0, &now));
    try exports.put("now_ms", try Code.Value.NativeFunction.init(vm.allocator, 0, &nowMs));
    try exports.put("sleep", try Code.Value.NativeFunction.init(vm.allocator, 1, &sleep));

    return Code.Value.Map.fromStringHashMap(vm.allocator, exports);
}

pub fn now(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = arguments;
    _ = vm;

    return Code.Value{ .int = std.time.timestamp() };
}

pub fn nowMs(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = arguments;
    _ = vm;

    return Code.Value{ .int = std.time.milliTimestamp() };
}

pub fn sleep(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const cast = @import("cast.zig");

    const seconds = cast.toFloat(vm, &.{arguments[0]});

    std.time.sleep(@intFromFloat(seconds.float * std.math.pow(f64, 10.0, 9.0)));

    return .none;
}
