const std = @import("std");

const Ast = @import("../compiler/Ast.zig");
const Code = @import("Code.zig");
const Atom = @import("Atom.zig");

const VirtualMachine = @This();

allocator: std.mem.Allocator,

mutex: std.Thread.Mutex = .{},

argv: []const []const u8,

globals: Globals,

stack: Stack(Code.Value),
open_upvalues: std.ArrayList(**Code.Value),
exported: Code.Value = .none,

frames: Stack(Frame),
frames_start: usize = 0,

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
    source_loc: Ast.SourceLoc,
};

pub const Globals = std.AutoHashMap(Atom, Code.Value);

pub const Frame = struct {
    closure: *Code.Value.Closure,
    stack: [*]Code.Value,
    counter: usize = 0,
};

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        start: [*]T,
        end: [*]T,
        capacity: usize,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) std.mem.Allocator.Error!Self {
            const buffer = (try allocator.alloc(T, capacity));

            return Self{
                .start = buffer.ptr,
                .end = buffer.ptr,
                .capacity = capacity,
            };
        }

        pub fn len(self: Self) usize {
            return self.end - self.start;
        }

        pub fn top(self: Self) T {
            return (self.end - 1)[0];
        }

        pub fn topPtr(self: Self) *T {
            return @ptrCast(self.end - 1);
        }

        pub fn append(self: *Self, value: T) Error!void {
            if (self.len() >= self.capacity) {
                @branchHint(.unlikely);

                return error.StackOverflow;
            } else {
                @branchHint(.likely);

                self.appendAssumeCapacity(value);
            }
        }

        pub fn appendSlice(self: *Self, values: []const T) Error!void {
            if (self.len() + values.len >= self.capacity) {
                @branchHint(.unlikely);

                return error.StackOverflow;
            } else {
                @branchHint(.likely);

                for (values) |value| {
                    self.appendAssumeCapacity(value);
                }
            }
        }

        pub fn appendAssumeCapacity(self: *Self, value: T) void {
            self.end[0] = value;
            self.end += 1;
        }

        pub fn pop(self: *Self) T {
            self.end -= 1;
            return self.end[0];
        }

        pub fn popMultiple(self: *Self, count: usize) void {
            self.end -= count;
        }
    };
}

pub fn init(allocator: std.mem.Allocator, argv: []const []const u8) Error!VirtualMachine {
    const max_frames = 64;
    const max_stack_size = max_frames * 255;

    var vm: VirtualMachine = .{
        .allocator = allocator,
        .argv = argv,
        .globals = Globals.init(allocator),
        .stack = try Stack(Code.Value).init(allocator, max_stack_size),
        .open_upvalues = std.ArrayList(**Code.Value).init(allocator),
        .frames = try Stack(Frame).init(allocator, max_frames),
    };

    vm.mutex.lock();

    try vm.addGlobals();

    return vm;
}

pub fn addGlobals(self: *VirtualMachine) std.mem.Allocator.Error!void {
    const array = @import("./builtins/array.zig");
    const cast = @import("./builtins/cast.zig");
    const string = @import("./builtins/string.zig");
    const iterable = @import("./builtins/iterable.zig");
    const console = @import("./builtins/console.zig");
    const hash = @import("./builtins/hash.zig");
    const function = @import("./builtins/function.zig");
    const map = @import("./builtins/map.zig");
    const module = @import("./builtins/module.zig");
    const process = @import("./builtins/process.zig");
    const random = @import("./builtins/random.zig");

    try array.addGlobals(self);
    try cast.addGlobals(self);
    try string.addGlobals(self);
    try iterable.addGlobals(self);
    try console.addGlobals(self);
    try hash.addGlobals(self);
    try function.addGlobals(self);
    try map.addGlobals(self);
    try module.addGlobals(self);
    try process.addGlobals(self);
    try random.addGlobals(self);
}

pub fn setCode(self: *VirtualMachine, code: Code) std.mem.Allocator.Error!void {
    const function = (try Code.Value.Function.init(self.allocator, &.{}, code)).function;
    const closure = (try Code.Value.Closure.init(self.allocator, function, &self.globals, std.ArrayList(*Code.Value).init(self.allocator))).closure;

    self.frames.appendAssumeCapacity(.{ .closure = closure, .stack = self.stack.start });
}

pub fn run(self: *VirtualMachine) Error!void {
    var frame = self.frames.topPtr();

    while (true) {
        const instruction = frame.closure.function.code.instructions.items[frame.counter];
        const source_loc = frame.closure.function.code.source_locations.items[frame.counter];

        frame.counter += 1;

        switch (instruction) {
            .jump => |offset| frame.counter += offset,
            .back => |offset| frame.counter -= offset,
            .jump_if_false => |offset| {
                if (!self.stack.pop().isTruthy()) frame.counter += offset;
            },

            .load_global => |atom| try self.executeLoadGlobal(frame.*, atom, source_loc),
            .load_local => |index| try self.stack.append(frame.stack[index]),
            .load_upvalue => |index| try self.stack.append(frame.closure.upvalues.items[index].*),
            .load_constant => |index| try self.stack.append(frame.closure.function.code.constants.items[index]),
            .load_subscript => try self.executeLoadSubscript(source_loc),

            .store_global => |atom| try self.executeStoreGlobal(atom),
            .store_local => |index| frame.stack[index] = self.stack.pop(),
            .store_upvalue => |index| frame.closure.upvalues.items[index].* = self.stack.pop(),
            .store_subscript => try self.executeStoreSubscript(source_loc),

            .make_array => |length| try self.executeMakeArray(length),
            .make_map => |length| try self.executeMakeMap(length),
            .make_closure => |info| try self.executeMakeClosure(frame.*, info),

            .close_upvalue => |index| try self.executeCloseUpvalue(frame.*, index),

            .call => |arguments_count| {
                try self.executeCall(arguments_count, source_loc);

                frame = self.frames.topPtr();
            },

            .neg => try self.executeNeg(source_loc),
            .not => try self.executeNot(),

            .add => try self.executeAdd(source_loc),
            .subtract => try self.executeSubtract(source_loc),
            .divide => try self.executeDivide(source_loc),
            .multiply => try self.executeMultiply(source_loc),
            .exponent => try self.executeExponent(source_loc),
            .modulo => try self.executeModulo(source_loc),
            .equals => try self.executeEquals(),
            .less_than => try self.executeLessThan(source_loc),
            .greater_than => try self.executeGreaterThan(source_loc),

            .duplicate => try self.stack.append(self.stack.top()),

            .pop => _ = self.stack.pop(),

            .@"return" => {
                if (try self.executeReturn()) break;

                frame = self.frames.topPtr();
            },
        }
    }
}

fn executeLoadGlobal(self: *VirtualMachine, frame: Frame, atom: Atom, source_loc: Ast.SourceLoc) Error!void {
    if (frame.closure.globals.get(atom)) |global_value| {
        try self.stack.append(global_value);
    } else {
        var error_message_buf = std.ArrayList(u8).init(self.allocator);

        try error_message_buf.writer().print("undefined name '{s}'", .{atom.toName()});

        self.error_info = .{ .message = error_message_buf.items, .source_loc = source_loc };

        return error.UndefinedName;
    }
}

fn executeLoadSubscript(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    var index = self.stack.pop();
    const target = self.stack.pop();

    switch (target) {
        .array => |target_value| {
            if (index != .int) {
                self.error_info = .{ .message = "index is not int", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            if (index.int < 0) {
                index.int += @as(i64, @intCast(target_value.inner.items.len));
            }

            if (index.int < 0 or index.int >= @as(i64, @intCast(target_value.inner.items.len))) {
                self.error_info = .{ .message = "index overflow", .source_loc = source_loc };

                return error.IndexOverflow;
            }

            return self.stack.append(target_value.inner.items[@as(usize, @intCast(index.int))]);
        },

        .string => |target_value| {
            if (index != .int) {
                self.error_info = .{ .message = "index is not int", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            if (index.int < 0) {
                index.int += @as(i64, @intCast(target_value.content.len));
            }

            if (index.int < 0 or index.int >= @as(i64, @intCast(target_value.content.len))) {
                self.error_info = .{ .message = "index overflow", .source_loc = source_loc };

                return error.IndexOverflow;
            }

            const index_casted: usize = @intCast(index.int);

            return self.stack.append(.{ .string = .{ .content = target_value.content[index_casted .. index_casted + 1] } });
        },

        .map => |target_value| {
            if (!Code.Value.HashContext.hashable(index)) {
                self.error_info = .{ .message = "unhashable value", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            if (target_value.inner.get(index)) |value| {
                return self.stack.append(value);
            }

            const console = @import("./builtins/console.zig");

            var error_message_buf = std.ArrayList(u8).init(self.allocator);

            var buffered_writer = std.io.bufferedWriter(error_message_buf.writer());

            _ = try buffered_writer.write("undefined key '");

            try console.printImpl(std.ArrayList(u8).Writer, &buffered_writer, &.{index}, false);

            _ = try buffered_writer.write("' in map");

            try buffered_writer.flush();

            self.error_info = .{ .message = error_message_buf.items, .source_loc = source_loc };

            return error.UndefinedKey;
        },

        else => {},
    }

    self.error_info = .{ .message = "target is not array nor string nor map", .source_loc = source_loc };

    return error.UnexpectedValue;
}

fn executeStoreGlobal(self: *VirtualMachine, atom: Atom) Error!void {
    const value = self.stack.pop();

    try self.globals.put(atom, value);
}

fn executeStoreSubscript(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const target = self.stack.pop();
    var index = self.stack.pop();
    const value = self.stack.pop();

    switch (target) {
        .array => |target_value| {
            if (index != .int) {
                self.error_info = .{ .message = "index is not int", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            if (index.int < 0) {
                index.int += @as(i64, @intCast(target_value.inner.items.len));
            }

            if (index.int < 0 or index.int >= @as(i64, @intCast(target_value.inner.items.len))) {
                self.error_info = .{ .message = "index overflow", .source_loc = source_loc };

                return error.IndexOverflow;
            }

            target_value.inner.items[@as(usize, @intCast(index.int))] = value;

            return;
        },

        .map => |target_value| {
            if (!Code.Value.HashContext.hashable(index)) {
                @branchHint(.unlikely);

                self.error_info = .{ .message = "unhashable value", .source_loc = source_loc };

                return error.UnexpectedValue;
            }

            try target_value.inner.put(index, value);

            return;
        },

        else => {},
    }

    self.error_info = .{ .message = "target is not array nor map", .source_loc = source_loc };

    return error.UnexpectedValue;
}

fn executeMakeArray(self: *VirtualMachine, length: usize) Error!void {
    var inner = try Code.Value.Array.Inner.initCapacity(self.allocator, length);

    for (0..length) |_| {
        const value = self.stack.pop();

        inner.insertAssumeCapacity(0, value);
    }

    try self.stack.append(try Code.Value.Array.init(self.allocator, inner));
}

fn executeMakeMap(self: *VirtualMachine, length: u32) Error!void {
    var inner = Code.Value.Map.Inner.init(self.allocator);
    try inner.ensureTotalCapacity(length);

    for (0..length) |_| {
        const value = self.stack.pop();
        const key = self.stack.pop();

        inner.putAssumeCapacity(key, value);
    }

    try self.stack.append(try Code.Value.Map.init(self.allocator, inner));
}

fn executeCloseUpvalue(self: *VirtualMachine, frame: Frame, index: usize) Error!void {
    const closed_upvalue = try self.allocator.create(Code.Value);
    closed_upvalue.* = frame.stack[index];

    var i: usize = 0;

    while (i < self.open_upvalues.items.len) {
        const open_upvalue = self.open_upvalues.items[i];

        if (open_upvalue.* == &frame.stack[index]) {
            open_upvalue.* = closed_upvalue;

            _ = self.open_upvalues.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

fn executeMakeClosure(self: *VirtualMachine, frame: Frame, info: Code.Instruction.MakeClosure) Error!void {
    const function = frame.closure.function.code.constants.items[info.function_constant_index].function;

    var upvalues = std.ArrayList(*Code.Value).init(self.allocator);

    for (info.upvalues.items) |upvalue| {
        const upvalue_destination = try upvalues.addOne();

        if (upvalue.local_index) |local_index| {
            upvalue_destination.* = &frame.stack[local_index];
        }

        if (upvalue.pointer_index) |pointer_index| {
            upvalue_destination.* = frame.closure.upvalues.items[pointer_index];
        }

        try self.open_upvalues.append(upvalue_destination);
    }

    try self.stack.append(try Code.Value.Closure.init(self.allocator, function, frame.closure.globals, upvalues));
}

fn executeCall(self: *VirtualMachine, arguments_count: usize, source_loc: Ast.SourceLoc) Error!void {
    const callable = self.stack.pop();

    switch (callable) {
        .closure => |closure| {
            try self.checkArgumentsCount(closure.function.parameters.len, arguments_count, source_loc);

            return self.frames.append(.{ .closure = closure, .stack = self.stack.end - arguments_count });
        },

        .native_function => |native_function| {
            if (native_function.required_arguments_count != null) {
                try self.checkArgumentsCount(native_function.required_arguments_count.?, arguments_count, source_loc);
            }

            const stack_start = self.stack.end - arguments_count;

            const stack_arguments = stack_start[0..arguments_count];

            const arguments_with_context = if (native_function.maybe_context) |context|
                try std.mem.concat(self.allocator, Code.Value, &.{ &.{context.*}, stack_arguments })
            else
                stack_arguments;

            const return_value = native_function.call(self, arguments_with_context);

            self.stack.popMultiple(self.stack.end - stack_start);

            return self.stack.append(return_value);
        },

        else => {},
    }

    self.error_info = .{ .message = "not a callable", .source_loc = source_loc };

    return error.BadOperand;
}

inline fn checkArgumentsCount(self: *VirtualMachine, required_count: usize, arguments_count: usize, source_loc: Ast.SourceLoc) Error!void {
    if (required_count != arguments_count) {
        @branchHint(.unlikely);

        var error_message_buf = std.ArrayList(u8).init(self.allocator);

        try error_message_buf.writer().print("expected {} {s} got {}", .{ required_count, if (required_count != 1) "arguments" else "argument", arguments_count });

        self.error_info = .{ .message = error_message_buf.items, .source_loc = source_loc };

        return error.UnexpectedValue;
    }
}

fn executeReturn(self: *VirtualMachine) Error!bool {
    if (self.frames.len() == 1) {
        @branchHint(.unlikely);

        return true;
    }

    const popped_frame = self.frames.pop();

    const return_value = self.stack.pop();

    self.stack.popMultiple(self.stack.end - popped_frame.stack);

    try self.stack.append(return_value);

    return self.frames.len() == self.frames_start;
}

fn executeNeg(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const rhs = self.stack.pop();

    switch (rhs) {
        .int => |rhs_value| return self.stack.append(.{ .int = -rhs_value }),
        .float => |rhs_value| return self.stack.append(.{ .float = -rhs_value }),
        .boolean => |rhs_value| return self.stack.append(.{ .int = -@as(i64, @intCast(@intFromBool(rhs_value))) }),

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '-' unary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn executeNot(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();

    try self.stack.append(.{ .boolean = !rhs.isTruthy() });
}

fn executeAdd(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .int = lhs_value + rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs_value)) + rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .int = lhs_value + @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .float = lhs_value + @as(f64, @floatFromInt(rhs_value)) }),
            .float => |rhs_value| return self.stack.append(.{ .float = lhs_value + rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .float = lhs_value + @as(f64, @floatFromInt(@intFromBool(rhs_value))) }),

            else => {},
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) + rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(lhs_value))) + rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) + @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        .string => |lhs_value| switch (rhs) {
            .string => |rhs_value| {
                const concatenated_string: Code.Value = .{ .string = .{ .content = try std.mem.concat(self.allocator, u8, &.{ lhs_value.content, rhs_value.content }) } };

                return self.stack.append(concatenated_string);
            },

            else => {},
        },

        .array => |lhs_value| switch (rhs) {
            .array => |rhs_value| {
                const concatenated_array: Code.Value = try Code.Value.Array.init(self.allocator, try lhs_value.inner.clone());

                try concatenated_array.array.inner.appendSlice(rhs_value.inner.items);

                return self.stack.append(concatenated_array);
            },

            else => {},
        },

        .map => |lhs_value| switch (rhs) {
            .map => |rhs_value| {
                const concatenated_map: Code.Value = try Code.Value.Map.init(self.allocator, try lhs_value.inner.clone());

                try concatenated_map.map.inner.ensureUnusedCapacity(rhs_value.inner.count());

                var rhs_map_entry_iterator = rhs_value.inner.iterator();

                while (rhs_map_entry_iterator.next()) |rhs_map_entry| {
                    concatenated_map.map.inner.putAssumeCapacity(rhs_map_entry.key_ptr.*, rhs_map_entry.value_ptr.*);
                }

                return self.stack.append(concatenated_map);
            },

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '+' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn executeSubtract(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .int = lhs_value - rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs_value)) - rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .int = lhs_value - @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .float = lhs_value - @as(f64, @floatFromInt(rhs_value)) }),
            .float => |rhs_value| return self.stack.append(.{ .float = lhs_value - rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .float = lhs_value - @as(f64, @floatFromInt(@intFromBool(rhs_value))) }),

            else => {},
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) - rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(lhs_value))) - rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) - @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '-' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn executeDivide(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const cast = @import("builtins/cast.zig");

    const rhs = cast.toFloat(self, &.{self.stack.pop()});
    const lhs = cast.toFloat(self, &.{self.stack.pop()});

    if (!(lhs == .float and rhs == .float)) {
        self.error_info = .{ .message = "bad operand for '/' binary operator", .source_loc = source_loc };
        return error.BadOperand;
    }

    if (rhs.float == 0) {
        return error.DivisionByZero;
    }

    try self.stack.append(.{ .float = lhs.float / rhs.float });
}

fn executeMultiply(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .int = lhs_value * rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .float = @as(f64, @floatFromInt(lhs_value)) * rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .int = lhs_value * @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .float = lhs_value * @as(f64, @floatFromInt(rhs_value)) }),
            .float => |rhs_value| return self.stack.append(.{ .float = lhs_value * rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .float = lhs_value * @as(f64, @floatFromInt(@intFromBool(rhs_value))) }),

            else => {},
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) * rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .float = @as(f64, @floatFromInt(@intFromBool(lhs_value))) * rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .int = @as(i64, @intCast(@intFromBool(lhs_value))) * @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '*' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn executeExponent(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const cast = @import("builtins/cast.zig");

    const rhs = cast.toFloat(self, &.{self.stack.pop()});
    const lhs = cast.toFloat(self, &.{self.stack.pop()});

    if (!(lhs == .float and rhs == .float)) {
        self.error_info = .{ .message = "bad operand for '**' binary operator", .source_loc = source_loc };
        return error.BadOperand;
    }

    try self.stack.append(.{ .float = std.math.pow(f64, lhs.float, rhs.float) });
}

fn executeModulo(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .int = try std.math.mod(i64, lhs_value, rhs_value) }),
            .float => |rhs_value| return self.stack.append(.{ .float = try std.math.mod(f64, @as(f64, @floatFromInt(lhs_value)), rhs_value) }),
            .boolean => |rhs_value| return self.stack.append(.{ .int = try std.math.mod(i64, lhs_value, @as(i64, @intCast(@intFromBool(rhs_value)))) }),

            else => {},
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .float = try std.math.mod(f64, lhs_value, @as(f64, @floatFromInt(rhs_value))) }),
            .float => |rhs_value| return self.stack.append(.{ .float = try std.math.mod(f64, lhs_value, rhs_value) }),
            .boolean => |rhs_value| return self.stack.append(.{ .float = try std.math.mod(f64, lhs_value, @as(f64, @floatFromInt(@intFromBool(rhs_value)))) }),

            else => {},
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .int = try std.math.mod(i64, @as(i64, @intCast(@intFromBool(lhs_value))), rhs_value) }),
            .float => |rhs_value| return self.stack.append(.{ .float = try std.math.mod(f64, @as(f64, @floatFromInt((@intFromBool(lhs_value)))), rhs_value) }),
            .boolean => |rhs_value| return self.stack.append(.{ .int = try std.math.mod(i64, @as(i64, @intCast(@intFromBool(lhs_value))), @as(i64, @intCast(@intFromBool(rhs_value)))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '%' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn executeEquals(self: *VirtualMachine) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    try self.stack.append(.{ .boolean = lhs.eql(rhs, false) });
}

fn executeLessThan(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .boolean = lhs_value < rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .boolean = @as(f64, @floatFromInt(lhs_value)) < rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .boolean = lhs_value < @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .boolean = lhs_value < @as(f64, @floatFromInt(rhs_value)) }),
            .float => |rhs_value| return self.stack.append(.{ .boolean = lhs_value < rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .boolean = lhs_value < @as(f64, @floatFromInt(@intFromBool(rhs_value))) }),

            else => {},
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .boolean = @as(i64, @intCast(@intFromBool(lhs_value))) < rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .boolean = @as(f64, @floatFromInt(@intFromBool(lhs_value))) < rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .boolean = @as(i64, @intCast(@intFromBool(lhs_value))) < @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '<' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}

fn executeGreaterThan(self: *VirtualMachine, source_loc: Ast.SourceLoc) Error!void {
    const rhs = self.stack.pop();
    const lhs = self.stack.pop();

    switch (lhs) {
        .int => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .boolean = lhs_value > rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .boolean = @as(f64, @floatFromInt(lhs_value)) > rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .boolean = lhs_value > @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        .float => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .boolean = lhs_value > @as(f64, @floatFromInt(rhs_value)) }),
            .float => |rhs_value| return self.stack.append(.{ .boolean = lhs_value > rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .boolean = lhs_value > @as(f64, @floatFromInt(@intFromBool(rhs_value))) }),

            else => {},
        },

        .boolean => |lhs_value| switch (rhs) {
            .int => |rhs_value| return self.stack.append(.{ .boolean = @as(i64, @intCast(@intFromBool(lhs_value))) > rhs_value }),
            .float => |rhs_value| return self.stack.append(.{ .boolean = @as(f64, @floatFromInt(@intFromBool(lhs_value))) > rhs_value }),
            .boolean => |rhs_value| return self.stack.append(.{ .boolean = @as(i64, @intCast(@intFromBool(lhs_value))) > @as(i64, @intCast(@intFromBool(rhs_value))) }),

            else => {},
        },

        else => {},
    }

    self.error_info = .{ .message = "bad operand for '>' binary operator", .source_loc = source_loc };

    return error.BadOperand;
}
