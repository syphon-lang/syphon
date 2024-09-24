const std = @import("std");

const Ast = @import("Ast.zig");
const Code = @import("../vm/Code.zig");

const Optimizer = @This();

allocator: std.mem.Allocator,

code: Code,

stack: std.ArrayList(?Code.Value),

pub const Error = std.mem.Allocator.Error;

pub fn init(allocator: std.mem.Allocator) Optimizer {
    return Optimizer{
        .allocator = allocator,
        .code = .{
            .constants = std.ArrayList(Code.Value).init(allocator),
            .instructions = std.ArrayList(Code.Instruction).init(allocator),
            .source_locations = std.ArrayList(Ast.SourceLoc).init(allocator),
        },
        .stack = std.ArrayList(?Code.Value).init(allocator),
    };
}

pub fn emitConstant(self: *Optimizer, value: Code.Value, source_loc: Ast.SourceLoc) Error!void {
    try self.emitInstruction(.{ .load_constant = try self.code.addConstant(value) }, source_loc);
}

pub fn emitInstruction(self: *Optimizer, instruction: Code.Instruction, source_loc: Ast.SourceLoc) Error!void {
    const optimize_away = switch (instruction) {
        .load_global,
        .load_local,
        .load_upvalue,
        .make_closure,
        => blk: {
            try self.stack.append(null);

            break :blk false;
        },

        .load_subscript => blk: {
            self.stack.shrinkRetainingCapacity(self.stack.items.len - 2);

            try self.stack.append(null);

            break :blk false;
        },

        .store_global,
        .store_local,
        .store_upvalue,
        .jump_if_false,
        .pop,
        => blk: {
            _ = self.stack.pop();

            break :blk false;
        },

        .store_subscript => blk: {
            self.stack.shrinkRetainingCapacity(self.stack.items.len - 3);

            break :blk false;
        },

        .call,
        .make_array,
        => |length| blk: {
            self.stack.shrinkRetainingCapacity(self.stack.items.len - length);

            try self.stack.append(null);

            break :blk false;
        },

        .make_map => |length| blk: {
            self.stack.shrinkRetainingCapacity(self.stack.items.len - (length * 2));

            try self.stack.append(null);

            break :blk false;
        },

        .load_constant => |index| blk: {
            try self.stack.append(self.code.constants.items[index]);

            break :blk false;
        },

        .duplicate => blk: {
            try self.stack.append(self.stack.getLast());

            break :blk false;
        },

        .neg => try self.optimizeNeg(),
        .not => try self.optimizeNot(),

        .add => try self.optimizeAdd(),
        .subtract => try self.optimizeSubtract(),
        .multiply => try self.optimizeMultiply(),
        .divide => try self.optimizeDivide(),
        .exponent => try self.optimizeExponent(),
        .modulo => try self.optimizeModulo(),
        .equals => try self.optimizeEquals(),
        .less_than => try self.optimizeLessThan(),
        .greater_than => try self.optimizeGreaterThan(),

        else => false,
    };

    if (!optimize_away) {
        switch (instruction) {
            .neg,
            .not,
            .add,
            .subtract,
            .multiply,
            .divide,
            .exponent,
            .modulo,
            .equals,
            .greater_than,
            .less_than,
            => try self.stack.append(null),

            else => {},
        }

        try self.code.instructions.append(instruction);
        try self.code.source_locations.append(source_loc);
    }
}

fn popInstruction(self: *Optimizer) Code.Instruction {
    _ = self.code.source_locations.pop();
    return self.code.instructions.pop();
}

fn optimizeNeg(self: *Optimizer) Error!bool {
    const rhs = self.stack.pop() orelse return false;

    const result: Code.Value = switch (rhs) {
        .int => |rhs_value| .{ .int = -rhs_value },

        .float => |rhs_value| .{ .float = -rhs_value },

        .boolean => |rhs_value| .{ .int = -@as(i64, @intCast(@intFromBool(rhs_value))) },

        else => return false,
    };

    self.code.instructions.items[self.code.instructions.items.len - 1] = .{ .load_constant = try self.code.addConstant(result) };

    try self.stack.append(result);

    return true;
}

fn optimizeNot(self: *Optimizer) Error!bool {
    const rhs = self.stack.pop() orelse return false;

    const result: Code.Value = .{ .boolean = !rhs.isTruthy() };

    self.code.instructions.items[self.code.instructions.items.len - 1] = .{ .load_constant = try self.code.addConstant(result) };

    try self.stack.append(result);

    return true;
}

fn getBinaryOperands(self: *Optimizer) ?struct { Code.Value, Code.Value } {
    const rhs = self.stack.pop() orelse {
        _ = self.stack.pop();

        return null;
    };

    const lhs = self.stack.pop() orelse return null;

    return .{ lhs, rhs };
}

fn getBinaryFloatOperands(self: *Optimizer) ?struct { Code.Value, Code.Value } {
    const cast = @import("../vm/builtins/cast.zig");

    const rhs = cast.toFloat(undefined, &.{self.stack.pop() orelse {
        _ = self.stack.pop();

        return null;
    }});

    const lhs = cast.toFloat(undefined, &.{self.stack.pop() orelse return null});

    return .{ lhs, rhs };
}

fn endBinaryOperation(self: *Optimizer, result: Code.Value) Error!bool {
    _ = self.popInstruction();

    self.code.instructions.items[self.code.instructions.items.len - 1] = .{ .load_constant = try self.code.addConstant(result) };

    try self.stack.append(result);

    return true;
}

fn optimizeAdd(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryOperands() orelse return false;

    const maybe_result: ?Code.Value = switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .int = lhs_value + rhs_value },
            .float => |rhs_value| .{ .float = @as(f64, @floatFromInt(lhs_value)) + rhs_value },
            .boolean => |rhs_value| .{ .int = lhs_value + @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .float = lhs_value + @as(f64, @floatFromInt(rhs_value)) },
            .float => |rhs_value| .{ .float = lhs_value + rhs_value },
            .boolean => |rhs_value| .{ .float = lhs_value + @as(f64, @floatFromInt(@intFromBool(rhs_value))) },

            else => null,
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) + rhs_value },
            .float => |rhs_value| .{ .float = @as(f64, @floatFromInt(@intFromBool(lhs_value))) + rhs_value },
            .boolean => |rhs_value| .{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) + @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        else => null,
    };

    return self.endBinaryOperation(maybe_result orelse return false);
}

fn optimizeSubtract(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryOperands() orelse return false;

    const maybe_result: ?Code.Value = switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .int = lhs_value - rhs_value },
            .float => |rhs_value| .{ .float = @as(f64, @floatFromInt(lhs_value)) - rhs_value },
            .boolean => |rhs_value| .{ .int = lhs_value - @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .float = lhs_value - @as(f64, @floatFromInt(rhs_value)) },
            .float => |rhs_value| .{ .float = lhs_value - rhs_value },
            .boolean => |rhs_value| .{ .float = lhs_value - @as(f64, @floatFromInt(@intFromBool(rhs_value))) },

            else => null,
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) - rhs_value },
            .float => |rhs_value| .{ .float = @as(f64, @floatFromInt(@intFromBool(lhs_value))) - rhs_value },
            .boolean => |rhs_value| .{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) - @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        else => null,
    };

    return self.endBinaryOperation(maybe_result orelse return false);
}

fn optimizeMultiply(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryOperands() orelse return false;

    const maybe_result: ?Code.Value = switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .int = lhs_value * rhs_value },
            .float => |rhs_value| .{ .float = @as(f64, @floatFromInt(lhs_value)) * rhs_value },
            .boolean => |rhs_value| .{ .int = lhs_value * @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .float = lhs_value * @as(f64, @floatFromInt(rhs_value)) },
            .float => |rhs_value| .{ .float = lhs_value * rhs_value },
            .boolean => |rhs_value| .{ .float = lhs_value * @as(f64, @floatFromInt(@intFromBool(rhs_value))) },

            else => null,
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) * rhs_value },
            .float => |rhs_value| .{ .float = @as(f64, @floatFromInt(@intFromBool(lhs_value))) * rhs_value },
            .boolean => |rhs_value| .{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) * @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        else => null,
    };

    return self.endBinaryOperation(maybe_result orelse return false);
}

fn optimizeDivide(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryFloatOperands() orelse return false;

    if (!(lhs == .float and rhs == .float)) {
        return false;
    }

    if (rhs.float == 0) {
        return false;
    }

    return self.endBinaryOperation(.{ .float = lhs.float / rhs.float });
}

fn optimizeExponent(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryFloatOperands() orelse return false;

    if (!(lhs == .float and rhs == .float)) {
        return false;
    }

    if (rhs.float == 0) {
        return false;
    }

    return self.endBinaryOperation(.{ .float = std.math.pow(f64, lhs.float, rhs.float) });
}

fn optimizeModulo(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryOperands() orelse return false;

    const maybe_result: ?Code.Value = switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .int = std.math.mod(i64, lhs_value, rhs_value) catch return false },
            .float => |rhs_value| .{ .float = std.math.mod(f64, @as(f64, @floatFromInt(lhs_value)), rhs_value) catch return false },
            .boolean => |rhs_value| .{ .int = std.math.mod(i64, lhs_value, @as(i64, @intCast(@intFromBool(rhs_value)))) catch return false },

            else => null,
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .float = std.math.mod(f64, lhs_value, @as(f64, @floatFromInt(rhs_value))) catch return false },
            .float => |rhs_value| .{ .float = std.math.mod(f64, lhs_value, rhs_value) catch return false },
            .boolean => |rhs_value| .{ .float = std.math.mod(f64, lhs_value, @as(f64, @floatFromInt(@intFromBool(rhs_value)))) catch return false },

            else => null,
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .int = std.math.mod(i64, @as(i64, @intCast(@intFromBool(lhs_value))), rhs_value) catch return false },
            .float => |rhs_value| .{ .float = std.math.mod(f64, @as(f64, @floatFromInt((@intFromBool(lhs_value)))), rhs_value) catch return false },
            .boolean => |rhs_value| .{ .int = std.math.mod(i64, @as(i64, @intCast(@intFromBool(lhs_value))), @as(i64, @intCast(@intFromBool(rhs_value)))) catch return false },

            else => null,
        },

        else => null,
    };

    return self.endBinaryOperation(maybe_result orelse return false);
}

fn optimizeEquals(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryOperands() orelse return false;

    return self.endBinaryOperation(.{ .boolean = lhs.eql(rhs, true) });
}

fn optimizeLessThan(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryOperands() orelse return false;

    const maybe_result: ?Code.Value = switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .boolean = lhs_value < rhs_value },
            .float => |rhs_value| .{ .boolean = @as(f64, @floatFromInt(lhs_value)) < rhs_value },
            .boolean => |rhs_value| .{ .boolean = lhs_value < @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .boolean = lhs_value < @as(f64, @floatFromInt(rhs_value)) },
            .float => |rhs_value| .{ .boolean = lhs_value < rhs_value },
            .boolean => |rhs_value| .{ .boolean = lhs_value < @as(f64, @floatFromInt(@intFromBool(rhs_value))) },

            else => null,
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .boolean = @as(i64, @intCast(@intFromBool(lhs_value))) < rhs_value },
            .float => |rhs_value| .{ .boolean = @as(f64, @floatFromInt(@intFromBool(lhs_value))) < rhs_value },
            .boolean => |rhs_value| .{ .boolean = @as(i64, @intCast(@intFromBool(lhs_value))) < @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        else => null,
    };

    return self.endBinaryOperation(maybe_result orelse return false);
}

fn optimizeGreaterThan(self: *Optimizer) Error!bool {
    const lhs, const rhs = self.getBinaryOperands() orelse return false;

    const maybe_result: ?Code.Value = switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .boolean = lhs_value > rhs_value },
            .float => |rhs_value| .{ .boolean = @as(f64, @floatFromInt(lhs_value)) > rhs_value },
            .boolean => |rhs_value| .{ .boolean = lhs_value > @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .boolean = lhs_value > @as(f64, @floatFromInt(rhs_value)) },
            .float => |rhs_value| .{ .boolean = lhs_value > rhs_value },
            .boolean => |rhs_value| .{ .boolean = lhs_value > @as(f64, @floatFromInt(@intFromBool(rhs_value))) },

            else => null,
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| .{ .boolean = @as(i64, @intCast(@intFromBool(lhs_value))) > rhs_value },
            .float => |rhs_value| .{ .boolean = @as(f64, @floatFromInt(@intFromBool(lhs_value))) > rhs_value },
            .boolean => |rhs_value| .{ .boolean = @as(i64, @intCast(@intFromBool(lhs_value))) > @as(i64, @intCast(@intFromBool(rhs_value))) },

            else => null,
        },

        else => null,
    };

    return self.endBinaryOperation(maybe_result orelse return false);
}
