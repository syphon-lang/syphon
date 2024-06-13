const std = @import("std");

const Time = @import("Time.zig");
const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("random", .{ .object = .{ .native_function = .{ .name = "random", .required_arguments_count = 2, .call = &random } } });
}

fn random(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Type = @import("Type.zig");

    var min = Type.to_float(vm, &.{arguments[0]});
    var max = Type.to_float(vm, &.{arguments[1]});

    if (min == .none or max == .none) {
        return Code.Value{ .none = {} };
    }

    if (min.float > max.float) {
        std.mem.swap(Code.Value, &min, &max);
    }

    const RandGen = std.Random.DefaultPrng;

    var rnd = RandGen.init(@intCast(Time.time(vm, &.{}).int));

    return Code.Value{ .float = std.math.lerp(min.float, max.float, rnd.random().float(f64)) };
}
