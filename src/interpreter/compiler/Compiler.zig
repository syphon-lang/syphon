const std = @import("std");

const Ast = @import("Ast.zig");
const Code = @import("../vm/Code.zig");
const VirtualMachine = @import("../vm/VirtualMachine.zig");
const Atom = @import("../vm/Atom.zig");

const Compiler = @This();

allocator: std.mem.Allocator,

parent: ?*Compiler = null,

scope: Scope,
upvalues: Upvalues,
context: Context,
code: Code,

error_info: ?ErrorInfo = null,

pub const Error = error{
    BadOperand,
    UninitializedName,
    UnexpectedBreak,
    UnexpectedContinue,
    UnexpectedReturn,
} || std.mem.Allocator.Error;

pub const ErrorInfo = struct {
    message: []const u8,
    source_loc: Ast.SourceLoc,
};

pub const Scope = struct {
    parent: ?*Scope = null,
    tag: Tag = .global,
    locals: Locals,

    pub const Tag = enum {
        global,
        function,
        loop,
        conditional,
    };

    pub fn getLocal(self: Scope, atom: Atom) ?Local {
        var maybe_current: ?*const Scope = &self;

        while (maybe_current) |current| {
            if (current.locals.get(atom)) |local| {
                return local;
            }

            if (current.tag == .function) break;

            maybe_current = current.parent;
        }

        return null;
    }

    pub fn getLocalPtr(self: *Scope, atom: Atom) ?*Local {
        var maybe_current: ?*Scope = self;

        while (maybe_current) |current| {
            if (current.locals.getPtr(atom)) |local| {
                return local;
            }

            if (current.tag == .function) break;

            maybe_current = current.parent;
        }

        return null;
    }

    pub fn putLocal(self: *Scope, atom: Atom, local: Local) std.mem.Allocator.Error!void {
        return self.locals.put(atom, local);
    }

    pub fn countLocals(self: Scope) Locals.Size {
        return self.countLocalsUntil(.function);
    }

    pub fn countLocalsUntil(self: Scope, tag: Tag) Locals.Size {
        var total: Locals.Size = 0;

        var maybe_current: ?*const Scope = &self;

        while (maybe_current) |current| {
            total += current.locals.count();

            if (current.tag == tag) break;

            maybe_current = current.parent;
        }

        return total;
    }

    pub fn popLocalsUntil(self: Scope, code: *Code, tag: Scope.Tag) Error!void {
        for (0..self.countLocalsUntil(tag)) |_| {
            try code.source_locations.append(.{});
            try code.instructions.append(.pop);
        }
    }
};

pub const Upvalues = std.AutoHashMap(Atom, Upvalue);

pub const Upvalue = struct {
    index: usize,
    local_index: ?usize = null,
    pointer_index: ?usize = null,
};

pub const Locals = std.AutoHashMap(Atom, Local);

pub const Local = struct {
    index: usize,
    captured: bool = false,
};

pub const Context = struct {
    mode: Mode,
    compiling_conditional: bool = false,
    compiling_loop: bool = false,
    break_points: std.ArrayList(usize),
    continue_points: std.ArrayList(usize),

    pub const Mode = enum {
        script,
        function,
    };
};

pub fn init(allocator: std.mem.Allocator, mode: Context.Mode) std.mem.Allocator.Error!Compiler {
    return Compiler{
        .allocator = allocator,
        .scope = .{
            .locals = Locals.init(allocator),
        },
        .upvalues = Upvalues.init(allocator),
        .context = .{
            .mode = mode,
            .break_points = std.ArrayList(usize).init(allocator),
            .continue_points = std.ArrayList(usize).init(allocator),
        },
        .code = .{
            .constants = std.ArrayList(Code.Value).init(allocator),
            .instructions = std.ArrayList(Code.Instruction).init(allocator),
            .source_locations = std.ArrayList(Ast.SourceLoc).init(allocator),
        },
    };
}

fn getUpvalue(self: *Compiler, atom: Atom) std.mem.Allocator.Error!?Upvalue {
    if (self.upvalues.get(atom)) |upvalue| {
        return upvalue;
    }

    var maybe_current: ?*Compiler = self.parent;

    while (maybe_current) |current| {
        if (current.context.mode == .script) break;

        if (current.scope.getLocalPtr(atom)) |local| {
            const upvalue: Upvalue = .{ .index = self.upvalues.count(), .local_index = local.index };

            try self.upvalues.put(atom, upvalue);

            local.captured = true;

            return upvalue;
        }

        if (try current.getUpvalue(atom)) |other_upvalue| {
            const upvalue: Upvalue = .{ .index = self.upvalues.count(), .pointer_index = other_upvalue.index };

            try self.upvalues.put(atom, upvalue);

            return upvalue;
        }

        maybe_current = current.parent;
    }

    return null;
}

fn closeUpvalues(self: *Compiler) std.mem.Allocator.Error!void {
    var scope_local_iterator = self.scope.locals.valueIterator();

    while (scope_local_iterator.next()) |scope_local| {
        if (scope_local.captured) {
            try self.code.source_locations.append(.{});
            try self.code.instructions.append(.{ .close_upvalue = scope_local.index });
        }
    }
}

pub fn compile(self: *Compiler, ast: Ast) Error!void {
    try self.compileNodes(ast.body);

    try self.endCode();
}

fn endCode(self: *Compiler) Error!void {
    try self.closeUpvalues();

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.none) });

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.@"return");
}

fn compileNodes(self: *Compiler, nodes: []const Ast.Node) Error!void {
    for (nodes) |node| {
        try self.compileNode(node);
    }
}

fn compileNode(self: *Compiler, node: Ast.Node) Error!void {
    switch (node) {
        .stmt => try self.compileStmt(node.stmt),
        .expr => {
            try self.compileExpr(node.expr);

            try self.code.source_locations.append(.{});
            try self.code.instructions.append(.pop);
        },
    }
}

fn compileStmt(self: *Compiler, stmt: Ast.Node.Stmt) Error!void {
    switch (stmt) {
        .conditional => try self.compileConditionalStmt(stmt.conditional),

        .while_loop => try self.compileWhileLoopStmt(stmt.while_loop),

        .@"break" => try self.compileBreakStmt(stmt.@"break"),

        .@"continue" => try self.compileContinueStmt(stmt.@"continue"),

        .@"return" => try self.compileReturnStmt(stmt.@"return"),
    }
}

fn compileConditionalStmt(self: *Compiler, conditional: Ast.Node.Stmt.Conditional) Error!void {
    const BacktrackPoint = struct {
        condition_point: usize,
        jump_if_false_point: usize,
        jump_point: usize,
    };

    var backtrack_points = std.ArrayList(BacktrackPoint).init(self.allocator);

    const was_compiling_conditional = self.context.compiling_conditional;
    self.context.compiling_conditional = true;

    var parent_scope = self.scope;

    for (0..conditional.conditions.len) |i| {
        const condition_point = self.code.instructions.items.len;
        try self.compileExpr(conditional.conditions[i]);

        const jump_if_false_point = self.code.instructions.items.len;
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .jump_if_false = 0 });

        self.scope = .{
            .parent = &parent_scope,
            .tag = .conditional,
            .locals = Locals.init(self.allocator),
        };

        try self.compileNodes(conditional.possiblities[i]);

        try self.closeUpvalues();

        try self.scope.popLocalsUntil(&self.code, .conditional);

        const jump_point = self.code.instructions.items.len;
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .jump = 0 });

        try backtrack_points.append(.{ .condition_point = condition_point, .jump_if_false_point = jump_if_false_point, .jump_point = jump_point });
    }

    const fallback_point = self.code.instructions.items.len;

    self.scope.locals = Locals.init(self.allocator);

    try self.compileNodes(conditional.fallback);

    try self.closeUpvalues();

    try self.scope.popLocalsUntil(&self.code, .conditional);

    self.scope = parent_scope;

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

fn compileWhileLoopStmt(self: *Compiler, while_loop: Ast.Node.Stmt.WhileLoop) Error!void {
    const condition_point = self.code.instructions.items.len;
    try self.compileExpr(while_loop.condition);

    const jump_if_false_point = self.code.instructions.items.len;
    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .jump_if_false = 0 });

    const was_compiling_loop = self.context.compiling_loop;
    self.context.compiling_loop = true;

    const previous_break_points_len = self.context.break_points.items.len;

    const previous_continue_points_len = self.context.continue_points.items.len;

    var parent_scope = self.scope;

    self.scope = .{
        .parent = &parent_scope,
        .tag = .loop,
        .locals = Locals.init(self.allocator),
    };

    try self.compileNodes(while_loop.body);

    try self.closeUpvalues();

    try self.scope.popLocalsUntil(&self.code, .loop);

    self.scope = parent_scope;

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

fn compileBreakStmt(self: *Compiler, @"break": Ast.Node.Stmt.Break) Error!void {
    if (!self.context.compiling_loop) {
        self.error_info = .{ .message = "break outside a loop", .source_loc = @"break".source_loc };

        return error.UnexpectedBreak;
    }

    try self.closeUpvalues();

    try self.scope.popLocalsUntil(&self.code, .loop);

    try self.context.break_points.append(self.code.instructions.items.len);
    try self.code.source_locations.append(@"break".source_loc);
    try self.code.instructions.append(.{ .jump = 0 });
}

fn compileContinueStmt(self: *Compiler, @"continue": Ast.Node.Stmt.Continue) Error!void {
    if (!self.context.compiling_loop) {
        self.error_info = .{ .message = "continue outside a loop", .source_loc = @"continue".source_loc };

        return error.UnexpectedContinue;
    }

    try self.closeUpvalues();

    try self.scope.popLocalsUntil(&self.code, .loop);

    try self.context.continue_points.append(self.code.instructions.items.len);
    try self.code.source_locations.append(@"continue".source_loc);
    try self.code.instructions.append(.{ .back = 0 });
}

fn compileReturnStmt(self: *Compiler, @"return": Ast.Node.Stmt.Return) Error!void {
    if (self.context.mode != .function) {
        self.error_info = .{ .message = "return outside a function", .source_loc = @"return".source_loc };

        return error.UnexpectedReturn;
    }

    try self.compileExpr(@"return".value);

    try self.closeUpvalues();

    try self.code.source_locations.append(@"return".source_loc);
    try self.code.instructions.append(.@"return");
}

fn compileExpr(self: *Compiler, expr: Ast.Node.Expr) Error!void {
    switch (expr) {
        .identifier => try self.compileIdentifierExpr(expr.identifier),

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

        .subscript => try self.compileSubscriptExpr(expr.subscript),

        .assignment => try self.compileAssignmentExpr(expr.assignment),

        .call => try self.compileCallExpr(expr.call),
    }
}

fn compileNoneExpr(self: *Compiler, none: Ast.Node.Expr.None) Error!void {
    try self.code.source_locations.append(none.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.none) });
}

fn compileIdentifierExpr(self: *Compiler, identifier: Ast.Node.Expr.Identifier) Error!void {
    const atom = try Atom.new(identifier.name.buffer);

    if (self.scope.getLocal(atom)) |local| {
        try self.code.source_locations.append(identifier.name.source_loc);
        try self.code.instructions.append(.{ .load_local = local.index });
    } else if (try self.getUpvalue(atom)) |upvalue| {
        try self.code.source_locations.append(identifier.name.source_loc);
        try self.code.instructions.append(.{ .load_upvalue = upvalue.index });
    } else {
        try self.code.source_locations.append(identifier.name.source_loc);
        try self.code.instructions.append(.{ .load_global = atom });
    }
}

fn compileStringExpr(self: *Compiler, string: Ast.Node.Expr.String) Error!void {
    try self.code.source_locations.append(string.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .string = .{ .content = string.content } }) });
}

fn compileIntExpr(self: *Compiler, int: Ast.Node.Expr.Int) Error!void {
    try self.code.source_locations.append(int.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .int = int.value }) });
}

fn compileFloatExpr(self: *Compiler, float: Ast.Node.Expr.Float) Error!void {
    try self.code.source_locations.append(float.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = float.value }) });
}

fn compileBooleanExpr(self: *Compiler, boolean: Ast.Node.Expr.Boolean) Error!void {
    try self.code.source_locations.append(boolean.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .boolean = boolean.value }) });
}

fn compileArrayExpr(self: *Compiler, array: Ast.Node.Expr.Array) Error!void {
    for (array.values) |value| {
        try self.compileExpr(value);
    }

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .make_array = array.values.len });
}

fn compileMapExpr(self: *Compiler, map: Ast.Node.Expr.Map) Error!void {
    for (0..map.keys.len) |i| {
        try self.compileExpr(map.keys[map.keys.len - 1 - i]);
        try self.compileExpr(map.values[map.values.len - 1 - i]);
    }

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .make_map = @intCast(map.keys.len) });
}

fn compileFunctionExpr(self: *Compiler, ast_function: Ast.Node.Expr.Function) Error!void {
    var parameters = std.ArrayList(Atom).init(self.allocator);

    for (ast_function.parameters) |ast_parameter| {
        try parameters.append(try Atom.new(ast_parameter.buffer));
    }

    var compiler = try init(self.allocator, .function);

    compiler.parent = self;
    compiler.scope.parent = &self.scope;

    compiler.scope.tag = .function;

    for (parameters.items, 0..) |parameter, i| {
        try compiler.scope.putLocal(parameter, .{ .index = i });
    }

    try compiler.compileNodes(ast_function.body);

    try compiler.endCode();

    const function: Code.Value.Function = .{
        .parameters = parameters.items,
        .code = compiler.code,
    };

    const function_on_heap = try self.allocator.create(Code.Value.Function);
    function_on_heap.* = function;

    const function_constant_index = try self.code.addConstant(.{ .function = function_on_heap });

    var upvalues = Code.Instruction.MakeClosure.Upvalues.init(self.allocator);

    try upvalues.appendNTimes(undefined, compiler.upvalues.count());

    var compiler_upvalue_iterator = compiler.upvalues.valueIterator();

    while (compiler_upvalue_iterator.next()) |compiler_upvalue| {
        upvalues.items[compiler_upvalue.index] = .{ .local_index = compiler_upvalue.local_index, .pointer_index = compiler_upvalue.pointer_index };
    }

    try self.code.source_locations.append(ast_function.source_loc);
    try self.code.instructions.append(.{ .make_closure = .{ .function_constant_index = function_constant_index, .upvalues = upvalues } });
}

fn compileSubscriptExpr(self: *Compiler, subscript: Ast.Node.Expr.Subscript) Error!void {
    try self.compileExpr(subscript.target.*);
    try self.compileExpr(subscript.index.*);

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.load_subscript);
}

fn knownAtCompileTime(expr: Ast.Node.Expr) bool {
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

fn optimizeUnaryOperation(self: *Compiler, unary_operation: Ast.Node.Expr.UnaryOperation) Error!bool {
    if (!knownAtCompileTime(unary_operation.rhs.*)) return false;

    switch (unary_operation.operator) {
        .minus => return self.optimizeNeg(unary_operation),
        .bang => return self.optimizeNot(unary_operation),
    }
}

fn optimizeNeg(self: *Compiler, unary_operation: Ast.Node.Expr.UnaryOperation) Error!bool {
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

fn optimizeNot(self: *Compiler, unary_operation: Ast.Node.Expr.UnaryOperation) Error!bool {
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

fn compileUnaryOperationExpr(self: *Compiler, unary_operation: Ast.Node.Expr.UnaryOperation) Error!void {
    const optimized = try self.optimizeUnaryOperation(unary_operation);

    if (!optimized) {
        try self.compileExpr(unary_operation.rhs.*);

        switch (unary_operation.operator) {
            .minus => {
                try self.code.source_locations.append(unary_operation.source_loc);
                try self.code.instructions.append(.neg);
            },

            .bang => {
                try self.code.source_locations.append(unary_operation.source_loc);
                try self.code.instructions.append(.not);
            },
        }
    }
}

fn optimizeBinaryOperation(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!bool {
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

fn optimizeAdd(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!bool {
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

fn optimizeSubtract(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!bool {
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

fn cAstExprToFloat(expr: Ast.Node.Expr) error{CastingFailed}!f64 {
    return switch (expr) {
        .int => @floatFromInt(expr.int.value),

        .float => expr.float.value,

        .boolean => @floatFromInt(@intFromBool(expr.boolean.value)),

        else => error.CastingFailed,
    };
}

fn optimizeDivide(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!bool {
    // TODO: Optimize for other cases
    const lhs_cAsted = cAstExprToFloat(binary_operation.lhs.*) catch return false;
    const rhs_cAsted = cAstExprToFloat(binary_operation.rhs.*) catch return false;

    try self.code.source_locations.append(binary_operation.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = lhs_cAsted / rhs_cAsted }) });

    return true;
}

fn optimizeMultiply(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!bool {
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

fn optimizeExponent(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!bool {
    // TODO: Optimize for other cases
    const lhs_cAsted = cAstExprToFloat(binary_operation.lhs.*) catch return false;
    const rhs_cAsted = cAstExprToFloat(binary_operation.rhs.*) catch return false;

    try self.code.source_locations.append(binary_operation.source_loc);
    try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.{ .float = std.math.pow(f64, lhs_cAsted, rhs_cAsted) }) });

    return true;
}

fn compileBinaryOperationExpr(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!void {
    const optimized = try self.optimizeBinaryOperation(binary_operation);

    if (!optimized) {
        try self.compileExpr(binary_operation.lhs.*);
        try self.compileExpr(binary_operation.rhs.*);

        switch (binary_operation.operator) {
            .plus => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.add);
            },

            .minus => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.subtract);
            },

            .forward_slash => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.divide);
            },

            .star => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.multiply);
            },

            .double_star => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.exponent);
            },

            .percent => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.modulo);
            },

            .bang_equal_sign => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.not_equals);
            },

            .double_equal_sign => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.equals);
            },

            .less_than => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.less_than);
            },

            .greater_than => {
                try self.code.source_locations.append(binary_operation.source_loc);
                try self.code.instructions.append(.greater_than);
            },
        }
    }
}

fn compileAssignmentExpr(self: *Compiler, assignment: Ast.Node.Expr.Assignment) Error!void {
    if (assignment.target.* == .subscript) {
        if (assignment.operator != .none) {
            try self.compileExpr(assignment.target.*);
        }

        try self.compileExpr(assignment.value.*);

        try handleAssignmentOperator(self, assignment);

        try self.code.source_locations.append(assignment.source_loc);
        try self.code.instructions.append(.duplicate);

        try self.compileExpr(assignment.target.subscript.index.*);
        try self.compileExpr(assignment.target.subscript.target.*);

        try self.code.source_locations.append(assignment.source_loc);
        try self.code.instructions.append(.store_subscript);
    } else if (assignment.target.* == .identifier) {
        if (assignment.operator != .none) {
            try self.compileExpr(assignment.target.*);
        }

        const atom = try Atom.new(assignment.target.identifier.name.buffer);

        if (assignment.value.* == .function and self.context.mode == .function and self.scope.getLocal(atom) == null and (try self.getUpvalue(atom)) == null) {
            const index = self.scope.countLocals();

            try self.scope.putLocal(atom, .{ .index = index });

            try self.code.source_locations.append(.{});
            try self.code.instructions.append(.{ .load_constant = try self.code.addConstant(.none) });
        }

        try self.compileExpr(assignment.value.*);

        try handleAssignmentOperator(self, assignment);

        if (self.context.mode == .function) {
            if (self.scope.getLocal(atom)) |local| {
                try self.code.source_locations.append(assignment.source_loc);
                try self.code.instructions.append(.duplicate);

                try self.code.source_locations.append(assignment.source_loc);
                try self.code.instructions.append(.{ .store_local = local.index });
            } else if (try self.getUpvalue(atom)) |upvalue| {
                try self.code.source_locations.append(assignment.source_loc);
                try self.code.instructions.append(.duplicate);

                try self.code.source_locations.append(assignment.source_loc);
                try self.code.instructions.append(.{ .store_upvalue = upvalue.index });
            } else {
                const index = self.scope.countLocals();

                try self.scope.putLocal(atom, .{ .index = index });

                try self.code.source_locations.append(assignment.source_loc);
                try self.code.instructions.append(.duplicate);
            }
        } else {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.duplicate);

            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .store_global = atom });
        }
    } else {
        self.error_info = .{ .message = "expected a name or subscript to assign to", .source_loc = assignment.source_loc };

        return error.BadOperand;
    }
}

fn handleAssignmentOperator(self: *Compiler, assignment: Ast.Node.Expr.Assignment) Error!void {
    switch (assignment.operator) {
        .none => {},

        .plus => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.add);
        },

        .minus => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.subtract);
        },

        .forward_slash => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.divide);
        },

        .star => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.multiply);
        },

        .double_star => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.exponent);
        },

        .percent => {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.modulo);
        },
    }
}

fn compileCallExpr(self: *Compiler, call: Ast.Node.Expr.Call) Error!void {
    for (call.arguments) |argument| {
        try self.compileExpr(argument);
    }

    try self.compileExpr(call.callable.*);

    try self.code.source_locations.append(call.source_loc);
    try self.code.instructions.append(.{ .call = call.arguments.len });
}
