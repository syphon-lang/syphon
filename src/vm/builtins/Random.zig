const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

const RandGen = std.Random.DefaultPrng;
threadlocal var rnd = RandGen.init(0);

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    const Time = @import("Time.zig");

    rnd = RandGen.init(@bitCast(Time.nowMs(vm, &.{}).int));

    try vm.globals.put(try Atom.new("random"), Code.Value.Object.NativeFunction.init(2, &random));
}

fn random(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Type = @import("Type.zig");

    var min = Type.toFloat(vm, &.{arguments[0]});
    var max = Type.toFloat(vm, &.{arguments[1]});

    if (min == .none or max == .none) {
        return Code.Value{ .none = {} };
    }

    if (min.float > max.float) {
        std.mem.swap(Code.Value, &min, &max);
    }

    return Code.Value{ .float = std.math.lerp(min.float, max.float, rnd.random().float(f64)) };
}
