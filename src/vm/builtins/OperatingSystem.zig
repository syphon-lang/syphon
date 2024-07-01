const std = @import("std");
const builtin = @import("builtin");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("name", .{ .object = .{ .string = .{ .content = @tagName(builtin.os.tag) } } });
    try exports.put("arch", .{ .object = .{ .string = .{ .content = comptime getArchName(builtin.cpu.arch) } } });

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, exports);
}

fn getArchName(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .arm, .armeb, .thumb, .thumbeb => "aarch",
        .aarch64, .aarch64_be, .aarch64_32 => "aarch64",
        .bpfel, .bpfeb => "bpf",
        .mips, .mipsel => "mips",
        .mips64, .mips64el => "mips64",
        .powerpc, .powerpcle => "powerpc",
        .powerpc64, .powerpc64le => "powerpc64",
        .amdgcn => "amdgpu",
        .sparc, .sparcel => "sparc",
        else => @tagName(arch),
    };
}
