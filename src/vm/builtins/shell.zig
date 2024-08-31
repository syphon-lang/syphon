const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("run", Code.Value.Object.NativeFunction.init(1, &run));

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, exports);
}

fn run(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return .none;
    }

    var argv = std.ArrayList([]const u8).init(vm.allocator);

    var arg_iterator = std.mem.splitAny(u8, arguments[0].object.string.content, " ");

    while (arg_iterator.next()) |arg| {
        argv.append(arg) catch return .none;
    }

    const raw_result = std.process.Child.run(.{
        .allocator = vm.allocator,
        .argv = argv.items,
    }) catch return .none;

    var result = std.StringHashMap(Code.Value).init(vm.allocator);

    switch (raw_result.term) {
        .Exited => {
            result.put("termination", .{ .object = .{ .string = .{ .content = "exited" } } }) catch return .none;

            result.put("status_code", .{ .int = @intCast(raw_result.term.Exited) }) catch return .none;
        },

        .Signal => {
            result.put("termination", .{ .object = .{ .string = .{ .content = "signal" } } }) catch return .none;

            result.put("status_code", .{ .int = @intCast(raw_result.term.Signal) }) catch return .none;
        },

        .Stopped => {
            result.put("termination", .{ .object = .{ .string = .{ .content = "stopped" } } }) catch return .none;

            result.put("status_code", .{ .int = @intCast(raw_result.term.Stopped) }) catch return .none;
        },

        .Unknown => {
            result.put("termination", .{ .object = .{ .string = .{ .content = "unknown" } } }) catch return .none;

            result.put("status_code", .{ .int = @intCast(raw_result.term.Unknown) }) catch return .none;
        },
    }

    result.put("stdout", .{ .object = .{ .string = .{ .content = raw_result.stdout } } }) catch return .none;

    result.put("stderr", .{ .object = .{ .string = .{ .content = raw_result.stdout } } }) catch return .none;

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, result) catch .none;
}
