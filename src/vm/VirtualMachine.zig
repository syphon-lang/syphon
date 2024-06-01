const std = @import("std");

const SourceLoc = @import("../compiler/ast.zig").SourceLoc;
const GarbageCollector = @import("GarbageCollector.zig");

const VirtualMachine = @This();

gpa: std.mem.Allocator,

gc: *GarbageCollector,

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
                content: []u8,
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
                            if (!lhs.object.array.values.items[i].eql(rhs.object.array.values.items[i], false)) {
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

pub fn init(gpa: std.mem.Allocator, gc: *GarbageCollector) Error!VirtualMachine {
    return VirtualMachine{ .gpa = gpa, .gc = gc, .frames = try std.ArrayList(Frame).initCapacity(gpa, MAX_FRAMES_COUNT), .stack = try std.ArrayList(Code.Value).initCapacity(gpa, MAX_STACK_SIZE), .globals = std.StringHashMap(Code.Value).init(gpa), .start_time = try std.time.Instant.now() };
}

fn _print(buffered_writer: *std.io.BufferedWriter(4096, std.fs.File.Writer), arguments: []const Code.Value, debug: bool) !void {
    for (arguments, 0..) |argument, i| {
        switch (argument) {
            .none => {
                _ = try buffered_writer.write("none");
            },

            .int => try buffered_writer.writer().print("{d}", .{argument.int}),
            .float => try buffered_writer.writer().print("{d}", .{argument.float}),
            .boolean => try buffered_writer.writer().print("{}", .{argument.boolean}),

            .object => switch (argument.object) {
                .string => {
                    if (debug) {
                        try buffered_writer.writer().print("'{s}'", .{argument.object.string.content});
                    } else {
                        try buffered_writer.writer().print("{s}", .{argument.object.string.content});
                    }
                },

                .array => {
                    _ = try buffered_writer.write("[");

                    for (argument.object.array.values.items, 0..) |value, j| {
                        if (value == .object and value.object == .array and value.object.array == argument.object.array) {
                            _ = try buffered_writer.write("..");
                        } else {
                            try _print(buffered_writer, &.{value}, true);
                        }

                        if (j < argument.object.array.values.items.len - 1) {
                            _ = try buffered_writer.write(", ");
                        }
                    }

                    _ = try buffered_writer.write("]");
                },

                .function => try buffered_writer.writer().print("<function '{s}'>", .{argument.object.function.name}),

                .native_function => try buffered_writer.writer().print("<native function '{s}'>", .{argument.object.native_function.name}),
            },
        }

        if (i < arguments.len - 1) {
            _ = try buffered_writer.write(" ");
        }
    }
}

fn print(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = self;

    const stdout = std.io.getStdOut();
    var buffered_writer = std.io.bufferedWriter(stdout.writer());

    _print(&buffered_writer, arguments, false) catch |err| switch (err) {
        else => {
            std.debug.print("print native function: error occured while trying to print\n", .{});
        },
    };

    buffered_writer.flush() catch |err| switch (err) {
        else => {
            std.debug.print("print native function: error occured while trying to print\n", .{});
        },
    };

    return Code.Value{ .none = {} };
}

fn println(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const stdout = std.io.getStdOut();
    var buffered_writer = std.io.bufferedWriter(stdout.writer());

    const new_line_interned = self.gc.intern("\n") catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory\n", .{});
            std.process.exit(1);
        },
    };

    const new_line_value: Code.Value = .{ .object = .{ .string = .{ .content = new_line_interned } } };

    self.gc.markValue(new_line_value) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory\n", .{});
            std.process.exit(1);
        },
    };

    const new_arguments = std.mem.concat(self.gpa, Code.Value, &.{ arguments, &.{new_line_value} }) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory\n", .{});
            std.process.exit(1);
        },
    };

    _print(&buffered_writer, new_arguments, false) catch |err| switch (err) {
        else => {
            std.debug.print("println native function: error occured while trying to print\n", .{});
        },
    };

    buffered_writer.flush() catch |err| switch (err) {
        else => {
            std.debug.print("println native function: error occured while trying to print\n", .{});
        },
    };

    self.gpa.free(new_arguments);

    return Code.Value{ .none = {} };
}

fn random(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    var min = arguments[0];
    var max = arguments[1];

    if ((min != .int and min != .float) or (max != .int and max != .float)) {
        return Code.Value{ .none = {} };
    }

    switch (min) {
        .int => switch (max) {
            .int => {
                if (min.int > max.int) {
                    std.mem.swap(Code.Value, &min, &max);
                } else if (min.int == max.int) {
                    return Code.Value{ .float = @floatFromInt(min.int) };
                }
            },

            .float => {
                if (@as(f64, @floatFromInt(min.int)) > max.float) {
                    std.mem.swap(Code.Value, &min, &max);
                } else if (@as(f64, @floatFromInt(min.int)) == max.float) {
                    return max;
                }
            },

            else => unreachable,
        },

        .float => switch (max) {
            .int => {
                if (min.float > @as(f64, @floatFromInt(max.int))) {
                    std.mem.swap(Code.Value, &min, &max);
                } else if (min.float == @as(f64, @floatFromInt(max.int))) {
                    return min;
                }
            },

            .float => {
                if (min.float > max.float) {
                    std.mem.swap(Code.Value, &min, &max);
                } else if (min.float > max.float) {
                    return min;
                }
            },

            else => unreachable,
        },

        else => unreachable,
    }

    const RandGen = std.Random.DefaultPrng;
    var rnd = RandGen.init(@intCast(self.time(&.{}).int));

    switch (min) {
        .int => switch (max) {
            .int => return Code.Value{ .float = std.math.lerp(@as(f64, @floatFromInt(min.int)), @as(f64, @floatFromInt(max.int)), rnd.random().float(f64)) },

            .float => return Code.Value{ .float = std.math.lerp(@as(f64, @floatFromInt(min.int)), max.float, rnd.random().float(f64)) },

            else => unreachable,
        },

        .float => switch (max) {
            .int => return Code.Value{ .float = std.math.lerp(min.float, @as(f64, @floatFromInt(max.int)), rnd.random().float(f64)) },

            .float => return Code.Value{ .float = std.math.lerp(min.float, max.float, rnd.random().float(f64)) },

            else => unreachable,
        },

        else => unreachable,
    }
}

fn exit(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = self;

    const status_code = arguments[0];

    switch (status_code) {
        .int => std.process.exit(@intCast(std.math.mod(i64, status_code.int, 256) catch |err| switch (err) {
            else => std.process.exit(1),
        })),
        else => std.process.exit(1),
    }
}

fn time(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = arguments;

    const now_time = std.time.Instant.now() catch |err| switch (err) {
        error.Unsupported => unreachable,
    };

    const elapsed_time = now_time.since(self.start_time);

    return Code.Value{ .int = @intCast(elapsed_time) };
}

fn typeof(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const value = arguments[0];

    const typeof_value = switch (value) {
        .none => "none",
        .int => "int",
        .float => "float",
        .boolean => "boolean",
        .object => switch (value.object) {
            .string => "string",
            .array => "array",
            .function, .native_function => "function",
        },
    };

    const typeof_value_interned = self.gc.intern(typeof_value) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory\n", .{});
            std.process.exit(1);
        },
    };

    return Code.Value{ .object = .{ .string = .{ .content = typeof_value_interned } } };
}

fn array_push(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = self;

    if (arguments[0] != .object and arguments[0].object != .array) {
        return Code.Value{ .none = {} };
    }

    const array = arguments[0].object.array;

    const value = arguments[1];

    array.values.append(value) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory\n", .{});
            std.process.exit(1);
        },
    };

    return Code.Value{ .none = {} };
}

fn array_pop(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = self;

    if (arguments[0] != .object and arguments[0].object != .array) {
        return Code.Value{ .none = {} };
    }

    const array = arguments[0].object.array;

    return array.values.popOrNull() orelse Code.Value{ .none = {} };
}

fn len(self: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = self;

    const value = arguments[0];

    switch (value) {
        .object => switch (value.object) {
            .array => return Code.Value{ .int = @intCast(value.object.array.values.items.len) },
            .string => return Code.Value{ .int = @intCast(value.object.string.content.len) },

            else => {},
        },

        else => {},
    }

    return Code.Value{ .none = {} };
}

pub fn addGlobals(self: *VirtualMachine) std.mem.Allocator.Error!void {
    try self.globals.put("print", .{ .object = .{ .native_function = .{ .name = "print", .required_arguments_count = null, .call = &print } } });
    try self.globals.put("println", .{ .object = .{ .native_function = .{ .name = "println", .required_arguments_count = null, .call = &println } } });
    try self.globals.put("random", .{ .object = .{ .native_function = .{ .name = "random", .required_arguments_count = 2, .call = &random } } });
    try self.globals.put("exit", .{ .object = .{ .native_function = .{ .name = "exit", .required_arguments_count = 1, .call = &exit } } });
    try self.globals.put("time", .{ .object = .{ .native_function = .{ .name = "time", .required_arguments_count = 0, .call = &time } } });
    try self.globals.put("typeof", .{ .object = .{ .native_function = .{ .name = "typeof", .required_arguments_count = 1, .call = &typeof } } });
    try self.globals.put("array_push", .{ .object = .{ .native_function = .{ .name = "array_push", .required_arguments_count = 2, .call = &array_push } } });
    try self.globals.put("array_pop", .{ .object = .{ .native_function = .{ .name = "array_pop", .required_arguments_count = 1, .call = &array_pop } } });
    try self.globals.put("len", .{ .object = .{ .native_function = .{ .name = "len", .required_arguments_count = 1, .call = &len } } });
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

pub fn addGCRoots(self: *VirtualMachine) std.mem.Allocator.Error!void {
    try self.gc.roots.append(&self.stack);
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
            var values = std.ArrayList(Code.Value).init(self.gc.allocator());

            for (0..info.array.length) |_| {
                const value = self.stack.pop();
                try self.gc.markValue(value);

                try values.insert(0, value);
            }

            const array: Code.Value.Object.Array = .{ .values = values };

            var array_on_heap = try self.gc.allocator().alloc(Code.Value.Object.Array, 1);
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
                        try self.gc.markValue(lhs);
                        try self.gc.markValue(rhs);

                        const concatenated_string: Code.Value = .{ .object = .{ .string = .{ .content = try std.mem.concat(self.gc.allocator(), u8, &.{ lhs.object.string.content, rhs.object.string.content }) } } };

                        try self.gc.markValue(concatenated_string);

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
