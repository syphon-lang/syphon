const std = @import("std");

const ast = @import("ast.zig");
const SourceLoc = ast.SourceLoc;
const AutoHashMapRecorder = @import("../ds/hash_map_recorder.zig").AutoHashMapRecorder;
const Code = @import("../vm/Code.zig");
const VirtualMachine = @import("../vm/VirtualMachine.zig");
const Atom = @import("../vm/Atom.zig");

const CodeGen = @This();

allocator: std.mem.Allocator,

code: Code,

locals: AutoHashMapRecorder(Atom, void),

context: Context,

error_info: ?ErrorInfo = null,

pub const Error = error{
    BadOperand,
    UnexpectedBreak,
    UnexpectedContinue,
    UnexpectedReturn,
} || std.mem.Allocator.Error;

pub const ErrorInfo = struct {
    message: []const u8,
    source_loc: SourceLoc,
};

pub const Context = struct {
    mode: Mode,
    compiling_conditional: bool = false,
    compiling_loop: bool = false,
    break_points: std.ArrayList(usize),
    continue_points: std.ArrayList(usize),
    unused_expression: bool = false,

    pub const Mode = enum {
        script,
        function,
    };
};

pub fn init(allocator: std.mem.Allocator, mode: Context.Mode, maybe_locals: ?AutoHashMapRecorder(Atom, void)) std.mem.Allocator.Error!CodeGen {
    return CodeGen{
        .allocator = allocator,
        .code = .{
            .constants = std.ArrayList(Code.Value).init(allocator),
            .instructions = std.ArrayList(Code.Instruction).init(allocator),
            .source_locations = std.ArrayList(SourceLoc).init(allocator),
        },
        .locals = if (maybe_locals) |locals| locals else try AutoHashMapRecorder(Atom, void).initSnapshotsCapacity(allocator, 128),
        .context = .{
            .mode = mode,
            .break_points = std.ArrayList(usize).init(allocator),
            .continue_points = std.ArrayList(usize).init(allocator),
        },
    };
}

pub fn compileRoot(self: *CodeGen, root: ast.Root) Error!void {
    try self.compileNodes(root.body);

    try self.endCode();
}

fn endCode(self: *CodeGen) Error!void {
    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .none = {} }) });

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .@"return" = {} });
}

fn compileNodes(self: *CodeGen, nodes: []const ast.Node) Error!void {
    for (nodes) |node| {
        try self.compileNode(node);
    }
}

fn compileNode(self: *CodeGen, node: ast.Node) Error!void {
    switch (node) {
        .stmt => try self.compileStmt(node.stmt),
        .expr => {
            self.context.unused_expression = true;
            try self.compileExpr(node.expr);
            self.context.unused_expression = false;
        },
    }
}

fn compileStmt(self: *CodeGen, stmt: ast.Node.Stmt) Error!void {
    switch (stmt) {
        .conditional => try self.compileConditionalStmt(stmt.conditional),

        .while_loop => try self.compileWhileLoopStmt(stmt.while_loop),

        .@"break" => try self.compileBreakStmt(stmt.@"break"),

        .@"continue" => try self.compileContinueStmt(stmt.@"continue"),

        .@"return" => try self.compileReturnStmt(stmt.@"return"),
    }
}

fn compileConditionalStmt(self: *CodeGen, conditional: ast.Node.Stmt.Conditional) Error!void {
    const BacktrackPoint = struct {
        condition_point: usize,
        jump_if_false_point: usize,
        jump_point: usize,
    };

    var backtrack_points = std.ArrayList(BacktrackPoint).init(self.allocator);

    const was_compiling_conditional = self.context.compiling_conditional;
    self.context.compiling_conditional = true;

    for (0..conditional.conditions.len) |i| {
        const condition_point = self.code.instructions.items.len;
        try self.compileExpr(conditional.conditions[i]);

        const jump_if_false_point = self.code.instructions.items.len;
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .jump_if_false = 0 });

        try self.compileNodes(conditional.possiblities[i]);

        const jump_point = self.code.instructions.items.len;
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .jump = 0 });

        try backtrack_points.append(.{ .condition_point = condition_point, .jump_if_false_point = jump_if_false_point, .jump_point = jump_point });
    }

    const fallback_point = self.code.instructions.items.len;
    try self.compileNodes(conditional.fallback);
    const after_fallback_point = self.code.instructions.items.len;

    self.context.compiling_conditional = was_compiling_conditional;

    var backtrack_points_iter: usize = 0;

    while ((backtrack_points.items.len - backtrack_points_iter) > 0) {
        const default_backtrack_point: BacktrackPoint = .{ .condition_point = fallback_point, .jump_if_false_point = 0, .jump_point = 0 };

        const current_backtrack_point = backtrack_points.items[backtrack_points_iter];
        backtrack_points_iter += 1;

        const next_backtrack_point = blk: {
            if ((backtrack_points.items.len - backtrack_points_iter) == 0) {
                break :blk default_backtrack_point;
            } else {
                break :blk backtrack_points.items[backtrack_points_iter];
            }
        };

        self.code.instructions.items[current_backtrack_point.jump_if_false_point] = .{ .jump_if_false = next_backtrack_point.condition_point - current_backtrack_point.jump_if_false_point - 1 };

        self.code.instructions.items[current_backtrack_point.jump_point] = .{ .jump = after_fallback_point - current_backtrack_point.jump_point - 1 };
    }
}

fn compileWhileLoopStmt(self: *CodeGen, while_loop: ast.Node.Stmt.WhileLoop) Error!void {
    const condition_point = self.code.instructions.items.len;
    try self.compileExpr(while_loop.condition);

    const jump_if_false_point = self.code.instructions.items.len;
    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .jump_if_false = 0 });

    const was_compiling_loop = self.context.compiling_loop;
    self.context.compiling_loop = true;

    const previous_break_points_len = self.context.break_points.items.len;

    const previous_continue_points_len = self.context.continue_points.items.len;

    try self.compileNodes(while_loop.body);

    self.context.compiling_loop = was_compiling_loop;

    self.code.instructions.items[jump_if_false_point] = .{ .jump_if_false = self.code.instructions.items.len - jump_if_false_point };

    for (self.context.break_points.items[previous_break_points_len..]) |break_point| {
        self.code.instructions.items[break_point] = .{ .jump = self.code.instructions.items.len - break_point };
    }

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .back = self.code.instructions.items.len - condition_point + 1 });

    for (self.context.continue_points.items[previous_continue_points_len..]) |continue_point| {
        self.code.instructions.items[continue_point] = .{ .back = continue_point - condition_point + 1 };
    }

    self.context.break_points.shrinkRetainingCapacity(previous_break_points_len);

    self.context.continue_points.shrinkRetainingCapacity(previous_continue_points_len);
}

fn compileBreakStmt(self: *CodeGen, @"break": ast.Node.Stmt.Break) Error!void {
    if (!self.context.compiling_loop) {
        self.error_info = .{ .message = "break outside a loop", .source_loc = @"break".source_loc };

        return error.UnexpectedBreak;
    }

    try self.context.break_points.append(self.code.instructions.items.len);
    try self.code.source_locations.append(@"break".source_loc);
    try self.code.instructions.append(.{ .jump = 0 });
}

fn compileContinueStmt(self: *CodeGen, @"continue": ast.Node.Stmt.Continue) Error!void {
    if (!self.context.compiling_loop) {
        self.error_info = .{ .message = "continue outside a loop", .source_loc = @"continue".source_loc };

        return error.UnexpectedContinue;
    }

    try self.context.continue_points.append(self.code.instructions.items.len);
    try self.code.source_locations.append(@"continue".source_loc);
    try self.code.instructions.append(.{ .back = 0 });
}

fn compileReturnStmt(self: *CodeGen, @"return": ast.Node.Stmt.Return) Error!void {
    if (self.context.mode != .function) {
        self.error_info = .{ .message = "return outside a function", .source_loc = @"return".source_loc };

        return error.UnexpectedReturn;
    }

    try self.compileExpr(@"return".value);

    try self.code.source_locations.append(@"return".source_loc);
    try self.code.instructions.append(.{ .@"return" = {} });
}

fn compileExpr(self: *CodeGen, expr: ast.Node.Expr) Error!void {
    switch (expr) {
        .identifier => try self.compileIdentifierExpr(expr.identifier),

        .subscript => try self.compileSubscriptExpr(expr.subscript),

        .assignment => try self.compileAssignmentExpr(expr.assignment),

        .call => try self.compileCallExpr(expr.call),

        else => {},
    }

    if (!self.context.unused_expression) {
        switch (expr) {
            .none => try self.compileNoneExpr(expr.none),

            .string => try self.compileStringExpr(expr.string),

            .int => try self.compileIntExpr(expr.int),

            .float => try self.compileFloatExpr(expr.float),

            .boolean => try self.compileBooleanExpr(expr.boolean),

            .array => try self.compileArrayExpr(expr.array),

            .map => try self.compileMapExpr(expr.map),

            .function => try self.compileFunctionExpr(expr.function),

            .unary_operation => try self.compileUnaryOperationExpr(expr.unary_operation),

            .binary_operation => try self.compileBinaryOperationExpr(expr.binary_operation),

            else => {},
        }
    } else {}
}

fn compileNoneExpr(self: *CodeGen, none: ast.Node.Expr.None) Error!void {
    try self.code.source_locations.append(none.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .none = {} }) });
}

fn compileIdentifierExpr(self: *CodeGen, identifier: ast.Node.Expr.Identifier) Error!void {
    try self.code.source_locations.append(identifier.name.source_loc);
    try self.code.instructions.append(.{ .load_atom = try Atom.new(identifier.name.buffer) });

    if (self.context.unused_expression) {
        try self.code.source_locations.append(identifier.name.source_loc);
        try self.code.instructions.append(.{ .pop = {} });
    }
}

fn compileStringExpr(self: *CodeGen, string: ast.Node.Expr.String) Error!void {
    try self.code.source_locations.append(string.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .object = .{ .string = .{ .content = string.content } } }) });
}

fn compileIntExpr(self: *CodeGen, int: ast.Node.Expr.Int) Error!void {
    try self.code.source_locations.append(int.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = int.value }) });
}

fn compileFloatExpr(self: *CodeGen, float: ast.Node.Expr.Float) Error!void {
    try self.code.source_locations.append(float.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = float.value }) });
}

fn compileBooleanExpr(self: *CodeGen, boolean: ast.Node.Expr.Boolean) Error!void {
    try self.code.source_locations.append(boolean.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .boolean = boolean.value }) });
}

fn compileArrayExpr(self: *CodeGen, array: ast.Node.Expr.Array) Error!void {
    for (array.values) |value| {
        try self.compileExpr(value);
    }

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .make_array = array.values.len });
}

fn compileMapExpr(self: *CodeGen, map: ast.Node.Expr.Map) Error!void {
    for (0..map.keys.len) |i| {
        try self.compileExpr(map.keys[i]);
        try self.compileExpr(map.values[i]);
    }

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .make_map = @intCast(map.keys.len) });
}

fn compileFunctionExpr(self: *CodeGen, ast_function: ast.Node.Expr.Function) Error!void {
    var parameters = std.ArrayList(Atom).init(self.allocator);

    for (ast_function.parameters) |ast_parameter| {
        try parameters.append(try Atom.new(ast_parameter.buffer));
    }

    const function: Code.Value.Object.Function = .{
        .parameters = try parameters.toOwnedSlice(),
        .code = blk: {
            self.locals.newSnapshot();

            try self.locals.ensureUnusedCapacity(@intCast(parameters.items.len));

            for (parameters.items) |parameter| {
                try self.locals.put(parameter, {});
            }

            var gen = try init(self.allocator, .function, self.locals);

            try gen.compileNodes(ast_function.body);

            try gen.endCode();

            self.locals.destroySnapshot();

            break :blk gen.code;
        },
    };

    const function_on_heap = try self.allocator.create(Code.Value.Object.Function);
    function_on_heap.* = function;

    try self.code.source_locations.append(ast_function.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .object = .{ .function = function_on_heap } }) });
}

fn compileSubscriptExpr(self: *CodeGen, subscript: ast.Node.Expr.Subscript) Error!void {
    try self.compileExpr(subscript.target.*);
    try self.compileExpr(subscript.index.*);

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .load_subscript = {} });

    if (self.context.unused_expression) {
        try self.code.source_locations.append(subscript.source_loc);
        try self.code.instructions.append(.{ .pop = {} });
    }
}

fn knownAtCompileTime(expr: ast.Node.Expr) bool {
    return switch (expr) {
        .identifier => false,
        .subscript => false,
        .assignment => false,
        .call => false,

        .binary_operation => knownAtCompileTime(expr.binary_operation.lhs.*) and knownAtCompileTime(expr.binary_operation.rhs.*),
        .unary_operation => knownAtCompileTime(expr.unary_operation.rhs.*),

        else => true,
    };
}

fn optimizeUnaryOperation(self: *CodeGen, unary_operation: ast.Node.Expr.UnaryOperation) Error!bool {
    if (!knownAtCompileTime(unary_operation.rhs.*)) return false;

    switch (unary_operation.operator) {
        .minus => return self.optimizeNeg(unary_operation),
        .bang => return self.optimizeNot(unary_operation),
    }
}

fn optimizeNeg(self: *CodeGen, unary_operation: ast.Node.Expr.UnaryOperation) Error!bool {
    // TODO: Optimize for other cases
    switch (unary_operation.rhs.*) {
        .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = -unary_operation.rhs.int.value }) }),

        .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = -unary_operation.rhs.float.value }) }),

        .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = -@as(i64, @intCast(@intFromBool(unary_operation.rhs.boolean.value))) }) }),

        else => return false,
    }

    try self.code.source_locations.append(unary_operation.source_loc);

    return true;
}

fn optimizeNot(self: *CodeGen, unary_operation: ast.Node.Expr.UnaryOperation) Error!bool {
    // TODO: Optimize for other cases
    switch (unary_operation.rhs.*) {
        .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .boolean = unary_operation.rhs.int.value == 0 }) }),

        .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .boolean = unary_operation.rhs.float.value == 0 }) }),

        .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .boolean = !unary_operation.rhs.boolean.value }) }),

        else => return false,
    }

    try self.code.source_locations.append(unary_operation.source_loc);

    return true;
}

fn compileUnaryOperationExpr(self: *CodeGen, unary_operation: ast.Node.Expr.UnaryOperation) Error!void {
    const optimized = try self.optimizeUnaryOperation(unary_operation);

    if (!optimized) {
        try self.compileExpr(unary_operation.rhs.*);

        switch (unary_operation.operator) {
            .minus => {
                try self.code.source_locations.append(unary_operation.source_loc);
                try self.code.instructions.append(.{ .neg = {} });
            },

            .bang => {
                try self.code.source_locations.append(unary_operation.source_loc);
                try self.code.instructions.append(.{ .not = {} });
            },
        }
    }
}

fn optimizeBinaryOperation(self: *CodeGen, binary_operation: ast.Node.Expr.BinaryOperation) Error!bool {
    if (!knownAtCompileTime(binary_operation.lhs.*) or !knownAtCompileTime(binary_operation.rhs.*)) return false;

    // TODO: Optimize for other cases
    switch (binary_operation.operator) {
        .plus => return self.optimizeAdd(binary_operation),
        .minus => return self.optimizeSubtract(binary_operation),
        .forward_slash => return self.optimizeDivide(binary_operation),
        .star => return self.optimizeMultiply(binary_operation),
        .double_star => return self.optimizeExponent(binary_operation),

        else => return false,
    }
}

fn optimizeAdd(self: *CodeGen, binary_operation: ast.Node.Expr.BinaryOperation) Error!bool {
    // TODO: Optimize for other cases
    switch (binary_operation.lhs.*) {
        .int => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = binary_operation.lhs.int.value + binary_operation.rhs.int.value }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(binary_operation.lhs.int.value)) + binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = binary_operation.lhs.int.value + @as(i64, @intFromBool(binary_operation.rhs.boolean.value)) }) }),

            else => return false,
        },

        .float => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = binary_operation.lhs.float.value + @as(f64, @floatFromInt(binary_operation.rhs.int.value)) }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(binary_operation.lhs.int.value)) + binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = binary_operation.lhs.float.value + @as(f64, @floatFromInt(@as(i64, @intFromBool(binary_operation.rhs.boolean.value)))) }) }),

            else => return false,
        },

        .boolean => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = @as(i64, @intFromBool(binary_operation.lhs.boolean.value)) + binary_operation.rhs.int.value }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(@as(i64, @intFromBool(binary_operation.lhs.boolean.value)))) + binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = @as(i64, @intFromBool(binary_operation.lhs.boolean.value)) + @as(i64, @intFromBool(binary_operation.rhs.boolean.value)) }) }),

            else => return false,
        },

        else => return false,
    }

    try self.code.source_locations.append(binary_operation.source_loc);

    return true;
}

fn optimizeSubtract(self: *CodeGen, binary_operation: ast.Node.Expr.BinaryOperation) Error!bool {
    // TODO: Optimize for other cases
    switch (binary_operation.lhs.*) {
        .int => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = binary_operation.lhs.int.value - binary_operation.rhs.int.value }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(binary_operation.lhs.int.value)) - binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = binary_operation.lhs.int.value - @as(i64, @intFromBool(binary_operation.rhs.boolean.value)) }) }),

            else => return false,
        },

        .float => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = binary_operation.lhs.float.value - @as(f64, @floatFromInt(binary_operation.rhs.int.value)) }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(binary_operation.lhs.int.value)) - binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = binary_operation.lhs.float.value - @as(f64, @floatFromInt(@as(i64, @intFromBool(binary_operation.rhs.boolean.value)))) }) }),

            else => return false,
        },

        .boolean => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = @as(i64, @intFromBool(binary_operation.lhs.boolean.value)) - binary_operation.rhs.int.value }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(@as(i64, @intFromBool(binary_operation.lhs.boolean.value)))) - binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = @as(i64, @intFromBool(binary_operation.lhs.boolean.value)) - @as(i64, @intFromBool(binary_operation.rhs.boolean.value)) }) }),

            else => return false,
        },

        else => return false,
    }

    try self.code.source_locations.append(binary_operation.source_loc);

    return true;
}

fn castExprToFloat(expr: ast.Node.Expr) error{CastingFailed}!f64 {
    return switch (expr) {
        .int => @floatFromInt(expr.int.value),

        .float => expr.float.value,

        .boolean => @floatFromInt(@intFromBool(expr.boolean.value)),

        else => error.CastingFailed,
    };
}

fn optimizeDivide(self: *CodeGen, binary_operation: ast.Node.Expr.BinaryOperation) Error!bool {
    // TODO: Optimize for other cases
    const lhs_casted = castExprToFloat(binary_operation.lhs.*) catch return false;
    const rhs_casted = castExprToFloat(binary_operation.rhs.*) catch return false;

    try self.code.source_locations.append(binary_operation.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = lhs_casted / rhs_casted }) });

    return true;
}

fn optimizeMultiply(self: *CodeGen, binary_operation: ast.Node.Expr.BinaryOperation) Error!bool {
    // TODO: Optimize for other cases
    switch (binary_operation.lhs.*) {
        .int => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = binary_operation.lhs.int.value * binary_operation.rhs.int.value }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(binary_operation.lhs.int.value)) * binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = binary_operation.lhs.int.value * @as(i64, @intFromBool(binary_operation.rhs.boolean.value)) }) }),

            else => return false,
        },

        .float => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = binary_operation.lhs.float.value * @as(f64, @floatFromInt(binary_operation.rhs.int.value)) }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(binary_operation.lhs.int.value)) * binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = binary_operation.lhs.float.value * @as(f64, @floatFromInt(@as(i64, @intFromBool(binary_operation.rhs.boolean.value)))) }) }),

            else => return false,
        },

        .boolean => switch (binary_operation.rhs.*) {
            .int => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = @as(i64, @intFromBool(binary_operation.lhs.boolean.value)) * binary_operation.rhs.int.value }) }),

            .float => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = @as(f64, @floatFromInt(@as(i64, @intFromBool(binary_operation.lhs.boolean.value)))) * binary_operation.rhs.float.value }) }),

            .boolean => try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = @as(i64, @intFromBool(binary_operation.lhs.boolean.value)) * @as(i64, @intFromBool(binary_operation.rhs.boolean.value)) }) }),

            else => return false,
        },

        else => return false,
    }

    try self.code.source_locations.append(binary_operation.source_loc);

    return true;
}

fn optimizeExponent(self: *CodeGen, binary_operation: ast.Node.Expr.BinaryOperation) Error!bool {
    // TODO: Optimize for other cases
    const lhs_casted = castExprToFloat(binary_operation.lhs.*) catch return false;
    const rhs_casted = castExprToFloat(binary_operation.rhs.*) catch return false;

    try self.code.source_locations.append(binary_operation.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = std.math.pow(f64, lhs_casted, rhs_casted) }) });

    return true;
}

fn compileBinaryOperationExpr(self: *CodeGen, binary_operation: ast.Node.Expr.BinaryOperation) Error!void {
    const optimized = try self.optimizeBinaryOperation(binary_operation);

    if (!optimized) {
        try self.compileExpr(binary_operation.lhs.*);
        try self.compileExpr(binary_operation.rhs.*);

        switch (binary_operation.operator) {
            .plus => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .add = {} });
            },

            .minus => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .subtract = {} });
            },

            .forward_slash => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .divide = {} });
            },

            .star => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .multiply = {} });
            },

            .double_star => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .exponent = {} });
            },

            .percent => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .modulo = {} });
            },

            .bang_equal_sign => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .not_equals = {} });
            },

            .double_equal_sign => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .equals = {} });
            },

            .less_than => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .less_than = {} });
            },

            .greater_than => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.{ .greater_than = {} });
            },
        }
    }
}

fn compileAssignmentExpr(self: *CodeGen, assignment: ast.Node.Expr.Assignment) Error!void {
    const was_unused_expression = self.context.unused_expression;
    self.context.unused_expression = false;

    if (assignment.target.* == .subscript) {
        if (assignment.operator != .none) {
            try self.compileExpr(assignment.target.*);
        }

        try self.compileExpr(assignment.value.*);

        try handleAssignmentOperator(self, assignment);

        if (!was_unused_expression) {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .duplicate = {} });
        }

        try self.compileExpr(assignment.target.subscript.index.*);
        try self.compileExpr(assignment.target.subscript.target.*);

        self.context.unused_expression = was_unused_expression;

        try self.code.source_locations.append(assignment.source_loc);
        try self.code.instructions.append(.{ .store_subscript = {} });

        self.context.unused_expression = was_unused_expression;

        if (!self.context.unused_expression) {
            try self.compileExpr(assignment.value.*);
        }
    } else if (assignment.target.* == .identifier) {
        if (assignment.operator != .none) {
            try self.compileExpr(assignment.target.*);
        }

        try self.compileExpr(assignment.value.*);

        try handleAssignmentOperator(self, assignment);

        const atom = try Atom.new(assignment.target.identifier.name.buffer);

        if (self.locals.get(atom) != null) {
            self.context.unused_expression = was_unused_expression;

            if (!self.context.unused_expression) {
                try self.code.source_locations.append(assignment.source_loc);
                try self.code.instructions.append(.{ .duplicate = {} });
            }

            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .store_atom = atom });
        } else {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .store_atom = atom });

            try self.locals.put(atom, {});

            self.context.unused_expression = was_unused_expression;

            if (!self.context.unused_expression) {
                try self.code.source_locations.append(assignment.source_loc);
                try self.code.instructions.append(.{ .duplicate = {} });
            }
        }
    } else {
        self.error_info = .{ .message = "expected a name or subscript to assign to", .source_loc = assignment.source_loc };

        return error.BadOperand;
    }
}

fn handleAssignmentOperator(self: *CodeGen, assignment: ast.Node.Expr.Assignment) Error!void {
    switch (assignment.operator) {
        .none => {},

        .plus => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .add = {} });
        },

        .minus => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .subtract = {} });
        },

        .forward_slash => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .divide = {} });
        },

        .star => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .multiply = {} });
        },

        .double_star => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .exponent = {} });
        },

        .percent => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .modulo = {} });
        },
    }
}

fn compileCallExpr(self: *CodeGen, call: ast.Node.Expr.Call) Error!void {
    const was_unused_expression = self.context.unused_expression;
    self.context.unused_expression = false;

    for (call.arguments) |argument| {
        try self.compileExpr(argument);
    }

    try self.compileExpr(call.callable.*);

    try self.code.source_locations.append(call.source_loc);
    try self.code.instructions.append(.{ .call = call.arguments.len });

    self.context.unused_expression = was_unused_expression;

    if (self.context.unused_expression) {
        try self.code.source_locations.append(call.source_loc);
        try self.code.instructions.append(.{ .pop = {} });
    }
}
