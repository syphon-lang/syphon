const std = @import("std");
const builtin = @import("builtin");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("name", .{ .string = .{ .content = @tagName(builtin.os.tag) } });
    try exports.put("arch", .{ .string = .{ .content = comptime getArchName(builtin.cpu.arch) } });

    return Code.Value.Map.fromStringHashMap(vm.allocator, exports);
}

fn getArchName(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .arm, .armeb, .thumb, .thumbeb => "aarch",
        .aarch64, .aarch64_be => "aarch64",
        .bpfel, .bpfeb => "bpf",
        .mipsel => "mips",
        .mips64el => "mips64",
        .powerpcle => "powerpc",
        .powerpc64le => "powerpc64",
        .amdgcn => "amdgpu",
        else => @tagName(arch),
    };
}
