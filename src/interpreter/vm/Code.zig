const std = @import("std");

const Atom = @import("Atom.zig");
const VirtualMachine = @import("VirtualMachine.zig");
const Ast = @import("../compiler/Ast.zig");

const Code = @This();

constants: std.ArrayList(Value),

instructions: std.ArrayList(Instruction),

source_locations: std.ArrayList(Ast.SourceLoc),

pub const Value = union(enum) {
    none,
    int: i64,
    float: f64,
    boolean: bool,
    string: String,
    array: *Array,
    map: *Map,
    closure: *Closure,
    function: *Function,
    native_function: *NativeFunction,

    pub const String = struct {
        content: []const u8,
    };

    pub const Array = struct {
        pub const Inner = std.ArrayList(Value);

        inner: Inner,

        pub fn init(allocator: std.mem.Allocator, inner: Inner) std.mem.Allocator.Error!Value {
            const array: Array = .{ .inner = inner };

            const array_on_heap = try allocator.create(Array);
            array_on_heap.* = array;

            return Value{ .array = array_on_heap };
        }

        pub fn fromStringSlices(allocator: std.mem.Allocator, from: []const []const u8) std.mem.Allocator.Error!Value {
            var values = try std.ArrayList(Value).initCapacity(allocator, from.len);

            for (from) |content| {
                const value: Value = .{ .string = .{ .content = content } };
                values.appendAssumeCapacity(value);
            }

            return init(allocator, values);
        }
    };

    pub const Map = struct {
        pub const Inner = std.ArrayHashMap(Value, Value, Value.HashContext, true);

        inner: Inner,

        pub fn init(allocator: std.mem.Allocator, inner: Inner) std.mem.Allocator.Error!Value {
            const map: Map = .{ .inner = inner };

            const map_on_heap = try allocator.create(Map);
            map_on_heap.* = map;

            return Value{ .map = map_on_heap };
        }

        pub fn fromStringHashMap(allocator: std.mem.Allocator, from: std.StringHashMap(Value)) std.mem.Allocator.Error!Value {
            var inner = Inner.init(allocator);

            var from_entry_iterator = from.iterator();

            while (from_entry_iterator.next()) |from_entry| {
                const key: Value = .{ .string = .{ .content = from_entry.key_ptr.* } };
                const value = from_entry.value_ptr.*;

                try inner.put(key, value);
            }

            return init(allocator, inner);
        }

        pub fn fromEnvMap(allocator: std.mem.Allocator, from: std.process.EnvMap) std.mem.Allocator.Error!Value {
            var inner = Inner.init(allocator);

            var from_entry_iterator = from.iterator();

            while (from_entry_iterator.next()) |from_entry| {
                const key: Value = .{ .string = .{ .content = from_entry.key_ptr.* } };
                const value: Value = .{ .string = .{ .content = from_entry.value_ptr.* } };

                try inner.put(key, value);
            }

            return init(allocator, inner);
        }

        pub fn getWithString(self: Map, key: []const u8) ?Value {
            return self.inner.get(.{ .string = .{ .content = key } });
        }
    };

    pub const Closure = struct {
        function: *Function,
        globals: *VirtualMachine.Globals,
        upvalues: std.ArrayList(*Value),

        pub fn init(allocator: std.mem.Allocator, function: *Function, globals: *VirtualMachine.Globals, upvalues: std.ArrayList(*Value)) std.mem.Allocator.Error!Value {
            const closure: Closure = .{ .function = function, .globals = globals, .upvalues = upvalues };

            const closure_on_heap = try allocator.create(Closure);
            closure_on_heap.* = closure;

            return Value{ .closure = closure_on_heap };
        }

        pub fn call(self: *Closure, vm: *VirtualMachine, arguments: []const Value) Value {
            for (arguments) |argument| {
                vm.stack.append(argument) catch return .none;
            }

            const previous_frames_start = vm.frames_start;

            vm.frames_start = vm.frames.items.len;

            vm.frames.append(.{ .closure = self, .stack_start = vm.stack.items.len - self.function.parameters.len }) catch return .none;

            vm.run() catch return .none;

            vm.frames_start = previous_frames_start;

            return vm.stack.pop();
        }
    };

    pub const Function = struct {
        code: Code,
        parameters: []const Atom,

        pub fn init(allocator: std.mem.Allocator, parameters: []const Atom, code: Code) std.mem.Allocator.Error!Value {
            const function: Function = .{ .parameters = parameters, .code = code };

            const function_on_heap = try allocator.create(Function);
            function_on_heap.* = function;

            return Value{ .function = function_on_heap };
        }
    };

    pub const NativeFunction = struct {
        maybe_context: ?*Value = null,
        required_arguments_count: ?usize,
        call: Call,

        const Call = *const fn (*VirtualMachine, []const Value) Value;

        pub fn init(allocator: std.mem.Allocator, required_arguments_count: ?usize, call: Call) std.mem.Allocator.Error!Value {
            const native_function: NativeFunction = .{ .required_arguments_count = required_arguments_count, .call = call };

            const native_function_on_heap = try allocator.create(NativeFunction);
            native_function_on_heap.* = native_function;

            return Value{ .native_function = native_function_on_heap };
        }
    };

    pub const HashContext = struct {
        pub fn hashable(key: Value) bool {
            return switch (key) {
                .string => true,

                .array, .map, .closure, .function, .native_function => false,

                else => true,
            };
        }

        pub fn hash(ctx: HashContext, key: Value) u32 {
            _ = ctx;

            return switch (key) {
                .none => 0,

                .int => @truncate(@as(u64, @bitCast(key.int))),

                .float => @truncate(@as(u64, @bitCast(@as(i64, @intFromFloat(key.float))))),

                .boolean => @intFromBool(key.boolean),

                .string => @truncate(std.hash.Wyhash.hash(0, key.string.content)),

                else => unreachable,
            };
        }

        pub fn eql(ctx: HashContext, a: Value, b: Value, b_index: usize) bool {
            _ = ctx;
            _ = b_index;

            return a.eql(b, false);
        }
    };

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .none => false,
            .int => |value| value != 0,
            .float => |value| value != 0.0,
            .boolean => |value| value,
            .string => |value| value.content.len != 0,
            .array => |value| value.inner.items.len != 0,
            .map => |value| value.inner.count() != 0,

            else => true,
        };
    }

    pub fn eql(lhs: Value, rhs: Value, strict: bool) bool {
        if (lhs.isTruthy() != rhs.isTruthy()) {
            return false;
        }

        switch (lhs) {
            .none => return rhs == .none,

            .int => return (rhs == .int and lhs.int == rhs.int) or (!strict and rhs == .float and @as(f64, @floatFromInt(lhs.int)) == rhs.float) or (!strict and rhs == .boolean and lhs.int == @as(i64, @intFromBool(rhs.boolean))),

            .float => return (rhs == .float and lhs.float == rhs.float) or (!strict and rhs == .int and lhs.float == @as(f64, @floatFromInt(rhs.int))) or (!strict and rhs == .boolean and lhs.float == @as(f64, @floatFromInt(@intFromBool(rhs.boolean)))),

            .boolean => return (rhs == .boolean and lhs.boolean == rhs.boolean) or (!strict and rhs == .int and @as(i64, @intFromBool(lhs.boolean)) == rhs.int) or (!strict and rhs == .float and @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) == rhs.float),

            .string => return rhs == .string and std.mem.eql(u8, lhs.string.content, rhs.string.content),

            .array => {
                if (!(rhs == .array and lhs.array.inner.items.len == rhs.array.inner.items.len)) {
                    return false;
                }

                for (0..lhs.array.inner.items.len) |i| {
                    if (lhs.array.inner.items[i] == .array and lhs.array.inner.items[i].array == lhs.array) {
                        if (!(rhs.array.inner.items[i] == .array and rhs.array.inner.items[i].array == lhs.array)) {
                            return false;
                        }
                    } else if (!lhs.array.inner.items[i].eql(rhs.array.inner.items[i], false)) {
                        return false;
                    }
                }
            },

            .map => {
                if (rhs != .map) {
                    return false;
                }

                var lhs_map_iterator = lhs.map.inner.iterator();

                while (lhs_map_iterator.next()) |lhs_entry| {
                    if (rhs.map.inner.get(lhs_entry.key_ptr.*)) |rhs_entry_value| {
                        if (lhs_entry.value_ptr.* == .map and lhs_entry.value_ptr.map == lhs.map) {
                            if (!(rhs_entry_value == .map and rhs_entry_value.map == lhs.map)) {
                                return false;
                            }
                        } else if (!lhs_entry.value_ptr.eql(rhs_entry_value, false)) {
                            return false;
                        }
                    } else {
                        return false;
                    }
                }
            },

            // Comparing with pointers instead of checking everything is used here because when you do "function == other_function" you are just comparing function pointers
            .closure => return rhs == .closure and lhs.closure == rhs.closure,
            .function => return rhs == .function and lhs.function == rhs.function,
            .native_function => return rhs == .native_function and lhs.native_function.call == rhs.native_function.call,
        }

        return true;
    }
};

pub const Instruction = union(enum) {
    jump: usize,
    jump_if_false: usize,
    back: usize,
    load_constant: usize,
    load_global: Atom,
    load_local: usize,
    load_upvalue: usize,
    load_subscript,
    store_global: Atom,
    store_local: usize,
    store_upvalue: usize,
    store_subscript,
    make_array: usize,
    make_map: u32,
    make_closure: MakeClosure,
    close_upvalue: usize,
    call: usize,
    neg,
    not,
    add,
    subtract,
    divide,
    multiply,
    exponent,
    modulo,
    equals,
    less_than,
    greater_than,
    duplicate,
    pop,
    @"return",

    pub const MakeClosure = struct {
        function_constant_index: usize,
        upvalues: Upvalues,

        pub const Upvalues = std.ArrayList(Upvalue);

        pub const Upvalue = struct {
            local_index: ?usize,
            pointer_index: ?usize,
        };
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
