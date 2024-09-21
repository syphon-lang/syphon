const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("call"), try Code.Value.NativeFunction.init(vm.allocator, 2, &call));
    try vm.globals.put(try Atom.new("get_parameters"), try Code.Value.NativeFunction.init(vm.allocator, 1, &getParameters));
}

fn getParameters(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    var parameter_strings = std.ArrayList(Code.Value).init(vm.allocator);

    switch (arguments[0]) {
        .closure => |closure| {
            parameter_strings.ensureTotalCapacity(closure.function.parameters.len) catch return .none;

            for (closure.function.parameters) |parameter| {
                parameter_strings.appendAssumeCapacity(.{ .string = .{ .content = parameter.toName() } });
            }
        },

        .native_function => |native_function| {
            if (native_function.required_arguments_count) |parameters_count| {
                parameter_strings.ensureTotalCapacity(parameters_count) catch return .none;

                for (0..parameters_count) |_| {
                    parameter_strings.appendAssumeCapacity(.{ .string = .{ .content = "<unknown>" } });
                }
            } else {
                return .none;
            }
        },

        else => return .none,
    }

    return Code.Value.Array.init(vm.allocator, parameter_strings) catch .none;
}

fn call(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[1] != .array) {
        return .none;
    }

    const function_arguments = arguments[1].array;

    switch (arguments[0]) {
        .closure => |closure| {
            if (function_arguments.inner.items.len != closure.function.parameters.len) {
                return .none;
            }

            return closure.call(vm, function_arguments.inner.items);
        },

        .native_function => |native_function| {
            if (native_function.required_arguments_count != null and
                function_arguments.inner.items.len != native_function.required_arguments_count.?)
            {
                return .none;
            }

            const function_arguments_with_context = if (native_function.maybe_context) |context|
                std.mem.concat(vm.allocator, Code.Value, &.{ &.{context.*}, function_arguments.inner.items }) catch return .none
            else
                function_arguments.inner.items;

            return native_function.call(vm, function_arguments_with_context);
        },

        else => return .none,
    }
}
