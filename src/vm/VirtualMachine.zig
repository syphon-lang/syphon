const std = @import("std");

const SourceLoc = @import("../compiler/ast.zig").SourceLoc;
const AutoHashMapRecorder = @import("../ds/hash_map_recorder.zig").AutoHashMapRecorder;
const Code = @import("Code.zig");
const Atom = @import("Atom.zig");

const VirtualMachine = @This();

allocator: std.mem.Allocator,

mutex: std.Thread.Mutex = .{},

exported: Code.Value = .{ .none = {} },

frames: std.ArrayList(Frame),
stack: std.ArrayList(Code.Value),
globals: std.AutoHashMap(Atom, Code.Value),

internal_vms: std.ArrayList(VirtualMachine),
internal_functions: std.AutoHashMap(*Code.Value.Object.Function, *VirtualMachine),

argv: []const []const u8,

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
    locals: AutoHashMapRecorder(Atom, usize),
    ip: usize = 0,
    stack_start: usize = 0,
};

pub const MAX_FRAMES_COUNT = 64;
pub const MAX_STACK_SIZE = MAX_FRAMES_COUNT * 255;

pub fn init(allocator: std.mem.Allocator, argv: []const []const u8) Error!VirtualMachine {
    var vm: VirtualMachine = .{
        .allocator = allocator,
        .frames = try std.ArrayList(Frame).initCapacity(allocator, MAX_FRAMES_COUNT),
        .stack = try std.ArrayList(Code.Value).initCapacity(allocator, MAX_STACK_SIZE),
        .globals = std.AutoHashMap(Atom, Code.Value).init(allocator),
        .internal_vms = try std.ArrayList(VirtualMachine).initCapacity(allocator, MAX_FRAMES_COUNT),
        .internal_functions = std.AutoHashMap(*Code.Value.Object.Function, *VirtualMachine).init(allocator),
        .argv = argv,
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
        .locals = try AutoHashMapRecorder(Atom, usize).initSnapshotsCapacity(self.allocator, MAX_FRAMES_COUNT),
    });
}

pub fn run(self: *VirtualMachine) Error!void {
    var frame = &self.frames.items[self.frames.items.len - 1];

    while (true) {
        if (self.frames.items.len >= MAX_FRAMES_COUNT or self.stack.items.len >= MAX_STACK_SIZE) {
            return error.StackOverflow;
        }

        // TODO: This check is needed here because in some scenarios it becomes equal, investigate further...
        if (frame.ip == frame.function.code.instructions.items.len) {
            return;
        }

        const instruction = frame.function.code.instructions.items[frame.ip];
        const source_loc = frame.function.code.source_locations.items[frame.ip];

        frame.ip += 1;

        switch (instruction) {
            .jump => frame.ip += instruction.jump,
            .back => frame.ip -= instruction.back,
            .jump_if_false => {
                if (!self.stack.pop().is_truthy()) frame.ip += instruction.jump_if_false;
            },

            .load_atom => try self.executeLoadAtom(instruction.load_atom, source_loc, frame),
            .load_constant => try self.stack.append(frame.function.code.constants.items[instruction.load_constant]),
            .load_subscript => try self.executeLoadSubscript(source_loc),

            .store_atom => try self.executeStoreAtom(instruction.store_atom, frame),
            .store_subscript => try self.executeStoreSubscript(source_loc),

            .make_array => try self.executeMakeArray(instruction.make_array),
            .make_map => try self.executeMakeMap(instruction.make_map),

            .call => {
                try self.executeCall(instruction.call, source_loc, frame);

                frame = &self.frames.items[self.frames.items.len - 1];
            },

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

            .duplicate => try self.stack.append(self.stack.getLast()),

            .pop => _ = self.stack.pop(),

            .@"return" => {
                const end_loop = try self.executeReturn();
                if (end_loop) break;

                frame = &self.frames.items[self.frames.items.len - 1];
            },
        }
    }
}

fn executeLoadAtom(self: *VirtualMachine, atom: Atom, source_loc: SourceLoc, frame: *Frame) Error!void {
    if (frame.locals.get(atom)) |stack_index| {
        try self.stack.append(self.stack.items[stack_index]);
    } else if (self.globals.get(atom)) |global_value| {
        try self.stack.append(global_value);
    } else {
        var error_message_buf = std.ArrayList(u8).init(self.allocator);

        try error_message_buf.writer().print("undefined name '{s}'", .{atom.toName()});

        self.error_info = .{ .message = try error_message_buf.toOwnedSlice(), .source_loc = source_loc };

        return error.UndefinedName;
    }
}

fn executeLoadSubscript(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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
}

fn executeStoreAtom(self: *VirtualMachine, atom: Atom, frame: *Frame) Error!void {
    const value = self.stack.pop();

    if (frame.locals.getFromLastSnapshot(atom)) |stack_index| {
        self.stack.items[stack_index] = value;
    } else {
        const stack_index = self.stack.items.len;

        try self.stack.append(value);

        try frame.locals.put(atom, stack_index);
    }
}

fn executeStoreSubscript(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const target = self.stack.pop();
    var index = self.stack.pop();
    const value = self.stack.pop();

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

    self.error_info = .{ .message = "target is not array nor map", .source_loc = source_loc };

    return error.UnexpectedValue;
}

fn executeMakeArray(self: *VirtualMachine, length: usize) Error!void {
    var values = try std.ArrayList(Code.Value).initCapacity(self.allocator, length);

    for (0..length) |_| {
        const value = self.stack.pop();

        values.insertAssumeCapacity(0, value);
    }

    try self.stack.append(try Code.Value.Object.Array.init(self.allocator, values));
}

fn executeMakeMap(self: *VirtualMachine, length: u32) Error!void {
    var inner = Code.Value.Object.Map.Inner.init(self.allocator);
    try inner.ensureTotalCapacity(length);

    for (0..length) |_| {
        const value = self.stack.pop();
        const key = self.stack.pop();

        inner.putAssumeCapacity(key, value);
    }

    try self.stack.append(try Code.Value.Object.Map.init(self.allocator, inner));
}

fn executeCall(self: *VirtualMachine, arguments_count: usize, source_loc: SourceLoc, frame: *Frame) Error!void {
    const callable = self.stack.pop();

    if (callable == .object) {
        switch (callable.object) {
            .function => {
                try self.checkArgumentsCount(callable.object.function.parameters.len, arguments_count, source_loc);

                try self.callUserFunction(callable.object.function, frame);
            },

            .native_function => {
                if (callable.object.native_function.required_arguments_count != null) {
                    try self.checkArgumentsCount(callable.object.native_function.required_arguments_count.?, arguments_count, source_loc);
                }

                try self.callNativeFunction(callable.object.native_function, arguments_count);
            },

            else => {
                self.error_info = .{ .message = "not a callable", .source_loc = source_loc };

                return error.BadOperand;
            },
        }
    }
}

fn checkArgumentsCount(self: *VirtualMachine, required_count: usize, arguments_count: usize, source_loc: SourceLoc) Error!void {
    if (required_count != arguments_count) {
        var error_message_buf = std.ArrayList(u8).init(self.allocator);

        try error_message_buf.writer().print("expected {} {s} got {}", .{ required_count, if (required_count != 1) "arguments" else "argument", arguments_count });

        self.error_info = .{ .message = try error_message_buf.toOwnedSlice(), .source_loc = source_loc };

        return error.UnexpectedValue;
    }
}

pub fn callUserFunction(self: *VirtualMachine, function: *Code.Value.Object.Function, frame: *Frame) Error!void {
    const stack_start = self.stack.items.len - function.parameters.len;

    if (self.internal_functions.get(function)) |internal_vm| {
        const internal_stack_start = internal_vm.stack.items.len;

        try internal_vm.stack.appendSlice(self.stack.items[stack_start..]);

        self.stack.shrinkRetainingCapacity(stack_start);

        const internal_frame = &internal_vm.frames.items[internal_vm.frames.items.len - 1];

        internal_frame.locals.newSnapshot();

        try internal_frame.locals.ensureUnusedCapacity(@intCast(function.parameters.len));

        for (function.parameters, 0..) |parameter, i| {
            try internal_frame.locals.put(parameter, internal_stack_start + i);
        }

        try internal_vm.frames.append(.{ .function = function, .locals = internal_frame.locals, .stack_start = internal_stack_start });

        internal_vm.run() catch |err| {
            self.error_info = internal_vm.error_info;

            return err;
        };

        const return_value = internal_vm.stack.pop();

        try self.stack.append(return_value);
    } else {
        frame.locals.newSnapshot();

        try frame.locals.ensureUnusedCapacity(@intCast(function.parameters.len));

        for (function.parameters, 0..) |parameter, i| {
            try frame.locals.put(parameter, stack_start + i);
        }

        try self.frames.append(.{ .function = function, .locals = frame.locals, .stack_start = stack_start });
    }
}

fn callNativeFunction(self: *VirtualMachine, native_function: Code.Value.Object.NativeFunction, arguments_count: usize) Error!void {
    const stack_start = self.stack.items.len - arguments_count;

    const return_value = native_function.call(self, self.stack.items[stack_start..]);

    self.stack.shrinkRetainingCapacity(stack_start);

    try self.stack.append(return_value);
}

fn executeReturn(self: *VirtualMachine) Error!bool {
    if (self.frames.items.len == 1) {
        return true;
    }

    const popped_frame = self.frames.pop();

    const return_value = self.stack.pop();

    const frame = &self.frames.items[self.frames.items.len - 1];

    self.stack.shrinkRetainingCapacity(popped_frame.stack_start);

    frame.locals.destroySnapshot();

    try self.stack.append(return_value);

    return frame.ip == frame.function.code.instructions.items.len;
}

fn executeNeg(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

fn executeNot(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();

    try self.stack.append(.{ .boolean = !rhs.is_truthy() });
}

fn executeAdd(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

            .array => switch (rhs) {
                .object => switch (rhs.object) {
                    .array => {
                        const concatenated_array: Code.Value = try Code.Value.Object.Array.init(self.allocator, try lhs.object.array.values.clone());

                        try concatenated_array.object.array.values.appendSlice(rhs.object.array.values.items);

                        return self.stack.append(concatenated_array);
                    },

                    else => {},
                },

                else => {},
            },

            .map => switch (rhs) {
                .object => switch (rhs.object) {
                    .map => {
                        const concatenated_map: Code.Value = try Code.Value.Object.Map.init(self.allocator, try lhs.object.map.inner.clone());

                        try concatenated_map.object.map.inner.ensureUnusedCapacity(rhs.object.map.inner.count());

                        var rhs_map_entry_iterator = rhs.object.map.inner.iterator();

                        while (rhs_map_entry_iterator.next()) |rhs_map_entry| {
                            concatenated_map.object.map.inner.putAssumeCapacity(rhs_map_entry.key_ptr.*, rhs_map_entry.value_ptr.*);
                        }

                        return self.stack.append(concatenated_map);
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

fn executeSubtract(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

fn executeDivide(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

    try self.stack.append(.{ .float = lhs.float / rhs.float });
}

fn executeMultiply(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

fn executeExponent(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
    const Type = @import("builtins/Type.zig");

    const rhs = Type.toFloat(self, &.{self.stack.pop()});
    const lhs = Type.toFloat(self, &.{self.stack.pop()});

    if (!(lhs == .float and rhs == .float)) {
        self.error_info = .{ .message = "bad operand for '**' binary operator", .source_loc = source_loc };
        return error.BadOperand;
    }

    try self.stack.append(.{ .float = std.math.pow(f64, lhs.float, rhs.float) });
}

fn executeModulo(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

fn executeNotEquals(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    try self.stack.append(.{ .boolean = !lhs.eql(rhs, false) });
}

fn executeEquals(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    try self.stack.append(.{ .boolean = lhs.eql(rhs, false) });
}

fn executeLessThan(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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

fn executeGreaterThan(self: *VirtualMachine, source_loc: SourceLoc) Error!void {
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
