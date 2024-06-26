const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("typeof", Code.Value.Object.NativeFunction.init(1, &typeof));
    try vm.globals.put("to_int", Code.Value.Object.NativeFunction.init(1, &toInt));
    try vm.globals.put("to_float", Code.Value.Object.NativeFunction.init(1, &toFloat));
    try vm.globals.put("to_string", Code.Value.Object.NativeFunction.init(1, &toString));
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

pub fn toInt(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    switch (value) {
        .int => return value,
        .float => return Code.Value{ .int = @intFromFloat(value.float) },
        .boolean => return Code.Value{ .int = @intFromBool(value.boolean) },

        .object => switch (value.object) {
            .string => {
                const parsed_int = std.fmt.parseInt(i64, value.object.string.content, 10) catch {
                    return Code.Value{ .none = {} };
                };

                return Code.Value{ .int = parsed_int };
            },

            else => {},
        },

        else => {},
    }

    return Code.Value{ .none = {} };
}

pub fn toFloat(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const value = arguments[0];

    switch (value) {
        .float => return value,
        .int => return Code.Value{ .float = @floatFromInt(value.int) },
        .boolean => return Code.Value{ .float = @floatFromInt(@intFromBool(value.boolean)) },

        .object => switch (value.object) {
            .string => {
                const parsed_float = std.fmt.parseFloat(f64, value.object.string.content) catch {
                    return Code.Value{ .none = {} };
                };

                return Code.Value{ .float = parsed_float };
            },

            else => {},
        },

        else => {},
    }

    return Code.Value{ .none = {} };
}

pub fn toString(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Console = @import("Console.zig");

    var result = std.ArrayList(u8).init(vm.allocator);
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
