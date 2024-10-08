const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("utf8_encode", try Code.Value.NativeFunction.init(vm.allocator, 1, &utf8Encode));
    try exports.put("utf8_decode", try Code.Value.NativeFunction.init(vm.allocator, 1, &utf8Decode));

    return Code.Value.Map.fromStringHashMap(vm.allocator, exports);
}

fn utf8Encode(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return .none;
    }

    const encoded = vm.allocator.alloc(u8, 4) catch return .none;

    const encoded_len = std.unicode.utf8Encode(@intCast(arguments[0].int), encoded) catch return .none;

    return Code.Value{ .string = .{ .content = encoded[0..encoded_len] } };
}

fn utf8Decode(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] != .string) {
        return .none;
    }

    const encoded = arguments[0].string.content;

    const decoded = switch (encoded.len) {
        1 => encoded[0],
        2 => std.unicode.utf8Decode2(encoded[0..2].*) catch return .none,
        3 => std.unicode.utf8Decode3(encoded[0..3].*) catch return .none,
        4 => std.unicode.utf8Decode4(encoded[0..4].*) catch return .none,
        else => return .none,
    };

    return Code.Value{ .int = @intCast(decoded) };
}
