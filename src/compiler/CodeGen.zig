const std = @import("std");

const ast = @import("ast.zig");
const SourceLoc = ast.SourceLoc;
const VirtualMachine = @import("../vm/VirtualMachine.zig");

const CodeGen = @This();

gpa: std.mem.Allocator,

code: VirtualMachine.Code,

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

    pub const Mode = enum {
        script,
        function,
        repl,
    };
};

pub fn init(gpa: std.mem.Allocator, mode: Context.Mode) CodeGen {
    return CodeGen{ .gpa = gpa, .code = .{ .constants = std.ArrayList(VirtualMachine.Code.Value).init(gpa), .instructions = std.ArrayList(VirtualMachine.Code.Instruction).init(gpa), .source_locations = std.ArrayList(SourceLoc).init(gpa) }, .context = .{ .mode = mode, .break_points = std.ArrayList(usize).init(gpa), .continue_points = std.ArrayList(usize).init(gpa) } };
}

pub fn compileRoot(self: *CodeGen, root: ast.Root) Error!void {
    try self.compileNodes(root.body);

    try self.endCode();
}

fn endCode(self: *CodeGen) Error!void {
    if (self.code.instructions.items.len == 0 or self.context.mode != .repl) {
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .none = {} }) } });
    }

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
            try self.compileExpr(node.expr);

            if (self.context.mode != .repl) {
                try self.code.source_locations.append(.{});
                try self.code.instructions.append(.{ .pop = {} });
            }
        },
    }
}

fn compileStmt(self: *CodeGen, stmt: ast.Node.Stmt) Error!void {
    switch (stmt) {
        .variable_declaration => try self.compileVariableDeclarationStmt(stmt.variable_declaration),

        .function_declaration => try self.compileFunctionDeclarationStmt(stmt.function_declaration),

        .conditional => try self.compileConditionalStmt(stmt.conditional),

        .while_loop => try self.compileWhileLoopStmt(stmt.while_loop),

        .@"break" => try self.compileBreakStmt(stmt.@"break"),

        .@"continue" => try self.compileContinueStmt(stmt.@"continue"),

        .@"return" => try self.compileReturnStmt(stmt.@"return"),
    }
}

fn compileVariableDeclarationStmt(self: *CodeGen, variable_declaration: ast.Node.Stmt.VariableDeclaration) Error!void {
    if (variable_declaration.value == null) {
        try self.code.source_locations.append(variable_declaration.name.source_loc);
        try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .none = {} }) } });
    } else {
        try self.compileExpr(variable_declaration.value.?);
    }

    try self.code.source_locations.append(variable_declaration.name.source_loc);
    try self.code.instructions.append(.{ .store = .{ .name = variable_declaration.name.buffer } });

    if (self.context.mode == .repl) {
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .none = {} }) } });
    }
}

fn compileFunctionDeclarationStmt(self: *CodeGen, function_declaration: ast.Node.Stmt.FunctionDeclaration) Error!void {
    var parameters = std.ArrayList([]const u8).init(self.gpa);

    for (function_declaration.parameters) |name| {
        try parameters.append(name.buffer);
    }

    const function: VirtualMachine.Code.Value.Object.Function = .{
        .name = function_declaration.name.buffer,
        .parameters = try parameters.toOwnedSlice(),
        .code = blk: {
            var gen = init(self.gpa, .function);

            try gen.compileNodes(function_declaration.body);

            try gen.endCode();

            break :blk gen.code;
        },
    };

    var function_on_heap = try self.gpa.alloc(VirtualMachine.Code.Value.Object.Function, 1);
    function_on_heap[0] = function;

    try self.code.source_locations.append(function_declaration.name.source_loc);
    try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .object = .{ .function = &function_on_heap[0] } }) } });

    try self.code.source_locations.append(function_declaration.name.source_loc);
    try self.code.instructions.append(.{ .store = .{ .name = function_declaration.name.buffer } });

    if (self.context.mode == .repl) {
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .none = {} }) } });
    }
}

fn compileConditionalStmt(self: *CodeGen, conditional: ast.Node.Stmt.Conditional) Error!void {
    const BacktrackPoint = struct {
        condition_point: usize,
        jump_if_false_point: usize,
        jump_point: usize,
    };

    var backtrack_points = std.ArrayList(BacktrackPoint).init(self.gpa);

    const was_compiling_conditional = self.context.compiling_conditional;
    self.context.compiling_conditional = true;

    for (0..conditional.conditions.len) |i| {
        const condition_point = self.code.instructions.items.len;
        try self.compileExpr(conditional.conditions[i]);

        const jump_if_false_point = self.code.instructions.items.len;
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .jump_if_false = .{ .offset = 0 } });

        try self.compileNodes(conditional.possiblities[i]);

        const jump_point = self.code.instructions.items.len;
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .jump = .{ .offset = 0 } });

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

        self.code.instructions.items[current_backtrack_point.jump_if_false_point] = .{ .jump_if_false = .{ .offset = next_backtrack_point.condition_point - current_backtrack_point.jump_if_false_point - 1 } };

        self.code.instructions.items[current_backtrack_point.jump_point] = .{ .jump = .{ .offset = after_fallback_point - current_backtrack_point.jump_point - 1 } };
    }
}

fn compileWhileLoopStmt(self: *CodeGen, while_loop: ast.Node.Stmt.WhileLoop) Error!void {
    const condition_point = self.code.instructions.items.len;
    try self.compileExpr(while_loop.condition);

    const jump_if_false_point = self.code.instructions.items.len;
    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .jump_if_false = .{ .offset = 0 } });

    const was_compiling_loop = self.context.compiling_loop;
    self.context.compiling_loop = true;

    const previous_break_points_len = self.context.break_points.items.len;

    const previous_continue_points_len = self.context.continue_points.items.len;

    try self.compileNodes(while_loop.body);

    self.context.compiling_loop = was_compiling_loop;

    self.code.instructions.items[jump_if_false_point] = .{ .jump_if_false = .{ .offset = self.code.instructions.items.len - jump_if_false_point } };

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .back = .{ .offset = self.code.instructions.items.len - condition_point + 1 } });

    for (self.context.break_points.items[previous_break_points_len..]) |break_point| {
        self.code.instructions.items[break_point] = .{ .jump = .{ .offset = self.code.instructions.items.len - break_point } };
    }

    for (self.context.continue_points.items[previous_continue_points_len..]) |continue_point| {
        self.code.instructions.items[continue_point] = .{ .back = .{ .offset = continue_point - condition_point + 1 } };
    }

    self.context.break_points.shrinkRetainingCapacity(previous_break_points_len);

    self.context.continue_points.shrinkRetainingCapacity(previous_continue_points_len);

    if (self.context.mode == .repl) {
        try self.code.source_locations.append(.{});
        try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .none = {} }) } });
    }
}

fn compileBreakStmt(self: *CodeGen, @"break": ast.Node.Stmt.Break) Error!void {
    if (!self.context.compiling_loop) {
        self.error_info = .{ .message = "break outside a loop", .source_loc = @"break".source_loc };

        return error.UnexpectedBreak;
    }

    try self.context.break_points.append(self.code.instructions.items.len);
    try self.code.source_locations.append(@"break".source_loc);
    try self.code.instructions.append(.{ .jump = .{ .offset = 0 } });
}

fn compileContinueStmt(self: *CodeGen, @"continue": ast.Node.Stmt.Continue) Error!void {
    if (!self.context.compiling_loop) {
        self.error_info = .{ .message = "continue outside a loop", .source_loc = @"continue".source_loc };

        return error.UnexpectedContinue;
    }

    try self.context.continue_points.append(self.code.instructions.items.len);
    try self.code.source_locations.append(@"continue".source_loc);
    try self.code.instructions.append(.{ .back = .{ .offset = 0 } });
}

fn compileReturnStmt(self: *CodeGen, @"return": ast.Node.Stmt.Return) Error!void {
    if (self.context.mode != .function) {
        self.error_info = .{ .message = "return outside a function", .source_loc = @"return".source_loc };

        return error.UnexpectedReturn;
    }

    if (@"return".value == null) {
        try self.code.source_locations.append(@"return".source_loc);
        try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .none = {} }) } });
    } else {
        try self.compileExpr(@"return".value.?);
    }

    try self.code.source_locations.append(@"return".source_loc);
    try self.code.instructions.append(.{ .@"return" = {} });
}

fn compileExpr(self: *CodeGen, expr: ast.Node.Expr) Error!void {
    switch (expr) {
        .none => try self.compileNoneExpr(expr.none),

        .identifier => try self.compileIdentifierExpr(expr.identifier),

        .string => try self.compileStringExpr(expr.string),

        .int => try self.compileIntExpr(expr.int),

        .float => try self.compileFloatExpr(expr.float),

        .boolean => try self.compileBooleanExpr(expr.boolean),

        .array => try self.compileArrayExpr(expr.array),

        .array_subscript => try self.compileArraySubscriptExpr(expr.array_subscript),

        .unary_operation => try self.compileUnaryOperationExpr(expr.unary_operation),

        .binary_operation => try self.compileBinaryOperationExpr(expr.binary_operation),

        .assignment => try self.compileAssignmentExpr(expr.assignment),

        .call => try self.compileCallExpr(expr.call),
    }
}

fn compileNoneExpr(self: *CodeGen, none: ast.Node.Expr.None) Error!void {
    try self.code.source_locations.append(none.source_loc);
    try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .none = {} }) } });
}

fn compileIdentifierExpr(self: *CodeGen, identifier: ast.Node.Expr.Identifier) Error!void {
    try self.code.source_locations.append(identifier.name.source_loc);
    try self.code.instructions.append(.{ .load = .{ .name = identifier.name.buffer } });
}

fn compileStringExpr(self: *CodeGen, string: ast.Node.Expr.String) Error!void {
    try self.code.source_locations.append(string.source_loc);
    try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .object = .{ .string = .{ .content = string.content } } }) } });
}

fn compileIntExpr(self: *CodeGen, int: ast.Node.Expr.Int) Error!void {
    try self.code.source_locations.append(int.source_loc);
    try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .int = int.value }) } });
}

fn compileFloatExpr(self: *CodeGen, float: ast.Node.Expr.Float) Error!void {
    try self.code.source_locations.append(float.source_loc);
    try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .float = float.value }) } });
}

fn compileBooleanExpr(self: *CodeGen, boolean: ast.Node.Expr.Boolean) Error!void {
    try self.code.source_locations.append(boolean.source_loc);
    try self.code.instructions.append(.{ .load = .{ .constant = try self.code.addConstant(.{ .boolean = boolean.value }) } });
}

fn compileArrayExpr(self: *CodeGen, array: ast.Node.Expr.Array) Error!void {
    for (array.values) |value| {
        try self.compileExpr(value);
    }

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .make = .{ .array = .{ .length = array.values.len } } });
}

fn compileArraySubscriptExpr(self: *CodeGen, array_subscript: ast.Node.Expr.ArraySubscript) Error!void {
    try self.compileExpr(array_subscript.target.*);
    try self.compileExpr(array_subscript.index.*);

    try self.code.source_locations.append(.{});
    try self.code.instructions.append(.{ .load = .{ .subscript = {} } });
}

fn compileUnaryOperationExpr(self: *CodeGen, unary_operation: ast.Node.Expr.UnaryOperation) Error!void {
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

fn compileBinaryOperationExpr(self: *CodeGen, binary_operation: ast.Node.Expr.BinaryOperation) Error!void {
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

fn compileAssignmentExpr(self: *CodeGen, assignment: ast.Node.Expr.Assignment) Error!void {
    if (assignment.target.* == .array_subscript) {
        try self.compileExpr(assignment.target.array_subscript.target.*);
        try self.compileExpr(assignment.target.array_subscript.index.*);
        try self.compileExpr(assignment.value.*);

        try self.code.source_locations.append(assignment.source_loc);
        try self.code.instructions.append(.{ .store = .{ .subscript = {} } });
    } else if (assignment.target.* == .identifier) {
        if (assignment.operator != .none) {
            try self.code.source_locations.append(assignment.source_loc);
            try self.code.instructions.append(.{ .load = .{ .name = assignment.target.identifier.name.buffer } });
        }

        try self.compileExpr(assignment.value.*);

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
        }

        try self.code.source_locations.append(assignment.source_loc);
        try self.code.instructions.append(.{ .store = .{ .name = assignment.target.identifier.name.buffer } });
    } else {
        self.error_info = .{ .message = "expected a name or an array subscript to assign to", .source_loc = assignment.source_loc };

        return error.BadOperand;
    }

    try self.compileExpr(assignment.target.*);
}

fn compileCallExpr(self: *CodeGen, call: ast.Node.Expr.Call) Error!void {
    for (call.arguments) |argument| {
        try self.compileExpr(argument);
    }

    try self.compileExpr(call.callable.*);

    try self.code.source_locations.append(call.source_loc);
    try self.code.instructions.append(.{ .call = .{ .arguments_count = call.arguments.len } });
}
