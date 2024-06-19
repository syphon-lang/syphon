const std = @import("std");
const builtin = @import("builtin");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.gpa);

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    if (builtin.os.tag == .windows) {
        try exports.put("stdin", .{ .int = @bitCast(@as(u64, @intFromPtr(stdin.handle))) });
        try exports.put("stdout", .{ .int = @bitCast(@as(u64, @intFromPtr(stdout.handle))) });
        try exports.put("stderr", .{ .int = @bitCast(@as(u64, @intFromPtr(stderr.handle))) });
    } else {
        try exports.put("stdin", .{ .int = @intCast(stdin.handle) });
        try exports.put("stdout", .{ .int = @intCast(stdout.handle) });
        try exports.put("stderr", .{ .int = @intCast(stderr.handle) });
    }

    return Code.Value.Object.Map.fromStringHashMap(vm.gpa, exports);
}
