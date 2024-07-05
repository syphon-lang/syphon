const std = @import("std");

const SourceLoc = @import("../compiler/ast.zig").SourceLoc;
const Code = @import("Code.zig");
const StringHashMapRecorder = @import("string_hash_map_recorder.zig").StringHashMapRecorder;

const VirtualMachine = @This();

allocator: std.mem.Allocator,

mutex: std.Thread.Mutex = .{},

frames: std.ArrayList(Frame),

stack: std.ArrayList(Code.Value),

globals: std.StringHashMap(Code.Value),

exported: Code.Value = .{ .none = {} },

argv: []const []const u8,

internal_vms: std.ArrayList(VirtualMachine),

internal_functions: std.AutoArrayHashMap(*Code.Value.Object.Function, *VirtualMachine),

error_info: ?ErrorInfo = null,

pub const Error = error{
    BadOperand,
    UndefinedName,
    UndefinedKey,
    UnexpectedValue,
    DivisionByZero,
    NegativeDenominator,
    IndexOverflow,
    StackOverflow,
} || std.mem.Allocator.Error;

pub const ErrorInfo = struct {
    message: []const u8,
    source_loc: SourceLoc,
};

pub const Frame = struct {
    function: *Code.Value.Object.Function,
    locals: StringHashMapRecorder(usize),
    ip: usize = 0,
};

pub const MAX_FRAMES_COUNT = 128;
pub const MAX_STACK_SIZE = MAX_FRAMES_COUNT * 255;

var FRAMES_BUFFER: [MAX_FRAMES_COUNT * @sizeOf(Frame)]u8 = undefined;
var STACK_BUFFER: [MAX_STACK_SIZE * @sizeOf(Code.Value)]u8 = undefined;
var frame_allocator = std.heap.FixedBufferAllocator.init(&FRAMES_BUFFER);
var stack_allocator = std.heap.FixedBufferAllocator.init(&STACK_BUFFER);

pub fn init(allocator: std.mem.Allocator, argv: []const []const u8) Error!VirtualMachine {
    var vm: VirtualMachine = .{
        .allocator = allocator,
        .frames = std.ArrayList(Frame).init(frame_allocator.allocator()),
        .stack = std.ArrayList(Code.Value).init(stack_allocator.allocator()),
        .globals = std.StringHashMap(Code.Value).init(allocator),
        .argv = argv,
        .internal_vms = try std.ArrayList(VirtualMachine).initCapacity(allocator, MAX_FRAMES_COUNT),
        .internal_functions = std.AutoArrayHashMap(*Code.Value.Object.Function, *VirtualMachine).init(allocator),
    };

    vm.mutex.lock();

    try vm.addGlobals();

    return vm;
}

pub fn addGlobals(self: *VirtualMachine) std.mem.Allocator.Error!void {
    const Array = @import("./builtins/Array.zig");
    const Console = @import("./builtins/Console.zig");
    const Hash = @import("./builtins/Hash.zig");
    const Map = @import("./builtins/Map.zig");
    const Module = @import("./builtins/Module.zig");
    const Process = @import("./builtins/Process.zig");
    const Random = @import("./builtins/Random.zig");
    const String = @import("./builtins/String.zig");
    const Type = @import("./builtins/Type.zig");

    try Array.addGlobals(self);
    try Console.addGlobals(self);
    try Hash.addGlobals(self);
    try Map.addGlobals(self);
    try Module.addGlobals(self);
    try Process.addGlobals(self);
    try Random.addGlobals(self);
    try String.addGlobals(self);
    try Type.addGlobals(self);
}

pub fn setCode(self: *VirtualMachine, code: Code) std.mem.Allocator.Error!void {
    const value = try Code.Value.Object.Function.init(self.allocator, &.{}, code);

    try self.frames.append(.{
        .function = value.object.function,
        .locals = try StringHashMapRecorder(usize).initSnapshotsCapacity(self.allocator, MAX_FRAMES_COUNT),
    });
}

pub fn run(self: *VirtualMachine) Error!Code.Value {
    const frame = &self.frames.items[self.frames.items.len - 1];

    while (true) {
        if (self.stack.items.len >= MAX_STACK_SIZE - 1 or self.frames.items.len >= MAX_FRAMES_COUNT - 1) {
            return error.StackOverflow;
        }

        const instruction = frame.function.code.instructions.items[frame.ip];
        const source_loc = frame.function.code.source_locations.items[frame.ip];

        frame.ip += 1;

        switch (instruction) {
            .jump => executeJump(instruction.jump, frame),
            .back => executeBack(instruction.back, frame),
            .jump_if_false => self.executeJumpIfFalse(instruction.jump_if_false, frame),

            .load => try self.executeLoad(instruction.load, source_loc, frame),
            .store => try self.executeStore(instruction.store, source_loc, frame),

            .call => try self.executeCall(instruction.call, source_loc, frame),

            .neg => try self.executeNeg(source_loc),
            .not => try self.executeNot(),

            .add => try self.executeAdd(source_loc),
            .subtract => try self.executeSubtract(source_loc),
            .divide => try self.executeDivide(source_loc),
            .multiply => try self.executeMultiply(source_loc),
            .exponent => try self.executeExponent(source_loc),
            .modulo => try self.executeModulo(source_loc),
            .not_equals => try self.executeNotEquals(),
            .equals => try self.executeEquals(),
            .less_than => try self.executeLessThan(source_loc),
            .greater_than => try self.executeGreaterThan(source_loc),

            .make => try self.executeMake(instruction.make),

            .duplicate => {
                try self.stack.append(self.stack.getLast());
            },

            .pop => {
                _ = self.stack.pop();
            },

            .@"return" => {
                return self.stack.pop();
            },
        }
    }
}

inline fn executeLoad(self: *VirtualMachine, info: Code.Instruction.Load, source_loc: SourceLoc, frame: *Frame) Error!void {
    switch (info) {
        .constant => {
            return self.stack.append(frame.function.code.constants.items[info.constant]);
        },

        .name => {
            if (frame.locals.get(info.name)) |stack_index| {
                return self.stack.append(self.stack.items[stack_index]);
            }

            if (self.globals.get(info.name)) |global_value| {
                return self.stack.append(global_value);
            }

            var error_message_buf = std.ArrayList(u8).init(self.allocator);

            try error_message_buf.writer().print("undefined name '{s}'", .{info.name});

            self.error_info = .{ .message = try error_message_buf.toOwnedSlice(), .source_loc = source_loc };

            return error.UndefinedName;
        },

        .subscript => {
            var index = self.stack.pop();
            const target = self.stack.pop();

            switch (target) {
                .object => switch (target.object) {
                    .array => {
                        if (index != .int) {
                            self.error_info = .{ .message = "index is not int", .source_loc = source_loc };

                            return error.UnexpectedValue;
                        }

                        if (index.int < 0) {
                            index.int += @as(i64, @bitCast(target.object.array.values.items.len));
                        }

                        if (index.int < 0 or index.int >= @as(i64, @bitCast(target.object.array.values.items.len))) {
                            self.error_info = .{ .message = "index overflow", .source_loc = source_loc };

                            return error.IndexOverflow;
                        }

                        return self.stack.append(target.object.array.values.items[@as(usize, @intCast(@as(u64, @bitCast(index.int))))]);
                    },

                    .string => {
                        if (index != .int) {
                            self.error_info = .{ .message = "index is not int", .source_loc = source_loc };

                            return error.UnexpectedValue;
                        }

                        if (index.int < 0) {
                            index.int += @as(i64, @bitCast(target.object.string.content.len));
                        }

                        if (index.int < 0 or index.int >= @as(i64, @bitCast(target.object.string.content.len))) {
                            self.error_info = .{ .message = "index overflow", .source_loc = source_loc };

                            return error.IndexOverflow;
                        }

                        const index_casted: usize = @intCast(@as(u64, @bitCast(index.int)));

                        return self.stack.append(.{ .object = .{ .string = .{ .content = target.object.string.content[index_casted .. index_casted + 1] } } });
                    },

                    .map => {
                        if (!Code.Value.HashContext.hashable(index)) {
                            self.error_info = .{ .message = "unhashable value", .source_loc = source_loc };

                            return error.UnexpectedValue;
                        }

                        if (target.object.map.inner.get(index)) |value| {
                            return self.stack.append(value);
                        }

                        const Console = @import("./builtins/Console.zig");

                        var error_message_buf = std.ArrayList(u8).init(self.allocator);

                        var buffered_writer = std.io.bufferedWriter(error_message_buf.writer());

                        _ = try buffered_writer.write("undefined key '");

                        try Console._print(std.ArrayList(u8).Writer, &buffered_writer, &.{index}, false);

                        _ = try buffered_writer.write("' in map");

                        try buffered_writer.flush();

                        self.error_info = .{ .message = try error_message_buf.toOwnedSlice(), .source_loc = source_loc };

                        return error.UndefinedKey;
                    },

                    else => {},
                },

                else => {},
            }

            self.error_info = .{ .message = "target is not array nor string nor map", .source_loc = source_loc };

            return error.UnexpectedValue;
        },
    }
}

inline fn executeStore(self: *VirtualMachine, info: Code.Instruction.Store, source_loc: SourceLoc, frame: *Frame) Error!void {
    const value = self.stack.pop();

    switch (info) {
        .name => {
            if (frame.locals.getFromLastSnapshot(info.name)) |stack_index| {
                self.stack.items[stack_index] = value;

                return;
            }

            const stack_index = self.stack.items.len;

            try self.stack.append(value);

            try frame.locals.put(info.name, stack_index);
        },

        .subscript => {
            var index = self.stack.pop();
            const target = self.stack.pop();

            switch (target) {
                .object => switch (target.object) {
                    .array => {
                        if (index != .int) {
                            self.error_info = .{ .message = "index is not int", .source_loc = source_loc };

                            return error.UnexpectedValue;
                        }

                        if (index.int < 0) {
                            index.int += @as(i64, @bitCast(target.object.array.values.items.len));
                        }

                        if (index.int < 0 or index.int >= @as(i64, @bitCast(target.object.array.values.items.len))) {
                            self.error_info = .{ .message = "index overflow", .source_loc = source_loc };

                            return error.IndexOverflow;
                        }

                        target.object.array.values.items[@as(usize, @intCast(@as(u64, @bitCast(index.int))))] = value;

                        return;
                    },

                    .map => {
                        if (!Code.Value.HashContext.hashable(index)) {
                            self.error_info = .{ .message = "unhashable value", .source_loc = source_loc };

                            return error.UnexpectedValue;
                        }

                        try target.object.map.inner.put(index, value);

                        return;
                    },

                    else => {},
                },

                else => {},
            }

            self.error_info = .{ .message = "target is array nor map", .source_loc = source_loc };

            return error.UnexpectedValue;
        },
    }
}

inline fn executeJump(info: Code.Instruction.Jump, frame: *Frame) void {
    frame.ip += info.offset;
}

inline fn executeBack(info: Code.Instruction.Back, frame: *Frame) void {
    frame.ip -= info.offset;
}

inline fn executeJumpIfFalse(self: *VirtualMachine, info: Code.Instruction.JumpIfFalse, frame: *Frame) void {
    const value = self.stack.pop();

    if (!value.is_truthy()) {
        frame.ip += info.offset;
    }
}

inline fn executeMake(self: *VirtualMachine, info: Code.Instruction.Make) Error!void {
    switch (info) {
        .array => {
            var values = try std.ArrayList(Code.Value).initCapacity(self.allocator, info.array.length);

            for (0..info.array.length) |_| {
                const value = self.stack.pop();

                values.insertAssumeCapacity(0, value);
            }

            try self.stack.append(try Code.Value.Object.Array.init(self.allocator, values));
        },

        .map => {
            var inner = Code.Value.Object.Map.Inner.init(self.allocator);
            try inner.ensureTotalCapacity(info.map.length);

            for (0..info.map.length) |_| {
                const key = self.stack.pop();
                const value = self.stack.pop();

                inner.putAssumeCapacity(key, value);
            }

            try self.stack.append(try Code.Value.Object.Map.init(self.allocator, inner));
        },
    }
}

inline fn executeNeg(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

inline fn executeNot(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();

    try self.stack.append(.{ .boolean = !rhs.is_truthy() });
}

inline fn executeAdd(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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
                        const concatenated_string: Code.Value = .{ .object = .{ .string = .{ .content = try std.mem.concat(self.allocator, u8, &.{ lhs.object.string.content, rhs.object.string.content }) } } };

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

inline fn executeSubtract(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

inline fn executeDivide(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const Type = @import("builtins/Type.zig");

    const rhs = Type.toFloat(self, &.{self.stack.pop()});
    const lhs = Type.toFloat(self, &.{self.stack.pop()});

    if (!(lhs == .float and rhs == .float)) {
        self.error_info = .{ .message = "bad operand for '/' binary operator", .source_loc = source_loc };
        return error.BadOperand;
    }

    if (rhs.float == 0) {
        return error.DivisionByZero;
    }

    return self.stack.append(.{ .float = lhs.float / rhs.float });
}

inline fn executeMultiply(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

inline fn executeExponent(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const Type = @import("builtins/Type.zig");

    const rhs = Type.toFloat(self, &.{self.stack.pop()});
    const lhs = Type.toFloat(self, &.{self.stack.pop()});

    if (!(lhs == .float and rhs == .float)) {
        self.error_info = .{ .message = "bad operand for '**' binary operator", .source_loc = source_loc };
        return error.BadOperand;
    }

    return self.stack.append(.{ .float = std.math.pow(f64, lhs.float, rhs.float) });
}

inline fn executeModulo(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

inline fn executeNotEquals(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    return self.stack.append(.{ .boolean = !lhs.eql(rhs, false) });
}

inline fn executeEquals(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    return self.stack.append(.{ .boolean = lhs.eql(rhs, false) });
}

inline fn executeLessThan(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

inline fn executeGreaterThan(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

inline fn executeCall(self: *VirtualMachine, info: Code.Instruction.Call, source_loc: SourceLoc, frame: *Frame) Error!void {
    const callable = self.stack.pop();

    if (callable == .object) {
        switch (callable.object) {
            .function => {
                try self.checkArgumentsCount(callable.object.function.parameters.len, info.arguments_count, source_loc);

                const return_value = try self.callUserFunction(callable.object.function, frame);

                return self.stack.append(return_value);
            },

            .native_function => {
                if (callable.object.native_function.required_arguments_count != null) {
                    try self.checkArgumentsCount(callable.object.native_function.required_arguments_count.?, info.arguments_count, source_loc);
                }

                const return_value = self.callNativeFunction(callable.object.native_function, info.arguments_count);

                return self.stack.append(return_value);
            },

            else => {},
        }
    }

    self.error_info = .{ .message = "not a callable", .source_loc = source_loc };

    return error.BadOperand;
}

inline fn checkArgumentsCount(self: *VirtualMachine, required_count: usize, arguments_count: usize, source_loc: SourceLoc) Error!void {
    if (required_count != arguments_count) {
        var error_message_buf = std.ArrayList(u8).init(self.allocator);

        try error_message_buf.writer().print("expected {} {s} got {}", .{ required_count, if (required_count != 1) "arguments" else "argument", arguments_count });

        self.error_info = .{ .message = try error_message_buf.toOwnedSlice(), .source_loc = source_loc };

        return error.UnexpectedValue;
    }
}

pub inline fn callUserFunction(self: *VirtualMachine, function: *Code.Value.Object.Function, frame: *Frame) Error!Code.Value {
    if (self.internal_functions.get(function)) |internal_vm| {
        const internal_frame = &internal_vm.frames.items[internal_vm.frames.items.len - 1];

        internal_frame.locals.newSnapshot();

        const internal_stack_start = internal_vm.stack.items.len;

        const stack_start = self.stack.items.len - function.parameters.len;

        try internal_vm.stack.appendSlice(self.stack.items[stack_start..]);

        self.stack.shrinkRetainingCapacity(stack_start);

        for (function.parameters, 0..) |parameter, i| {
            try internal_frame.locals.put(parameter, internal_stack_start + i);
        }

        try internal_vm.frames.append(.{ .function = function, .locals = internal_frame.locals });

        const return_value = internal_vm.run() catch |err| {
            self.error_info = internal_vm.error_info;

            return err;
        };

        internal_vm.stack.shrinkRetainingCapacity(internal_stack_start);

        internal_frame.locals.destroySnapshot();

        _ = internal_vm.frames.pop();

        return return_value;
    } else {
        frame.locals.newSnapshot();

        const stack_start = self.stack.items.len - function.parameters.len;

        for (function.parameters, 0..) |parameter, i| {
            try frame.locals.put(parameter, stack_start + i);
        }

        try self.frames.append(.{ .function = function, .locals = frame.locals });

        const return_value = try self.run();

        self.stack.shrinkRetainingCapacity(stack_start);

        frame.locals.destroySnapshot();

        _ = self.frames.pop();

        return return_value;
    }
}

inline fn callNativeFunction(self: *VirtualMachine, native_function: Code.Value.Object.NativeFunction, arguments_count: usize) Code.Value {
    const stack_start = self.stack.items.len - arguments_count;

    const return_value = native_function.call(self, self.stack.items[stack_start..]);

    self.stack.shrinkRetainingCapacity(stack_start);

    return return_value;
}
