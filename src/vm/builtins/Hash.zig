const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("hash"), Code.Value.Object.NativeFunction.init(1, &hash));
}

fn hash(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    if (!Code.Value.HashContext.hashable(value)) {
        return Code.Value{ .none = {} };
    }

    const hash_context = Code.Value.HashContext{};

    return Code.Value{ .int = @bitCast(hash_context.hash(value)) };
}
