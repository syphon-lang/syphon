const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("print", Code.Value.Object.NativeFunction.init(null, &print));
    try vm.globals.put("println", Code.Value.Object.NativeFunction.init(null, &println));
}

pub fn _print(comptime B: type, buffered_writer: *std.io.BufferedWriter(4096, B), arguments: []const Code.Value, debug: bool) !void {
    for (arguments, 0..) |argument, i| {
        switch (argument) {
            .none => {
                _ = try buffered_writer.write("none");
            },

            .int => try buffered_writer.writer().print("{d}", .{argument.int}),
            .float => try buffered_writer.writer().print("{d}", .{argument.float}),
            .boolean => try buffered_writer.writer().print("{}", .{argument.boolean}),

            .object => switch (argument.object) {
                .string => {
                    if (debug) {
                        try buffered_writer.writer().print("\"{s}\"", .{argument.object.string.content});
                    } else {
                        try buffered_writer.writer().print("{s}", .{argument.object.string.content});
                    }
                },

                .array => {
                    _ = try buffered_writer.write("[");

                    for (argument.object.array.values.items, 0..) |value, j| {
                        if (value == .object and value.object == .array and value.object.array == argument.object.array) {
                            _ = try buffered_writer.write("[..]");
                        } else {
                            try _print(B, buffered_writer, &.{value}, true);
                        }

                        if (j < argument.object.array.values.items.len - 1) {
                            _ = try buffered_writer.write(", ");
                        }
                    }

                    _ = try buffered_writer.write("]");
                },

                .map => {
                    _ = try buffered_writer.write("{");

                    var map_iterator = argument.object.map.inner.iterator();

                    var j: usize = 0;

                    while (map_iterator.next()) |entry| {
                        try _print(B, buffered_writer, &.{entry.key_ptr.*}, true);

                        _ = try buffered_writer.write(": ");

                        if (entry.value_ptr.* == .object and entry.value_ptr.object == .map and entry.value_ptr.object.map == argument.object.map) {
                            _ = try buffered_writer.write("{..}");
                        } else {
                            try _print(B, buffered_writer, &.{entry.value_ptr.*}, true);
                        }

                        if (j < argument.object.map.inner.count() - 1) {
                            _ = try buffered_writer.write(", ");
                        }

                        j += 1;
                    }

                    _ = try buffered_writer.write("}");
                },

                .function => try buffered_writer.writer().print("<function>", .{}),

                .native_function => try buffered_writer.writer().print("<native function>", .{}),
            },
        }

        if (i < arguments.len - 1) {
            _ = try buffered_writer.write(" ");
        }
    }
}

fn print(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    const stdout = std.io.getStdOut();
    var buffered_writer = std.io.bufferedWriter(stdout.writer());

    _print(std.fs.File.Writer, &buffered_writer, arguments, false) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    buffered_writer.flush() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .none = {} };
}

fn println(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const stdout = std.io.getStdOut();
    var buffered_writer = std.io.bufferedWriter(stdout.writer());

    const new_line_value: Code.Value = .{ .object = .{ .string = .{ .content = "\n" } } };

    const new_arguments = std.mem.concat(vm.allocator, Code.Value, &.{ arguments, &.{new_line_value} }) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    _print(std.fs.File.Writer, &buffered_writer, new_arguments, false) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    buffered_writer.flush() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .none = {} };
}
