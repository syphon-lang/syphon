const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("print"), try Code.Value.NativeFunction.init(vm.allocator, null, &print));
    try vm.globals.put(try Atom.new("println"), try Code.Value.NativeFunction.init(vm.allocator, null, &println));
}

pub fn printImpl(comptime B: type, buffered_writer: *std.io.BufferedWriter(4096, B), arguments: []const Code.Value, debug: bool) !void {
    for (arguments, 0..) |argument, i| {
        switch (argument) {
            .none => {
                _ = try buffered_writer.write("none");
            },

            .int => try buffered_writer.writer().print("{d}", .{argument.int}),
            .float => try buffered_writer.writer().print("{d}", .{argument.float}),
            .boolean => try buffered_writer.writer().print("{}", .{argument.boolean}),

            .string => {
                if (debug) {
                    try buffered_writer.writer().print("\"{s}\"", .{argument.string.content});
                } else {
                    try buffered_writer.writer().print("{s}", .{argument.string.content});
                }
            },

            .array => {
                _ = try buffered_writer.write("[");

                for (argument.array.inner.items, 0..) |array_value, j| {
                    if (array_value == .array and array_value.array == argument.array) {
                        _ = try buffered_writer.write("[..]");
                    } else {
                        try printImpl(B, buffered_writer, &.{array_value}, true);
                    }

                    if (j < argument.array.inner.items.len - 1) {
                        _ = try buffered_writer.write(", ");
                    }
                }

                _ = try buffered_writer.write("]");
            },

            .map => {
                _ = try buffered_writer.write("{");

                const map = argument.map;

                var j: usize = 0;

                for (map.inner.keys(), map.inner.values()) |map_key, map_value| {
                    try printImpl(B, buffered_writer, &.{map_key}, true);

                    _ = try buffered_writer.write(": ");

                    if (map_value == .map and map_value.map == argument.map) {
                        _ = try buffered_writer.write("{..}");
                    } else {
                        try printImpl(B, buffered_writer, &.{map_value}, true);
                    }

                    if (j < argument.map.inner.count() - 1) {
                        _ = try buffered_writer.write(", ");
                    }

                    j += 1;
                }

                _ = try buffered_writer.write("}");
            },

            .closure, .function => try buffered_writer.writer().print("<function>", .{}),

            .native_function => try buffered_writer.writer().print("<native function>", .{}),
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

    printImpl(std.fs.File.Writer, &buffered_writer, arguments, false) catch return .none;

    buffered_writer.flush() catch return .none;

    return .none;
}

fn println(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const stdout = std.io.getStdOut();
    var buffered_writer = std.io.bufferedWriter(stdout.writer());

    const new_line_value: Code.Value = .{ .string = .{ .content = "\n" } };

    const new_arguments = std.mem.concat(vm.allocator, Code.Value, &.{ arguments, &.{new_line_value} }) catch return .none;

    printImpl(std.fs.File.Writer, &buffered_writer, new_arguments, false) catch return .none;

    buffered_writer.flush() catch return .none;

    return .none;
}
