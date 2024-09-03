const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

const RandGen = std.Random.DefaultPrng;
threadlocal var rnd = RandGen.init(0);

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    const time = @import("time.zig");

    rnd = RandGen.init(@bitCast(time.nowMs(vm, &.{}).int));

    try vm.globals.put(try Atom.new("random"), try Code.Value.NativeFunction.init(vm.allocator, 2, &random));
}

fn random(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const cast = @import("cast.zig");

    var min = cast.toFloat(vm, &.{arguments[0]});
    var max = cast.toFloat(vm, &.{arguments[1]});

    if (min == .none or max == .none) {
        return .none;
    }

    if (min.float > max.float) {
        std.mem.swap(Code.Value, &min, &max);
    }

    return Code.Value{ .float = std.math.lerp(min.float, max.float, rnd.random().float(f64)) };
}
