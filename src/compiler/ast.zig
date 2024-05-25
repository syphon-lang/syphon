pub const SourceLoc = struct {
    line: usize,
    column: usize,
};

pub const Name = struct {
    buffer: []const u8,
    source_loc: SourceLoc,
};

pub const Root = struct {
    nodes: []const Node,
};

pub const Node = union(enum) {
    stmt: Stmt,
    expr: Expr,

    pub const Stmt = union(enum) {
        variable_declaration: VariableDeclaration,
        function_declaration: FunctionDeclaration,
        conditiional: Conditional,
        while_loop: WhileLoop,

        pub const VariableDeclaration = struct {
            name: Name,
            value: ?Expr,
        };

        pub const FunctionDeclaration = struct {
            name: Name,
            parameters: []const Name,
            nodes: []const Node,
        };

        pub const Conditional = struct {
            conditions: []const Expr,
            possiblities: []const []const Node,
            fallback: []const Node,
        };

        pub const WhileLoop = struct {
            condition: Expr,
            nodes: []const Node,
        };
    };

    pub const Expr = union(enum) {
        none: None,
        identifier: Identifier,
        string: String,
        int: Int,
        float: Float,
        array: Array,
        unary_operation: UnaryOperation,
        binary_operation: BinaryOperation,
        assignment: Assignment,
        array_subscript: ArraySubscript,
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

        pub const Array = struct {
            values: []const Expr,
        };

        pub const UnaryOperation = struct {
            operator: UnaryOperator,
            rhs: *Expr,

            pub const UnaryOperator = enum {
                minus,
                bang,
            };
        };

        pub const BinaryOperation = struct {
            lhs: *Expr,
            operator: BinaryOperator,
            rhs: *Expr,

            pub const BinaryOperator = enum {
                plus,
                minus,
                forward_slash,
                star,
                double_star,
            };
        };

        pub const Assignment = struct {
            target: *Expr,
            value: *Expr,
        };

        pub const ArraySubscript = struct {
            target: *Expr,
            index: *Expr,
        };

        pub const Call = struct {
            callable: *Expr,
            arguments: []const Expr,
        };
    };
};
