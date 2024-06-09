const std = @import("std");

const SourceLoc = @import("../compiler/ast.zig").SourceLoc;

const VirtualMachine = @This();

gpa: std.mem.Allocator,

frames: std.ArrayList(Frame),

stack: std.ArrayList(Code.Value),

globals: std.StringHashMap(Code.Value),

start_time: std.time.Instant,

error_info: ?ErrorInfo = null,

pub const Error = error{
    BadOperand,
    UndefinedName,
    UnexpectedValue,
    DivisionByZero,
    NegativeDenominator,
    IndexOverflow,
    StackOverflow,
    Unsupported,
} || std.mem.Allocator.Error;

pub const ErrorInfo = struct {
    message: []const u8,
    source_loc: SourceLoc,
};

pub const MAX_FRAMES_COUNT = 64;
pub const MAX_STACK_SIZE = MAX_FRAMES_COUNT * 1024;

pub const Frame = struct {
    function: *Code.Value.Object.Function,
    locals: std.StringHashMap(usize),
    ip: usize = 0,
    stack_start: usize = 0,
};

pub const Code = struct {
    constants: std.ArrayList(Value),
    instructions: std.ArrayList(Instruction),
    source_locations: std.ArrayList(SourceLoc),

    pub const Value = union(enum) {
        none: void,
        int: i64,
        float: f64,
        boolean: bool,
        object: Object,

        pub const Object = union(enum) {
            string: String,
            array: *Array,
            function: *Function,
            native_function: NativeFunction,

            pub const String = struct {
                content: []const u8,
            };

            pub const Array = struct {
                values: std.ArrayList(Value),
            };

            pub const Function = struct {
                name: []const u8,
                parameters: []const []const u8,
                code: Code,
            };

            pub const NativeFunction = struct {
                name: []const u8,
                required_arguments_count: ?usize,
                call: *const fn (*VirtualMachine, []const Value) Value,
            };
        };

        pub fn is_truthy(self: Value) bool {
            return switch (self) {
                .none => false,
                .int => self.int != 0,
                .float => self.float != 0.0,
                .boolean => self.boolean,
                .object => switch (self.object) {
                    .string => self.object.string.content.len != 0,
                    .array => self.object.array.values.items.len != 0,
                    else => true,
                },
            };
        }

        pub fn eql(lhs: Value, rhs: Value, strict: bool) bool {
            if (lhs.is_truthy() != rhs.is_truthy()) {
                return false;
            }

            switch (lhs) {
                .none => return rhs == .none,

                .int => return (rhs == .int and lhs.int == rhs.int) or (!strict and rhs == .float and @as(f64, @floatFromInt(lhs.int)) == rhs.float),
                .float => return (rhs == .float and lhs.float == rhs.float) or (!strict and rhs == .int and lhs.float == @as(f64, @floatFromInt(rhs.int))),
                .boolean => return rhs == .boolean and lhs.boolean == rhs.boolean,

                .object => switch (lhs.object) {
                    .string => return rhs == .object and rhs.object == .string and std.mem.eql(u8, lhs.object.string.content, rhs.object.string.content),

                    .array => {
                        if (!(rhs == .object and rhs.object == .array and lhs.object.array.values.items.len == rhs.object.array.values.items.len)) {
                            return false;
                        }

                        for (0..lhs.object.array.values.items.len) |i| {
                            if (lhs.object.array.values.items[i] == .object and lhs.object.array.values.items[i].object == .array and lhs.object.array.values.items[i].object.array == lhs.object.array) {
                                if (!(rhs.object.array.values.items[i] == .object and rhs.object.array.values.items[i].object == .array and rhs.object.array.values.items[i].object.array == lhs.object.array)) {
                                    return false;
                                }
                            } else if (!lhs.object.array.values.items[i].eql(rhs.object.array.values.items[i], false)) {
                                return false;
                            }
                        }
                    },

                    // Comparing with pointers instead of checking everything is used here because when you do "function == other_function" you are just comparing function pointers
                    .function => return rhs == .object and rhs.object == .function and lhs.object.function == rhs.object.function,
                    .native_function => return rhs == .object and rhs.object == .native_function and lhs.object.native_function.call == rhs.object.native_function.call,
                },
            }

            return true;
        }
    };

    pub const Instruction = union(enum) {
        load: Load,
        store: Store,
        jump: Jump,
        jump_if_false: JumpIfFalse,
        back: Back,
        make: Make,
        neg: void,
        not: void,
        add: void,
        subtract: void,
        divide: void,
        multiply: void,
        exponent: void,
        modulo: void,
        not_equals: void,
        equals: void,
        less_than: void,
        greater_than: void,
        call: Call,
        pop: void,
        @"return": void,

        pub const Load = union(enum) {
            constant: usize,
            name: []const u8,
            subscript: void,
        };

        pub const Store = union(enum) {
            name: []const u8,
            subscript: void,
        };

        pub const Jump = struct {
            offset: usize,
        };

        pub const JumpIfFalse = struct {
            offset: usize,
        };

        pub const Back = struct {
            offset: usize,
        };

        pub const Make = union(enum) {
            array: Array,

            pub const Array = struct {
                length: usize,
            };
        };

        pub const Call = struct {
            arguments_count: usize,
        };
    };

    pub fn addConstant(self: *Code, value: Value) std.mem.Allocator.Error!usize {
        for (self.constants.items, 0..) |constant, i| {
            if (constant.eql(value, true)) {
                return i;
            }
        }

        try self.constants.append(value);

        return self.constants.items.len - 1;
    }
};

pub fn init(gpa: std.mem.Allocator) Error!VirtualMachine {
    return VirtualMachine{ .gpa = gpa, .frames = try std.ArrayList(Frame).initCapacity(gpa, MAX_FRAMES_COUNT), .stack = try std.ArrayList(Code.Value).initCapacity(gpa, MAX_STACK_SIZE), .globals = std.StringHashMap(Code.Value).init(gpa), .start_time = try std.time.Instant.now() };
}

pub fn addGlobals(self: *VirtualMachine) std.mem.Allocator.Error!void {
    const Array = @import("./builtins/Array.zig");
    const Console = @import("./builtins/Console.zig");
    const Process = @import("./builtins/Process.zig");
    const Random = @import("./builtins/Random.zig");
    const Time = @import("./builtins/Time.zig");
    const Type = @import("./builtins/Type.zig");

    try Array.addGlobals(self);
    try Console.addGlobals(self);
    try Process.addGlobals(self);
    try Random.addGlobals(self);
    try Time.addGlobals(self);
    try Type.addGlobals(self);
}

pub fn setCode(self: *VirtualMachine, code: Code) std.mem.Allocator.Error!void {
    if (self.frames.items.len == 0) {
        var function_on_heap = try self.gpa.alloc(Code.Value.Object.Function, 1);
        function_on_heap[0] = .{ .name = "", .parameters = &.{}, .code = code };

        try self.frames.append(.{ .function = &function_on_heap[0], .locals = std.StringHashMap(usize).init(self.gpa) });
    } else {
        self.frames.items[0].function.code = code;
        self.frames.items[0].ip = 0;
    }
}

pub fn run(self: *VirtualMachine) Error!Code.Value {
    const frame = &self.frames.items[self.frames.items.len - 1];

    while (true) {
        if (self.stack.items.len >= MAX_STACK_SIZE or self.frames.items.len >= MAX_FRAMES_COUNT) {
            return error.StackOverflow;
        }

        const instruction = frame.function.code.instructions.items[frame.ip];
        const source_loc = frame.function.code.source_locations.items[frame.ip];

        frame.ip += 1;

        switch (instruction) {
            .load => try self.load(instruction.load, source_loc, frame),

            .store => try self.store(instruction.store, source_loc, frame),

            .jump => {
                const info = instruction.jump;

                frame.ip += info.offset;
            },

            .jump_if_false => {
                const value = self.stack.pop();

                if (!value.is_truthy()) {
                    const info = instruction.jump_if_false;

                    frame.ip += info.offset;
                }
            },

            .back => {
                const info = instruction.back;

                frame.ip -= info.offset;
            },

            .make => try self.make(instruction.make),

            .neg => try self.neg(source_loc),
            .not => try self.not(),

            .add => try self.add(source_loc),
            .subtract => try self.subtract(source_loc),
            .divide => try self.divide(source_loc),
            .multiply => try self.multiply(source_loc),
            .exponent => try self.exponent(source_loc),
            .modulo => try self.modulo(source_loc),
            .not_equals => try self.not_equals(),
            .equals => try self.equals(),
            .less_than => try self.less_than(source_loc),
            .greater_than => try self.greater_than(source_loc),

            .call => try self.call(instruction.call, source_loc, frame),

            .pop => {
                _ = self.stack.pop();
            },

            .@"return" => {
                return self.stack.pop();
            },
        }
    }
}

fn load(self: *VirtualMachine, info: Code.Instruction.Load, source_loc: SourceLoc, frame: *Frame) Error!void {
    switch (info) {
        .constant => {
            try self.stack.append(frame.function.code.constants.items[info.constant]);
        },

        .name => {
            const value = blk: {
                if (frame.locals.contains(info.name)) {
                    const stack_index = frame.locals.get(info.name).?;

                    break :blk self.stack.items[stack_index];
                } else if (self.globals.contains(info.name)) {
                    break :blk self.globals.get(info.name).?;
                } else {
                    var error_message_buf = std.ArrayList(u8).init(self.gpa);

                    try error_message_buf.writer().print("undefined name '{s}'", .{info.name});

                    self.error_info = .{ .message = try error_message_buf.toOwnedSlice(), .source_loc = source_loc };

                    return error.UndefinedName;
                }
            };

            try self.stack.append(value);
        },

        .subscript => {
            var index = self.stack.pop();
            const target = self.stack.pop();

            if (index != .int) {
                self.error_info = .{ .message = "index is not an integer", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            if (target != .object and target.object != .array) {
                self.error_info = .{ .message = "target is not an array", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            if (index.int < 0) {
                index.int += @as(i64, @intCast(target.object.array.values.items.len));
            }

            if (index.int < 0 or index.int >= @as(i64, @intCast(target.object.array.values.items.len))) {
                self.error_info = .{ .message = "index overflow", .source_loc = source_loc };

                return error.IndexOverflow;
            }

            try self.stack.append(target.object.array.values.items[@as(usize, @intCast(index.int))]);
        },
    }
}

fn store(self: *VirtualMachine, info: Code.Instruction.Store, source_loc: SourceLoc, frame: *Frame) Error!void {
    const value = self.stack.pop();

    switch (info) {
        .name => {
            if (frame.locals.contains(info.name) and frame.locals.get(info.name).? >= frame.stack_start) {
                const stack_index = frame.locals.get(info.name).?;

                self.stack.items[stack_index] = value;
            } else {
                const stack_index = self.stack.items.len;
                try self.stack.append(value);

                try frame.locals.put(info.name, stack_index);
            }
        },

        .subscript => {
            var index = self.stack.pop();
            const target = self.stack.pop();

            if (index != .int) {
                self.error_info = .{ .message = "index is not an integer", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            if (target != .object and target.object != .array) {
                self.error_info = .{ .message = "target is not an array", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            if (index.int < 0) {
                index.int += @as(i64, @intCast(target.object.array.values.items.len));
            }

            if (index.int < 0 or index.int >= @as(i64, @intCast(target.object.array.values.items.len))) {
                self.error_info = .{ .message = "index overflow", .source_loc = source_loc };

                return error.IndexOverflow;
            }

            target.object.array.values.items[@as(usize, @intCast(index.int))] = value;
        },
    }
}

fn make(self: *VirtualMachine, info: Code.Instruction.Make) Error!void {
    switch (info) {
        .array => {
            var values = std.ArrayList(Code.Value).init(self.gpa);

            for (0..info.array.length) |_| {
                const value = self.stack.pop();

                try values.insert(0, value);
            }

            const array: Code.Value.Object.Array = .{ .values = values };

            var array_on_heap = try self.gpa.alloc(Code.Value.Object.Array, 1);
            array_on_heap[0] = array;

            try self.stack.append(.{ .object = .{ .array = &array_on_heap[0] } });
        },
    }
}

fn neg(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();

    switch (rhs) {
        .int => return self.stack.append(.{ .int = -rhs.int }),
        .float => return self.stack.append(.{ .float = -rhs.float }),
        .boolean => return self.stack.append(.{ .int = -@as(i64, @intCast(@intFromBool(rhs.boolean))) }),

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '-' unary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn not(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();

    try self.stack.append(.{ .boolean = !rhs.is_truthy() });
}

fn add(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => switch (rhs) {
            .int => return self.stack.append(.{ .int = lhs.int + rhs.int }),
            .float => return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs.int)) + rhs.float }),
            .boolean => return self.stack.append(.{ .int = lhs.int + @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .float => switch (rhs) {
            .int => return self.stack.append(.{ .float = lhs.float + @as(f64, @floatFromInt(rhs.int)) }),
            .float => return self.stack.append(.{ .float = lhs.float + rhs.float }),
            .boolean => return self.stack.append(.{ .float = lhs.float + @as(f64, @floatFromInt(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .boolean => switch (rhs) {
            .int => return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs.boolean))) + rhs.int }),
            .float => return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) + rhs.float }),
            .boolean => return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs.boolean))) + @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .object => switch (lhs.object) {
            .string => switch (rhs) {
                .object => switch (rhs.object) {
                    .string => {
                        const concatenated_string: Code.Value = .{ .object = .{ .string = .{ .content = try std.mem.concat(self.gpa, u8, &.{ lhs.object.string.content, rhs.object.string.content }) } } };

                        return self.stack.append(concatenated_string);
                    },

                    else => {},
                },

                else => {},
            },

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '+' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn subtract(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => switch (rhs) {
            .int => return self.stack.append(.{ .int = lhs.int - rhs.int }),
            .float => return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs.int)) - rhs.float }),
            .boolean => return self.stack.append(.{ .int = lhs.int - @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .float => switch (rhs) {
            .int => return self.stack.append(.{ .float = lhs.float - @as(f64, @floatFromInt(rhs.int)) }),
            .float => return self.stack.append(.{ .float = lhs.float - rhs.float }),
            .boolean => return self.stack.append(.{ .float = lhs.float - @as(f64, @floatFromInt(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .boolean => switch (rhs) {
            .int => return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs.boolean))) - rhs.int }),
            .float => return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) - rhs.float }),
            .boolean => return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs.boolean))) - @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '-' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn divide(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => switch (rhs) {
            .int => return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs.int)) / @as(f64, @floatFromInt(rhs.int)) }),
            .float => return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs.int)) / rhs.float }),
            .boolean => return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs.int)) / @as(f64, @floatFromInt(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .float => switch (rhs) {
            .int => return self.stack.append(.{ .float = lhs.float / @as(f64, @floatFromInt(rhs.int)) }),
            .float => return self.stack.append(.{ .float = lhs.float / rhs.float }),
            .boolean => return self.stack.append(.{ .float = lhs.float / @as(f64, @floatFromInt(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .boolean => switch (rhs) {
            .int => return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(rhs.boolean))) / @as(f64, @floatFromInt(rhs.int)) }),
            .float => return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) / rhs.float }),
            .boolean => return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) / @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '/' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn multiply(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => switch (rhs) {
            .int => return self.stack.append(.{ .int = lhs.int * rhs.int }),
            .float => return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs.int)) * rhs.float }),
            .boolean => return self.stack.append(.{ .int = lhs.int * @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .float => switch (rhs) {
            .int => return self.stack.append(.{ .float = lhs.float * @as(f64, @floatFromInt(rhs.int)) }),
            .float => return self.stack.append(.{ .float = lhs.float * rhs.float }),
            .boolean => return self.stack.append(.{ .float = lhs.float * @as(f64, @floatFromInt(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .boolean => switch (rhs) {
            .int => return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs.boolean))) * rhs.int }),
            .float => return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) * rhs.float }),
            .boolean => return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs.boolean))) * @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '*' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn exponent(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => switch (rhs) {
            .int => return self.stack.append(.{ .float = std.math.pow(f64, @as(f64, @floatFromInt(lhs.int)), @as(f64, @floatFromInt(rhs.int))) }),
            .float => return self.stack.append(.{ .float = std.math.pow(f64, @as(f64, @floatFromInt(lhs.int)), rhs.float) }),
            .boolean => return self.stack.append(.{ .float = std.math.pow(f64, @as(f64, @floatFromInt(lhs.int)), @as(f64, @floatFromInt(@intFromBool(rhs.boolean)))) }),

            else => {},
        },

        .float => switch (rhs) {
            .int => return self.stack.append(.{ .float = std.math.pow(f64, lhs.float, @as(f64, @floatFromInt(rhs.int))) }),
            .float => return self.stack.append(.{ .float = std.math.pow(f64, lhs.float, rhs.float) }),
            .boolean => return self.stack.append(.{ .float = std.math.pow(f64, lhs.float, @as(f64, @floatFromInt(@intFromBool(rhs.boolean)))) }),

            else => {},
        },

        .boolean => switch (rhs) {
            .int => return self.stack.append(.{ .float = std.math.pow(f64, @as(f64, @floatFromInt(@intFromBool(lhs.boolean))), @as(f64, @floatFromInt(rhs.int))) }),
            .float => return self.stack.append(.{ .float = std.math.pow(f64, @as(f64, @floatFromInt(@intFromBool(lhs.boolean))), rhs.float) }),
            .boolean => return self.stack.append(.{ .float = std.math.pow(f64, @as(f64, @floatFromInt(@intFromBool(lhs.boolean))), @as(f64, @floatFromInt(@intFromBool(rhs.boolean)))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '**' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn modulo(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => switch (rhs) {
            .int => return self.stack.append(.{ .int = try std.math.mod(i64, lhs.int, rhs.int) }),
            .float => return self.stack.append(.{ .float = try std.math.mod(f64, @as(f64, @floatFromInt(lhs.int)), rhs.float) }),
            .boolean => return self.stack.append(.{ .int = try std.math.mod(i64, lhs.int, @as(i64, @intCast(@intFromBool(rhs.boolean)))) }),

            else => {},
        },

        .float => switch (rhs) {
            .int => return self.stack.append(.{ .float = try std.math.mod(f64, lhs.float, @as(f64, @floatFromInt(rhs.int))) }),
            .float => return self.stack.append(.{ .float = try std.math.mod(f64, lhs.float, rhs.float) }),
            .boolean => return self.stack.append(.{ .float = try std.math.mod(f64, lhs.float, @as(f64, @floatFromInt(@intFromBool(rhs.boolean)))) }),

            else => {},
        },

        .boolean => switch (rhs) {
            .int => return self.stack.append(.{ .int = try std.math.mod(i64, @as(i64, @intCast(@intFromBool(lhs.boolean))), rhs.int) }),
            .float => return self.stack.append(.{ .float = try std.math.mod(f64, @as(f64, @floatFromInt((@intFromBool(lhs.boolean)))), rhs.float) }),
            .boolean => return self.stack.append(.{ .int = try std.math.mod(i64, @as(i64, @intCast(@intFromBool(lhs.boolean))), @as(i64, @intCast(@intFromBool(rhs.boolean)))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '%' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn not_equals(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    return self.stack.append(.{ .boolean = !lhs.eql(rhs, false) });
}

fn equals(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    return self.stack.append(.{ .boolean = lhs.eql(rhs, false) });
}

fn less_than(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => switch (rhs) {
            .int => return self.stack.append(.{ .boolean = lhs.int < rhs.int }),
            .float => return self.stack.append(.{ .boolean = @as(f64, @floatFromInt(lhs.int)) < rhs.float }),
            .boolean => return self.stack.append(.{ .boolean = lhs.int < @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .float => switch (rhs) {
            .int => return self.stack.append(.{ .boolean = lhs.float < @as(f64, @floatFromInt(rhs.int)) }),
            .float => return self.stack.append(.{ .boolean = lhs.float < rhs.float }),
            .boolean => return self.stack.append(.{ .boolean = lhs.float < @as(f64, @floatFromInt(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .boolean => switch (rhs) {
            .int => return self.stack.append(.{ .boolean = @as(i64, @intCast(@intFromBool(lhs.boolean))) < rhs.int }),
            .float => return self.stack.append(.{ .boolean = @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) < rhs.float }),
            .boolean => return self.stack.append(.{ .boolean = @as(i64, @intCast(@intFromBool(lhs.boolean))) < @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '<' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn greater_than(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => switch (rhs) {
            .int => return self.stack.append(.{ .boolean = lhs.int > rhs.int }),
            .float => return self.stack.append(.{ .boolean = @as(f64, @floatFromInt(lhs.int)) > rhs.float }),
            .boolean => return self.stack.append(.{ .boolean = lhs.int > @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .float => switch (rhs) {
            .int => return self.stack.append(.{ .boolean = lhs.float > @as(f64, @floatFromInt(rhs.int)) }),
            .float => return self.stack.append(.{ .boolean = lhs.float > rhs.float }),
            .boolean => return self.stack.append(.{ .boolean = lhs.float > @as(f64, @floatFromInt(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        .boolean => switch (rhs) {
            .int => return self.stack.append(.{ .boolean = @as(i64, @intCast(@intFromBool(lhs.boolean))) > rhs.int }),
            .float => return self.stack.append(.{ .boolean = @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) > rhs.float }),
            .boolean => return self.stack.append(.{ .boolean = @as(i64, @intCast(@intFromBool(lhs.boolean))) > @as(i64, @intCast(@intFromBool(rhs.boolean))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '>' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn call(self: *VirtualMachine, info: Code.Instruction.Call, source_loc: SourceLoc, frame: *Frame) Error!void {
    const callable = self.stack.pop();

    var arguments = try std.ArrayList(Code.Value).initCapacity(self.gpa, info.arguments_count);

    for (0..info.arguments_count) |_| {
        try arguments.insert(0, self.stack.pop());
    }

    if (callable == .object) {
        switch (callable.object) {
            .function => {
                try self.checkArgumentsCount(callable.object.function.parameters.len, info.arguments_count, source_loc);

                const stack_start = self.stack.items.len;

                var locals = try frame.locals.clone();

                for (callable.object.function.parameters, 0..) |parameter, i| {
                    try self.stack.append(arguments.items[i]);
                    try locals.put(parameter, stack_start + i);
                }

                try self.frames.append(.{ .function = callable.object.function, .locals = locals, .stack_start = stack_start });

                const return_value = try self.run();

                self.stack.shrinkRetainingCapacity(stack_start);

                _ = self.frames.pop();

                return self.stack.append(return_value);
            },

            .native_function => {
                if (callable.object.native_function.required_arguments_count != null) {
                    try self.checkArgumentsCount(callable.object.native_function.required_arguments_count.?, info.arguments_count, source_loc);
                }

                const return_value = callable.object.native_function.call(self, arguments.items);

                return self.stack.append(return_value);
            },

            else => {},
        }
    }

    self.error_info = .{ .message = "not a callable", .source_loc = source_loc };

    return error.BadOperand;
}

fn checkArgumentsCount(self: *VirtualMachine, required_count: usize, arguments_count: usize, source_loc: SourceLoc) Error!void {
    if (required_count != arguments_count) {
        var error_message_buf = std.ArrayList(u8).init(self.gpa);

        const argument_or_arguments = blk: {
            if (arguments_count != 1) {
                break :blk "arguments";
            } else {
                break :blk "argument";
            }
        };

        try error_message_buf.writer().print("expected {} {s} got {}", .{ required_count, argument_or_arguments, arguments_count });

        self.error_info = .{ .message = try error_message_buf.toOwnedSlice(), .source_loc = source_loc };

        return error.UnexpectedValue;
    }
}
