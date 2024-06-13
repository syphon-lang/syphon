const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("typeof", .{ .object = .{ .native_function = .{ .name = "typeof", .required_arguments_count = 1, .call = &typeof } } });
    try vm.globals.put("to_int", .{ .object = .{ .native_function = .{ .name = "to_int", .required_arguments_count = 1, .call = &to_int } } });
    try vm.globals.put("to_float", .{ .object = .{ .native_function = .{ .name = "to_float", .required_arguments_count = 1, .call = &to_float } } });
    try vm.globals.put("to_string", .{ .object = .{ .native_function = .{ .name = "to_string", .required_arguments_count = 1, .call = &to_string } } });
}

fn typeof(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    const result = switch (value) {
        .none => "none",
        .int => "int",
        .float => "float",
        .boolean => "boolean",
        .object => switch (value.object) {
            .string => "string",
            .array => "array",
            .map => "map",
            .function, .native_function => "function",
        },
    };

    return Code.Value{ .object = .{ .string = .{ .content = result } } };
}

fn to_int(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    switch (value) {
        .int => return value,
        .float => return Code.Value{ .int = @intFromFloat(value.float) },
        .boolean => return Code.Value{ .int = @intFromBool(value.boolean) },
        else => return Code.Value{ .none = {} },
    }
}

pub fn to_float(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    switch (value) {
        .float => return value,
        .int => return Code.Value{ .float = @floatFromInt(value.int) },
        .boolean => return Code.Value{ .float = @floatFromInt(@intFromBool(value.boolean)) },
        else => return Code.Value{ .none = {} },
    }
}

fn to_string(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Console = @import("Console.zig");

    var result = std.ArrayList(u8).init(vm.gpa);
    var buffered_writer = std.io.bufferedWriter(result.writer());

    Console._print(std.ArrayList(u8).Writer, &buffered_writer, arguments, false) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    buffered_writer.flush() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const result_owned = result.toOwnedSlice() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .object = .{ .string = .{ .content = result_owned } } };
}
