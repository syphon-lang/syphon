const std = @import("std");

const Token = @import("Token.zig");
const Lexer = @import("Lexer.zig");

pub const SourceLoc = struct {
    line: usize = 1,
    column: usize = 1,
};

pub const Name = struct {
    buffer: []const u8,
    source_loc: SourceLoc,
};

pub const Root = struct {
    body: []Node,
};

pub const Node = union(enum) {
    stmt: Stmt,
    expr: Expr,

    pub const Stmt = union(enum) {
        function_declaration: FunctionDeclaration,
        conditional: Conditional,
        while_loop: WhileLoop,
        @"break": Break,
        @"continue": Continue,
        @"return": Return,

        pub const FunctionDeclaration = struct {
            name: Name,
            parameters: []Name,
            body: []Node,
        };

        pub const Conditional = struct {
            conditions: []Expr,
            possiblities: [][]Node,
            fallback: []Node,
        };

        pub const WhileLoop = struct {
            condition: Expr,
            body: []Node,
        };

        pub const Break = struct {
            source_loc: SourceLoc,
        };

        pub const Continue = struct {
            source_loc: SourceLoc,
        };

        pub const Return = struct {
            value: Expr,
            source_loc: SourceLoc,
        };
    };

    pub const Expr = union(enum) {
        none: None,
        identifier: Identifier,
        string: String,
        int: Int,
        float: Float,
        boolean: Boolean,
        array: Array,
        map: Map,
        unary_operation: UnaryOperation,
        binary_operation: BinaryOperation,
        assignment: Assignment,
        subscript: Subscript,
        call: Call,

        pub const None = struct {
            source_loc: SourceLoc,
        };

        pub const Identifier = struct {
            name: Name,
        };

        pub const String = struct {
            content: []const u8,
            source_loc: SourceLoc,
        };

        pub const Int = struct {
            value: i64,
            source_loc: SourceLoc,
        };

        pub const Float = struct {
            value: f64,
            source_loc: SourceLoc,
        };

        pub const Boolean = struct {
            value: bool,
            source_loc: SourceLoc,
        };

        pub const Array = struct {
            values: []Expr,
        };

        pub const Map = struct {
            keys: []Expr,
            values: []Expr,
        };

        pub const UnaryOperation = struct {
            operator: UnaryOperator,
            rhs: *Expr,
            source_loc: SourceLoc,

            pub const UnaryOperator = enum {
                minus,
                bang,
            };
        };

        pub const BinaryOperation = struct {
            lhs: *Expr,
            operator: BinaryOperator,
            rhs: *Expr,
            source_loc: SourceLoc,

            pub const BinaryOperator = enum {
                plus,
                minus,
                forward_slash,
                star,
                double_star,
                percent,
                bang_equal_sign,
                double_equal_sign,
                less_than,
                greater_than,
            };
        };

        pub const Assignment = struct {
            target: *Expr,
            operator: AssignmentOperator,
            value: *Expr,
            source_loc: SourceLoc,

            const AssignmentOperator = enum {
                none,
                plus,
                minus,
                forward_slash,
                star,
                double_star,
                percent,
            };
        };

        pub const Subscript = struct {
            target: *Expr,
            index: *Expr,
            source_loc: SourceLoc,
        };

        pub const Call = struct {
            callable: *Expr,
            arguments: []Expr,
            source_loc: SourceLoc,
        };
    };
};

pub const Parser = struct {
    buffer: [:0]const u8,

    tokens: []Token,
    current_token_index: usize,

    error_info: ?ErrorInfo = null,

    gpa: std.mem.Allocator,

    pub const Error = error{
        UnexpectedToken,
        InvalidNumber,
    } || std.mem.Allocator.Error;

    pub const ErrorInfo = struct {
        message: []const u8,
        source_loc: SourceLoc,
    };

    pub fn init(gpa: std.mem.Allocator, buffer: [:0]const u8) std.mem.Allocator.Error!Parser {
        var tokens = std.ArrayList(Token).init(gpa);

        var lexer = Lexer.init(buffer);

        while (true) {
            const token = lexer.next();

            try tokens.append(token);

            if (token.tag == .eof) break;
        }

        return Parser{ .buffer = buffer, .tokens = try tokens.toOwnedSlice(), .current_token_index = 0, .gpa = gpa };
    }

    fn nextToken(self: *Parser) Token {
        self.current_token_index += 1;

        return self.tokens[self.current_token_index - 1];
    }

    fn peekToken(self: Parser) Token {
        return self.tokens[self.current_token_index];
    }

    fn eatToken(self: *Parser, tag: Token.Tag) bool {
        if (self.peekToken().tag == tag) {
            _ = self.nextToken();

            return true;
        } else {
            return false;
        }
    }

    fn tokenValue(self: Parser, token: Token) []const u8 {
        return self.buffer[token.buffer_loc.start..token.buffer_loc.end];
    }

    fn tokenSourceLoc(self: Parser, token: Token) SourceLoc {
        var source_loc: SourceLoc = .{};

        for (0..self.buffer.len) |i| {
            if (i == token.buffer_loc.start) break;

            switch (self.buffer[i]) {
                0 => break,

                '\n' => {
                    source_loc.line += 1;
                    source_loc.column = 1;
                },

                else => source_loc.column += 1,
            }
        }

        return source_loc;
    }

    fn parseName(self: *Parser) Error!Name {
        if (self.peekToken().tag != .identifier) {
            self.error_info = .{ .message = "expected a name", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        const token = self.nextToken();

        return Name{ .buffer = self.tokenValue(token), .source_loc = self.tokenSourceLoc(token) };
    }

    pub fn parseRoot(self: *Parser) Error!Root {
        var body = std.ArrayList(Node).init(self.gpa);

        while (self.peekToken().tag != .eof) {
            try body.append(try self.parseStmt());
        }

        return Root{ .body = try body.toOwnedSlice() };
    }

    fn parseStmt(self: *Parser) Error!Node {
        return switch (self.peekToken().tag) {
            .keyword_fn => self.parseFunctionDeclarationStmt(),

            .keyword_if => self.parseConditionalStmt(),

            .keyword_while => self.parseWhileLoopStmt(),

            .keyword_break => self.parseBreakStmt(),

            .keyword_continue => self.parseContinueStmt(),

            .keyword_return => self.parseReturnStmt(),

            else => {
                const expr = self.parseExpr(.lowest);

                return expr;
            },
        };
    }

    fn parseFunctionDeclarationStmt(self: *Parser) Error!Node {
        _ = self.nextToken();

        const name = try self.parseName();

        const parameters = try self.parseFunctionParameters();

        const body = try self.parseBody();

        return Node{ .stmt = .{ .function_declaration = .{ .name = name, .parameters = parameters, .body = body } } };
    }

    fn parseFunctionParameters(self: *Parser) Error![]Name {
        var parameters = std.ArrayList(Name).init(self.gpa);

        if (!self.eatToken(.open_paren)) {
            self.error_info = .{ .message = "expected a '('", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        while (self.peekToken().tag != .eof and self.peekToken().tag != .close_paren) {
            try parameters.append(try self.parseName());

            if (!self.eatToken(.comma) and self.peekToken().tag != .close_paren) {
                self.error_info = .{ .message = "expected a ','", .source_loc = self.tokenSourceLoc(self.peekToken()) };

                return error.UnexpectedToken;
            }
        }

        if (!self.eatToken(.close_paren)) {
            self.error_info = .{ .message = "expected a ')'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        return try parameters.toOwnedSlice();
    }

    fn parseBody(self: *Parser) Error![]Node {
        var body = std.ArrayList(Node).init(self.gpa);

        if (!self.eatToken(.open_brace)) {
            self.error_info = .{ .message = "expected a '{'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        while (self.peekToken().tag != .eof and self.peekToken().tag != .close_brace) {
            try body.append(try self.parseStmt());
        }

        if (!self.eatToken(.close_brace)) {
            self.error_info = .{ .message = "expected a '}'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        return try body.toOwnedSlice();
    }

    fn parseConditionalStmt(self: *Parser) Error!Node {
        var conditions = std.ArrayList(Node.Expr).init(self.gpa);
        var possiblities = std.ArrayList([]Node).init(self.gpa);

        while (self.peekToken().tag == .keyword_if) {
            _ = self.nextToken();

            const condition = (try self.parseExpr(.lowest)).expr;
            const possibility = try self.parseBody();
            try conditions.append(condition);
            try possiblities.append(possibility);

            if (self.eatToken(.keyword_else)) {
                if (self.peekToken().tag == .keyword_if) continue;

                const fallback = try self.parseBody();

                return Node{ .stmt = .{ .conditional = .{ .conditions = try conditions.toOwnedSlice(), .possiblities = try possiblities.toOwnedSlice(), .fallback = fallback } } };
            }

            break;
        }

        return Node{ .stmt = .{ .conditional = .{ .conditions = try conditions.toOwnedSlice(), .possiblities = try possiblities.toOwnedSlice(), .fallback = &.{} } } };
    }

    fn parseWhileLoopStmt(self: *Parser) Error!Node {
        _ = self.nextToken();

        const condition = (try self.parseExpr(.lowest)).expr;
        const body = try self.parseBody();

        return Node{ .stmt = .{ .while_loop = .{ .condition = condition, .body = body } } };
    }

    fn parseBreakStmt(self: *Parser) Error!Node {
        const break_token = self.nextToken();

        return Node{ .stmt = .{ .@"break" = .{ .source_loc = self.tokenSourceLoc(break_token) } } };
    }

    fn parseContinueStmt(self: *Parser) Error!Node {
        const continue_token = self.nextToken();

        return Node{ .stmt = .{ .@"continue" = .{ .source_loc = self.tokenSourceLoc(continue_token) } } };
    }

    fn parseReturnStmt(self: *Parser) Error!Node {
        const return_token = self.nextToken();

        const value = (try self.parseExpr(.lowest)).expr;

        return Node{ .stmt = .{ .@"return" = .{ .value = value, .source_loc = self.tokenSourceLoc(return_token) } } };
    }

    const Precedence = enum {
        lowest,
        assign,
        comparison,
        sum,
        product,
        exponent,
        prefix,
        call,
        subscript,

        fn from(token: Token) Precedence {
            return switch (token.tag) {
                .plus_equal_sign, .minus_equal_sign, .forward_slash_equal_sign, .star_equal_sign, .double_star_equal_sign, .percent_equal_sign, .equal_sign => .assign,

                .bang_equal_sign, .double_equal_sign, .greater_than, .less_than => .comparison,

                .plus, .minus => .sum,

                .forward_slash, .star, .percent => .product,

                .double_star => .exponent,

                .open_paren => .call,

                .open_bracket, .period => .subscript,

                else => .lowest,
            };
        }
    };

    fn parseExpr(self: *Parser, precedence: Precedence) Error!Node {
        var lhs = try self.parseUnaryExpr();

        while (@intFromEnum(Precedence.from(self.peekToken())) > @intFromEnum(precedence)) {
            lhs = try self.parseBinaryExpr(lhs);
        }

        return Node{ .expr = lhs };
    }

    fn parseUnaryExpr(self: *Parser) Error!Node.Expr {
        switch (self.peekToken().tag) {
            .keyword_none => return self.parseNoneExpr(),

            .identifier => return self.parseIdentifierExpr(),

            .string_literal => return self.parseStringExpr(),

            .int => return self.parseIntExpr(),

            .float => return self.parseFloatExpr(),

            .keyword_true => return self.parseBooleanExpr(),
            .keyword_false => return self.parseBooleanExpr(),

            .minus => return self.parseUnaryOperationExpr(.minus),
            .bang => return self.parseUnaryOperationExpr(.bang),

            .open_paren => return self.parseParenthesesExpr(),

            .open_bracket => return self.parseArrayExpr(),

            .open_brace => return self.parseMapExpr(),

            else => {
                self.error_info = .{ .message = "unexpected token", .source_loc = self.tokenSourceLoc(self.peekToken()) };

                return error.UnexpectedToken;
            },
        }
    }

    fn parseNoneExpr(self: *Parser) Node.Expr {
        return Node.Expr{ .none = .{ .source_loc = self.tokenSourceLoc(self.nextToken()) } };
    }

    fn parseIdentifierExpr(self: *Parser) Error!Node.Expr {
        return Node.Expr{ .identifier = .{ .name = try self.parseName() } };
    }

    fn parseStringExpr(self: *Parser) Node.Expr {
        return Node.Expr{ .string = .{ .content = self.tokenValue(self.peekToken()), .source_loc = self.tokenSourceLoc(self.nextToken()) } };
    }

    fn parseIntExpr(self: *Parser) Error!Node.Expr {
        const value = std.fmt.parseInt(i64, self.tokenValue(self.peekToken()), 10) catch {
            self.error_info = .{ .message = "invalid number", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.InvalidNumber;
        };

        return Node.Expr{ .int = .{ .value = value, .source_loc = self.tokenSourceLoc(self.nextToken()) } };
    }

    fn parseFloatExpr(self: *Parser) Error!Node.Expr {
        const value = std.fmt.parseFloat(f64, self.tokenValue(self.peekToken())) catch {
            self.error_info = .{ .message = "invalid number", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.InvalidNumber;
        };

        return Node.Expr{ .float = .{ .value = value, .source_loc = self.tokenSourceLoc(self.nextToken()) } };
    }

    fn parseBooleanExpr(self: *Parser) Node.Expr {
        return switch (self.peekToken().tag) {
            .keyword_true => Node.Expr{ .boolean = .{ .value = true, .source_loc = self.tokenSourceLoc(self.nextToken()) } },
            .keyword_false => Node.Expr{ .boolean = .{ .value = false, .source_loc = self.tokenSourceLoc(self.nextToken()) } },
            else => unreachable,
        };
    }

    fn parseParenthesesExpr(self: *Parser) Error!Node.Expr {
        _ = self.nextToken();

        const value = (try self.parseExpr(.lowest)).expr;

        if (!self.eatToken(.close_paren)) {
            self.error_info = .{ .message = "expected a ')'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        return value;
    }

    fn parseArrayExpr(self: *Parser) Error!Node.Expr {
        _ = self.nextToken();

        var values = std.ArrayList(Node.Expr).init(self.gpa);

        while (self.peekToken().tag != .eof and self.peekToken().tag != .close_bracket) {
            try values.append((try self.parseExpr(.lowest)).expr);

            if (!self.eatToken(.comma) and self.peekToken().tag != .close_bracket) {
                self.error_info = .{ .message = "expected a ','", .source_loc = self.tokenSourceLoc(self.peekToken()) };

                return error.UnexpectedToken;
            }
        }

        if (!self.eatToken(.close_bracket)) {
            self.error_info = .{ .message = "expected a ']'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        return Node.Expr{ .array = .{ .values = try values.toOwnedSlice() } };
    }

    fn parseMapExpr(self: *Parser) Error!Node.Expr {
        _ = self.nextToken();

        var keys = std.ArrayList(Node.Expr).init(self.gpa);
        var values = std.ArrayList(Node.Expr).init(self.gpa);

        while (self.peekToken().tag != .eof and self.peekToken().tag != .close_brace) {
            try keys.append((try self.parseExpr(.lowest)).expr);

            if (!self.eatToken(.colon)) {
                self.error_info = .{ .message = "expected a ':'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

                return error.UnexpectedToken;
            }

            try values.append((try self.parseExpr(.lowest)).expr);

            if (!self.eatToken(.comma) and self.peekToken().tag != .close_brace) {
                self.error_info = .{ .message = "expected a ','", .source_loc = self.tokenSourceLoc(self.peekToken()) };

                return error.UnexpectedToken;
            }
        }

        if (!self.eatToken(.close_brace)) {
            self.error_info = .{ .message = "expected a '}'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        return Node.Expr{ .map = .{ .keys = try keys.toOwnedSlice(), .values = try values.toOwnedSlice() } };
    }

    fn parseUnaryOperationExpr(self: *Parser, operator: Node.Expr.UnaryOperation.UnaryOperator) Error!Node.Expr {
        const operator_token = self.nextToken();

        const rhs = (try self.parseExpr(.prefix)).expr;
        var rhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        rhs_on_heap[0] = rhs;

        return Node.Expr{ .unary_operation = .{ .operator = operator, .rhs = &rhs_on_heap[0], .source_loc = self.tokenSourceLoc(operator_token) } };
    }

    fn parseBinaryExpr(self: *Parser, lhs: Node.Expr) Error!Node.Expr {
        switch (self.peekToken().tag) {
            .plus => return self.parseBinaryOperationExpr(lhs, .plus),
            .minus => return self.parseBinaryOperationExpr(lhs, .minus),
            .forward_slash => return self.parseBinaryOperationExpr(lhs, .forward_slash),
            .star => return self.parseBinaryOperationExpr(lhs, .star),
            .double_star => return self.parseBinaryOperationExpr(lhs, .double_star),
            .percent => return self.parseBinaryOperationExpr(lhs, .percent),
            .bang_equal_sign => return self.parseBinaryOperationExpr(lhs, .bang_equal_sign),
            .double_equal_sign => return self.parseBinaryOperationExpr(lhs, .double_equal_sign),
            .less_than => return self.parseBinaryOperationExpr(lhs, .less_than),
            .greater_than => return self.parseBinaryOperationExpr(lhs, .greater_than),

            .equal_sign => return self.parseAssignmentExpr(lhs, .none),
            .plus_equal_sign => return self.parseAssignmentExpr(lhs, .plus),
            .minus_equal_sign => return self.parseAssignmentExpr(lhs, .minus),
            .forward_slash_equal_sign => return self.parseAssignmentExpr(lhs, .forward_slash),
            .star_equal_sign => return self.parseAssignmentExpr(lhs, .star),
            .double_star_equal_sign => return self.parseAssignmentExpr(lhs, .double_star),
            .percent_equal_sign => return self.parseAssignmentExpr(lhs, .percent),

            .open_paren => return self.parseCallExpr(lhs),

            .open_bracket => return self.parseBracketSubscriptExpr(lhs),

            .period => return self.parsePeriodSubscriptExpr(lhs),

            else => {
                self.error_info = .{ .message = "unexpected token", .source_loc = self.tokenSourceLoc(self.peekToken()) };

                return error.UnexpectedToken;
            },
        }
    }

    fn parseBinaryOperationExpr(self: *Parser, lhs: Node.Expr, operator: Node.Expr.BinaryOperation.BinaryOperator) Error!Node.Expr {
        var lhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        lhs_on_heap[0] = lhs;

        const operator_token = self.nextToken();

        const rhs = (try self.parseExpr(Precedence.from(operator_token))).expr;
        var rhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        rhs_on_heap[0] = rhs;

        return Node.Expr{ .binary_operation = .{ .lhs = &lhs_on_heap[0], .operator = operator, .rhs = &rhs_on_heap[0], .source_loc = self.tokenSourceLoc(operator_token) } };
    }

    fn parseAssignmentExpr(self: *Parser, lhs: Node.Expr, operator: Node.Expr.Assignment.AssignmentOperator) Error!Node.Expr {
        var lhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        lhs_on_heap[0] = lhs;

        const equal_sign_token = self.nextToken();

        const rhs = (try self.parseExpr(.lowest)).expr;
        var rhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        rhs_on_heap[0] = rhs;

        return Node.Expr{ .assignment = .{ .target = &lhs_on_heap[0], .operator = operator, .value = &rhs_on_heap[0], .source_loc = self.tokenSourceLoc(equal_sign_token) } };
    }

    fn parseBracketSubscriptExpr(self: *Parser, lhs: Node.Expr) Error!Node.Expr {
        var lhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        lhs_on_heap[0] = lhs;

        const open_bracket_token = self.nextToken();

        const rhs = (try self.parseExpr(.lowest)).expr;
        var rhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        rhs_on_heap[0] = rhs;

        if (!self.eatToken(.close_bracket)) {
            self.error_info = .{ .message = "expected a ']'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        return Node.Expr{ .subscript = .{ .target = &lhs_on_heap[0], .index = &rhs_on_heap[0], .source_loc = self.tokenSourceLoc(open_bracket_token) } };
    }

    fn parsePeriodSubscriptExpr(self: *Parser, lhs: Node.Expr) Error!Node.Expr {
        var lhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        lhs_on_heap[0] = lhs;

        const period_token = self.nextToken();

        if (self.peekToken().tag != .identifier) {
            self.error_info = .{ .message = "expected a name", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        const name_token = self.nextToken();

        const rhs: Node.Expr = .{ .string = .{ .content = self.tokenValue(name_token), .source_loc = self.tokenSourceLoc(name_token) } };

        var rhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        rhs_on_heap[0] = rhs;

        return Node.Expr{ .subscript = .{ .target = &lhs_on_heap[0], .index = &rhs_on_heap[0], .source_loc = self.tokenSourceLoc(period_token) } };
    }

    fn parseCallExpr(self: *Parser, lhs: Node.Expr) Error!Node.Expr {
        var lhs_on_heap = try self.gpa.alloc(Node.Expr, 1);
        lhs_on_heap[0] = lhs;

        const open_paren_token = self.nextToken();

        const arguments = try self.parseCallArguments();

        return Node.Expr{ .call = .{ .callable = &lhs_on_heap[0], .arguments = arguments, .source_loc = self.tokenSourceLoc(open_paren_token) } };
    }

    fn parseCallArguments(self: *Parser) Error![]Node.Expr {
        var arguments = std.ArrayList(Node.Expr).init(self.gpa);

        while (self.peekToken().tag != .eof and self.peekToken().tag != .close_paren) {
            try arguments.append((try self.parseExpr(.lowest)).expr);

            if (!self.eatToken(.comma) and self.peekToken().tag != .close_paren) {
                self.error_info = .{ .message = "expected a ','", .source_loc = self.tokenSourceLoc(self.peekToken()) };

                return error.UnexpectedToken;
            }
        }

        if (!self.eatToken(.close_paren)) {
            self.error_info = .{ .message = "expected a ')'", .source_loc = self.tokenSourceLoc(self.peekToken()) };

            return error.UnexpectedToken;
        }

        return arguments.toOwnedSlice();
    }
};
