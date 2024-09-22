const std = @import("std");

const Ast = @import("Ast.zig");
const Optimizer = @import("Optimizer.zig");
const Code = @import("../vm/Code.zig");
const VirtualMachine = @import("../vm/VirtualMachine.zig");
const Atom = @import("../vm/Atom.zig");

const Compiler = @This();

allocator: std.mem.Allocator,

parent: ?*Compiler = null,

scope: Scope,
upvalues: Upvalues,
context: Context,
optimizer: Optimizer,

error_info: ?ErrorInfo = null,

pub const Error = error{
    BadOperand,
    UninitializedName,
    UnexpectedBreak,
    UnexpectedContinue,
    UnexpectedReturn,
} || Optimizer.Error || std.mem.Allocator.Error;

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
        .optimizer = Optimizer.init(allocator),
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
            try self.optimizer.emitInstruction(.{ .close_upvalue = scope_local.index }, .{});
        }
    }
}

pub fn compile(self: *Compiler, ast: Ast) Error!void {
    try self.compileNodes(ast.body);

    try self.endCode();
}

fn endCode(self: *Compiler) Error!void {
    try self.closeUpvalues();

    try self.optimizer.emitConstant(.none, .{});
    try self.optimizer.emitInstruction(.@"return", .{});
}

fn compileNodes(self: *Compiler, nodes: []const Ast.Node) Error!void {
    for (nodes) |node| {
        try self.compileNode(node);
    }
}

fn compileNode(self: *Compiler, node: Ast.Node) Error!void {
    switch (node) {
        .stmt => |stmt| try self.compileStmt(stmt),
        .expr => |expr| {
            try self.compileExpr(expr);

            try self.optimizer.emitInstruction(.pop, .{});
        },
    }
}

fn compileStmt(self: *Compiler, stmt: Ast.Node.Stmt) Error!void {
    switch (stmt) {
        .conditional => |conditional| try self.compileConditionalStmt(conditional),

        .while_loop => |while_loop| try self.compileWhileLoopStmt(while_loop),

        .@"break" => |@"break"| try self.compileBreakStmt(@"break"),

        .@"continue" => |@"continue"| try self.compileContinueStmt(@"continue"),

        .@"return" => |@"return"| try self.compileReturnStmt(@"return"),
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
        const condition_point = self.optimizer.code.instructions.items.len;
        try self.compileExpr(conditional.conditions[i]);

        const jump_if_false_point = self.optimizer.code.instructions.items.len;
        try self.optimizer.emitInstruction(.{ .jump_if_false = 0 }, .{});

        self.scope = .{
            .parent = &parent_scope,
            .tag = .conditional,
            .locals = Locals.init(self.allocator),
        };

        try self.compileNodes(conditional.possiblities[i]);

        try self.closeUpvalues();

        try self.scope.popLocalsUntil(&self.optimizer.code, .conditional);

        const jump_point = self.optimizer.code.instructions.items.len;
        try self.optimizer.emitInstruction(.{ .jump = 0 }, .{});

        try backtrack_points.append(.{ .condition_point = condition_point, .jump_if_false_point = jump_if_false_point, .jump_point = jump_point });
    }

    const fallback_point = self.optimizer.code.instructions.items.len;

    self.scope.locals.clearRetainingCapacity();

    try self.compileNodes(conditional.fallback);

    try self.closeUpvalues();

    try self.scope.popLocalsUntil(&self.optimizer.code, .conditional);

    self.scope = parent_scope;

    const after_fallback_point = self.optimizer.code.instructions.items.len;

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

        self.optimizer.code.instructions.items[current_backtrack_point.jump_if_false_point] = .{ .jump_if_false = next_backtrack_point.condition_point - current_backtrack_point.jump_if_false_point - 1 };

        self.optimizer.code.instructions.items[current_backtrack_point.jump_point] = .{ .jump = after_fallback_point - current_backtrack_point.jump_point - 1 };
    }
}

fn compileWhileLoopStmt(self: *Compiler, while_loop: Ast.Node.Stmt.WhileLoop) Error!void {
    const condition_point = self.optimizer.code.instructions.items.len;
    try self.compileExpr(while_loop.condition);

    const jump_if_false_point = self.optimizer.code.instructions.items.len;
    try self.optimizer.emitInstruction(.{ .jump_if_false = 0 }, .{});

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

    try self.scope.popLocalsUntil(&self.optimizer.code, .loop);

    self.scope.locals.deinit();

    self.scope = parent_scope;

    self.context.compiling_loop = was_compiling_loop;

    self.optimizer.code.instructions.items[jump_if_false_point] = .{ .jump_if_false = self.optimizer.code.instructions.items.len - jump_if_false_point };

    for (self.context.break_points.items[previous_break_points_len..]) |break_point| {
        self.optimizer.code.instructions.items[break_point] = .{ .jump = self.optimizer.code.instructions.items.len - break_point };
    }

    try self.optimizer.emitInstruction(.{ .back = self.optimizer.code.instructions.items.len - condition_point + 1 }, .{});

    for (self.context.continue_points.items[previous_continue_points_len..]) |continue_point| {
        self.optimizer.code.instructions.items[continue_point] = .{ .back = continue_point - condition_point + 1 };
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

    try self.scope.popLocalsUntil(&self.optimizer.code, .loop);

    try self.context.break_points.append(self.optimizer.code.instructions.items.len);
    try self.optimizer.emitInstruction(.{ .jump = 0 }, @"break".source_loc);
}

fn compileContinueStmt(self: *Compiler, @"continue": Ast.Node.Stmt.Continue) Error!void {
    if (!self.context.compiling_loop) {
        self.error_info = .{ .message = "continue outside a loop", .source_loc = @"continue".source_loc };

        return error.UnexpectedContinue;
    }

    try self.closeUpvalues();

    try self.scope.popLocalsUntil(&self.optimizer.code, .loop);

    try self.context.continue_points.append(self.optimizer.code.instructions.items.len);
    try self.optimizer.emitInstruction(.{ .back = 0 }, @"continue".source_loc);
}

fn compileReturnStmt(self: *Compiler, @"return": Ast.Node.Stmt.Return) Error!void {
    if (self.context.mode != .function) {
        self.error_info = .{ .message = "return outside a function", .source_loc = @"return".source_loc };

        return error.UnexpectedReturn;
    }

    try self.compileExpr(@"return".value);

    try self.closeUpvalues();

    try self.optimizer.emitInstruction(.@"return", @"return".source_loc);
}

fn compileExpr(self: *Compiler, expr: Ast.Node.Expr) Error!void {
    switch (expr) {
        .identifier => |identifier| try self.compileIdentifierExpr(identifier),

        .none => |none| try self.compileNoneExpr(none),

        .string => |string| try self.compileStringExpr(string),

        .int => |int| try self.compileIntExpr(int),

        .float => |float| try self.compileFloatExpr(float),

        .boolean => |boolean| try self.compileBooleanExpr(boolean),

        .array => |array| try self.compileArrayExpr(array),

        .map => |map| try self.compileMapExpr(map),

        .function => |function| try self.compileFunctionExpr(function),

        .unary_operation => |unary_operation| try self.compileUnaryOperationExpr(unary_operation),

        .binary_operation => |binary_operation| try self.compileBinaryOperationExpr(binary_operation),

        .subscript => |subscript| try self.compileSubscriptExpr(subscript),

        .call => |call| try self.compileCallExpr(call),
    }
}

fn compileIdentifierExpr(self: *Compiler, identifier: Ast.Node.Expr.Identifier) Error!void {
    const atom = try Atom.new(identifier.name.buffer);

    if (self.scope.getLocal(atom)) |local| {
        try self.optimizer.emitInstruction(.{ .load_local = local.index }, identifier.name.source_loc);
    } else if (try self.getUpvalue(atom)) |upvalue| {
        try self.optimizer.emitInstruction(.{ .load_upvalue = upvalue.index }, identifier.name.source_loc);
    } else {
        try self.optimizer.emitInstruction(.{ .load_global = atom }, identifier.name.source_loc);
    }
}

fn compileNoneExpr(self: *Compiler, none: Ast.Node.Expr.None) Error!void {
    try self.optimizer.emitConstant(.none, none.source_loc);
}

fn compileStringExpr(self: *Compiler, string: Ast.Node.Expr.String) Error!void {
    try self.optimizer.emitConstant(.{ .string = .{ .content = string.content } }, string.source_loc);
}

fn compileIntExpr(self: *Compiler, int: Ast.Node.Expr.Int) Error!void {
    try self.optimizer.emitConstant(.{ .int = int.value }, int.source_loc);
}

fn compileFloatExpr(self: *Compiler, float: Ast.Node.Expr.Float) Error!void {
    try self.optimizer.emitConstant(.{ .float = float.value }, float.source_loc);
}

fn compileBooleanExpr(self: *Compiler, boolean: Ast.Node.Expr.Boolean) Error!void {
    try self.optimizer.emitConstant(.{ .boolean = boolean.value }, boolean.source_loc);
}

fn compileArrayExpr(self: *Compiler, array: Ast.Node.Expr.Array) Error!void {
    for (array.values) |value| {
        try self.compileExpr(value);
    }

    try self.optimizer.emitInstruction(.{ .make_array = array.values.len }, .{});
}

fn compileMapExpr(self: *Compiler, map: Ast.Node.Expr.Map) Error!void {
    for (0..map.keys.len) |i| {
        try self.compileExpr(map.keys[map.keys.len - 1 - i]);
        try self.compileExpr(map.values[map.values.len - 1 - i]);
    }

    try self.optimizer.emitInstruction(.{ .make_map = @intCast(map.keys.len) }, .{});
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
        .code = compiler.optimizer.code,
    };

    const function_on_heap = try self.allocator.create(Code.Value.Function);
    function_on_heap.* = function;

    const function_constant_index = try self.optimizer.code.addConstant(.{ .function = function_on_heap });

    var upvalues = Code.Instruction.MakeClosure.Upvalues.init(self.allocator);

    try upvalues.appendNTimes(undefined, compiler.upvalues.count());

    var compiler_upvalue_iterator = compiler.upvalues.valueIterator();

    while (compiler_upvalue_iterator.next()) |compiler_upvalue| {
        upvalues.items[compiler_upvalue.index] = .{ .local_index = compiler_upvalue.local_index, .pointer_index = compiler_upvalue.pointer_index };
    }

    try self.optimizer.emitInstruction(.{ .make_closure = .{ .function_constant_index = function_constant_index, .upvalues = upvalues } }, ast_function.source_loc);
}

fn compileSubscriptExpr(self: *Compiler, subscript: Ast.Node.Expr.Subscript) Error!void {
    try self.compileExpr(subscript.target.*);
    try self.compileExpr(subscript.index.*);

    try self.optimizer.emitInstruction(.load_subscript, .{});
}

fn compileUnaryOperationExpr(self: *Compiler, unary_operation: Ast.Node.Expr.UnaryOperation) Error!void {
    try self.compileExpr(unary_operation.rhs.*);

    switch (unary_operation.operator) {
        .minus => {
            try self.optimizer.emitInstruction(.neg, unary_operation.source_loc);
        },

        .bang => {
            try self.optimizer.emitInstruction(.not, unary_operation.source_loc);
        },
    }
}

fn compileBinaryOperationExpr(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!void {
    switch (binary_operation.operator) {
        .equal_sign,
        .plus_equal_sign,
        .minus_equal_sign,
        .forward_slash_equal_sign,
        .star_equal_sign,
        .double_star_equal_sign,
        .percent_equal_sign,
        => {
            if (binary_operation.lhs.* == .subscript) {
                if (binary_operation.operator != .equal_sign) {
                    try self.compileExpr(binary_operation.lhs.*);
                }

                try self.compileExpr(binary_operation.rhs.*);

                try handleAssignmentOperator(self, binary_operation);

                try self.optimizer.emitInstruction(.duplicate, binary_operation.source_loc);

                try self.compileExpr(binary_operation.lhs.subscript.index.*);
                try self.compileExpr(binary_operation.lhs.subscript.target.*);

                try self.optimizer.emitInstruction(.store_subscript, binary_operation.source_loc);
            } else if (binary_operation.lhs.* == .identifier) {
                if (binary_operation.operator != .equal_sign) {
                    try self.compileExpr(binary_operation.lhs.*);
                }

                const atom = try Atom.new(binary_operation.lhs.identifier.name.buffer);

                if (binary_operation.rhs.* == .function and self.context.mode == .function and self.scope.getLocal(atom) == null and (try self.getUpvalue(atom)) == null) {
                    const index = self.scope.countLocals();

                    try self.scope.putLocal(atom, .{ .index = index });

                    try self.optimizer.emitConstant(.none, .{});
                }

                try self.compileExpr(binary_operation.rhs.*);

                try handleAssignmentOperator(self, binary_operation);

                if (self.context.mode == .function) {
                    if (self.scope.getLocal(atom)) |local| {
                        try self.optimizer.emitInstruction(.duplicate, binary_operation.source_loc);

                        try self.optimizer.emitInstruction(.{ .store_local = local.index }, binary_operation.source_loc);
                    } else if (try self.getUpvalue(atom)) |upvalue| {
                        try self.optimizer.emitInstruction(.duplicate, binary_operation.source_loc);

                        try self.optimizer.emitInstruction(.{ .store_upvalue = upvalue.index }, binary_operation.source_loc);
                    } else {
                        const index = self.scope.countLocals();

                        try self.scope.putLocal(atom, .{ .index = index });

                        try self.optimizer.emitInstruction(.duplicate, binary_operation.source_loc);
                    }
                } else {
                    try self.optimizer.emitInstruction(.duplicate, binary_operation.source_loc);

                    try self.optimizer.emitInstruction(.{ .store_global = atom }, binary_operation.source_loc);
                }
            } else {
                self.error_info = .{ .message = "expected a name or subscript to assign to", .source_loc = binary_operation.source_loc };

                return error.BadOperand;
            }

            return;
        },

        else => {},
    }

    try self.compileExpr(binary_operation.lhs.*);
    try self.compileExpr(binary_operation.rhs.*);

    switch (binary_operation.operator) {
        .plus => {
            try self.optimizer.emitInstruction(.add, binary_operation.source_loc);
        },

        .minus => {
            try self.optimizer.emitInstruction(.subtract, binary_operation.source_loc);
        },

        .forward_slash => {
            try self.optimizer.emitInstruction(.divide, binary_operation.source_loc);
        },

        .star => {
            try self.optimizer.emitInstruction(.multiply, binary_operation.source_loc);
        },

        .double_star => {
            try self.optimizer.emitInstruction(.exponent, binary_operation.source_loc);
        },

        .percent => {
            try self.optimizer.emitInstruction(.modulo, binary_operation.source_loc);
        },

        .bang_equal_sign, .double_equal_sign => {
            try self.optimizer.emitInstruction(.equals, binary_operation.source_loc);

            if (binary_operation.operator == .bang_equal_sign) {
                try self.optimizer.emitInstruction(.not, binary_operation.source_loc);
            }
        },

        .less_than => {
            try self.optimizer.emitInstruction(.less_than, binary_operation.source_loc);
        },

        .greater_than => {
            try self.optimizer.emitInstruction(.greater_than, binary_operation.source_loc);
        },

        else => {},
    }
}

fn handleAssignmentOperator(self: *Compiler, binary_operation: Ast.Node.Expr.BinaryOperation) Error!void {
    switch (binary_operation.operator) {
        .plus_equal_sign => {
            try self.optimizer.emitInstruction(.add, binary_operation.source_loc);
        },

        .minus_equal_sign => {
            try self.optimizer.emitInstruction(.subtract, binary_operation.source_loc);
        },

        .forward_slash_equal_sign => {
            try self.optimizer.emitInstruction(.divide, binary_operation.source_loc);
        },

        .star_equal_sign => {
            try self.optimizer.emitInstruction(.multiply, binary_operation.source_loc);
        },

        .double_star_equal_sign => {
            try self.optimizer.emitInstruction(.exponent, binary_operation.source_loc);
        },

        .percent_equal_sign => {
            try self.optimizer.emitInstruction(.modulo, binary_operation.source_loc);
        },

        else => {},
    }
}

fn compileCallExpr(self: *Compiler, call: Ast.Node.Expr.Call) Error!void {
    for (call.arguments) |argument| {
        try self.compileExpr(argument);
    }

    try self.compileExpr(call.callable.*);

    try self.optimizer.emitInstruction(.{ .call = call.arguments.len }, call.source_loc);
}
