const std = @import("std");

const Time = @import("Time.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("random", .{ .object = .{ .native_function = .{ .name = "random", .required_arguments_count = 2, .call = &random } } });
}

fn random(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    var min = arguments[0];
    var max = arguments[1];

    if ((min != .int and min != .float) or (max != .int and max != .float)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    switch (min) {
        .int => switch (max) {
            .int => {
                if (min.int > max.int) {
                    std.mem.swap(VirtualMachine.Code.Value, &min, &max);
                } else if (min.int == max.int) {
                    return VirtualMachine.Code.Value{ .float = @floatFromInt(min.int) };
                }
            },

            .float => {
                if (@as(f64, @floatFromInt(min.int)) > max.float) {
                    std.mem.swap(VirtualMachine.Code.Value, &min, &max);
                } else if (@as(f64, @floatFromInt(min.int)) == max.float) {
                    return max;
                }
            },

            else => unreachable,
        },

        .float => switch (max) {
            .int => {
                if (min.float > @as(f64, @floatFromInt(max.int))) {
                    std.mem.swap(VirtualMachine.Code.Value, &min, &max);
                } else if (min.float == @as(f64, @floatFromInt(max.int))) {
                    return min;
                }
            },

            .float => {
                if (min.float > max.float) {
                    std.mem.swap(VirtualMachine.Code.Value, &min, &max);
                } else if (min.float > max.float) {
                    return min;
                }
            },

            else => unreachable,
        },

        else => unreachable,
    }

    const RandGen = std.Random.DefaultPrng;
    var rnd = RandGen.init(@intCast(Time.time(vm, &.{}).int));

    switch (min) {
        .int => switch (max) {
            .int => return VirtualMachine.Code.Value{ .float = std.math.lerp(@as(f64, @floatFromInt(min.int)), @as(f64, @floatFromInt(max.int)), rnd.random().float(f64)) },

            .float => return VirtualMachine.Code.Value{ .float = std.math.lerp(@as(f64, @floatFromInt(min.int)), max.float, rnd.random().float(f64)) },

            else => unreachable,
        },

        .float => switch (max) {
            .int => return VirtualMachine.Code.Value{ .float = std.math.lerp(min.float, @as(f64, @floatFromInt(max.int)), rnd.random().float(f64)) },

            .float => return VirtualMachine.Code.Value{ .float = std.math.lerp(min.float, max.float, rnd.random().float(f64)) },

            else => unreachable,
        },

        else => unreachable,
    }
}
