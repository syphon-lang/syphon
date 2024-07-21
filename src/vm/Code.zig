const std = @import("std");

const SourceLoc = @import("../compiler/ast.zig").SourceLoc;
const VirtualMachine = @import("VirtualMachine.zig");
const Atom = @import("Atom.zig");

const Code = @This();

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
        map: *Map,
        closure: *Closure,
        function: *Function,
        native_function: NativeFunction,

        pub const String = struct {
            content: []const u8,
        };

        pub const Array = struct {
            values: std.ArrayList(Value),

            pub fn init(allocator: std.mem.Allocator, values: std.ArrayList(Value)) std.mem.Allocator.Error!Value {
                const array: Array = .{ .values = values };

                const array_on_heap = try allocator.create(Array);
                array_on_heap.* = array;

                return Value{ .object = .{ .array = array_on_heap } };
            }

            pub fn fromStringSlices(allocator: std.mem.Allocator, from: []const []const u8) std.mem.Allocator.Error!Value {
                var values = try std.ArrayList(Value).initCapacity(allocator, from.len);

                for (from) |content| {
                    const value: Value = .{ .object = .{ .string = .{ .content = content } } };
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

                return Value{ .object = .{ .map = map_on_heap } };
            }

            pub fn fromStringHashMap(allocator: std.mem.Allocator, from: std.StringHashMap(Value)) std.mem.Allocator.Error!Value {
                var inner = Inner.init(allocator);

                var from_entry_iterator = from.iterator();

                while (from_entry_iterator.next()) |from_entry| {
                    const key: Value = .{ .object = .{ .string = .{ .content = from_entry.key_ptr.* } } };
                    const value = from_entry.value_ptr.*;

                    try inner.put(key, value);
                }

                return init(allocator, inner);
            }

            pub fn fromEnvMap(allocator: std.mem.Allocator, from: std.process.EnvMap) std.mem.Allocator.Error!Value {
                var inner = Inner.init(allocator);

                var from_entry_iterator = from.iterator();

                while (from_entry_iterator.next()) |from_entry| {
                    const key: Value = .{ .object = .{ .string = .{ .content = from_entry.key_ptr.* } } };
                    const value: Value = .{ .object = .{ .string = .{ .content = from_entry.value_ptr.* } } };

                    try inner.put(key, value);
                }

                return init(allocator, inner);
            }

            pub fn getWithString(self: Map, key: []const u8) ?Value {
                return self.inner.get(.{ .object = .{ .string = .{ .content = key } } });
            }
        };

        pub const Closure = struct {
            function: *Function,
            upvalues: std.ArrayList(*Value),

            pub fn init(allocator: std.mem.Allocator, function: *Function, upvalues: std.ArrayList(*Value)) std.mem.Allocator.Error!Value {
                const closure: Closure = .{ .function = function, .upvalues = upvalues };

                const closure_on_heap = try allocator.create(Closure);
                closure_on_heap.* = closure;

                return Value{ .object = .{ .closure = closure_on_heap } };
            }

            pub fn call(self: *Closure, vm: *VirtualMachine, arguments: []const Value) Value {
                for (arguments) |argument| {
                    vm.stack.append(argument) catch return .none;
                }

                const previous_frames_start = vm.frames_start;
                vm.frames_start = vm.frames.items.len;

                vm.callUserFunction(self) catch return .none;
                vm.run() catch return .none;

                vm.frames_start = previous_frames_start;

                return vm.stack.pop();
            }
        };

        pub const Function = struct {
            parameters: []const Atom,
            code: Code,

            pub fn init(allocator: std.mem.Allocator, parameters: []const Atom, code: Code) std.mem.Allocator.Error!Value {
                const function: Function = .{ .parameters = parameters, .code = code };

                const function_on_heap = try allocator.create(Function);
                function_on_heap.* = function;

                return Value{ .object = .{ .function = function_on_heap } };
            }
        };

        pub const NativeFunction = struct {
            required_arguments_count: ?usize,
            call: Call,

            const Call = *const fn (*VirtualMachine, []const Value) Value;

            pub fn init(required_arguments_count: ?usize, call: Call) Value {
                return Value{ .object = .{ .native_function = .{ .required_arguments_count = required_arguments_count, .call = call } } };
            }
        };
    };

    pub const HashContext = struct {
        pub fn hashable(key: Value) bool {
            return switch (key) {
                .object => switch (key.object) {
                    .string => true,

                    else => false,
                },

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

                .object => switch (key.object) {
                    .string => @truncate(std.hash.Wyhash.hash(0, key.object.string.content)),

                    else => unreachable,
                },
            };
        }

        pub fn eql(ctx: HashContext, a: Value, b: Value, b_index: usize) bool {
            _ = ctx;
            _ = b_index;

            return a.eql(b, false);
        }
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
                .map => self.object.map.inner.count() != 0,
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

            .int => return (rhs == .int and lhs.int == rhs.int) or (!strict and rhs == .float and @as(f64, @floatFromInt(lhs.int)) == rhs.float) or (!strict and rhs == .boolean and lhs.int == @as(i64, @intFromBool(rhs.boolean))),

            .float => return (rhs == .float and lhs.float == rhs.float) or (!strict and rhs == .int and lhs.float == @as(f64, @floatFromInt(rhs.int))) or (!strict and rhs == .boolean and lhs.float == @as(f64, @floatFromInt(@intFromBool(rhs.boolean)))),

            .boolean => return (rhs == .boolean and lhs.boolean == rhs.boolean) or (!strict and rhs == .int and @as(i64, @intFromBool(lhs.boolean)) == rhs.int) or (!strict and rhs == .float and @as(f64, @floatFromInt(@intFromBool(lhs.boolean))) == rhs.float),

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

                .map => {
                    if (!(rhs == .object and rhs.object == .map)) {
                        return false;
                    }

                    var lhs_map_iterator = lhs.object.map.inner.iterator();

                    while (lhs_map_iterator.next()) |lhs_entry| {
                        if (rhs.object.map.inner.get(lhs_entry.key_ptr.*)) |rhs_entry_value| {
                            if (lhs_entry.value_ptr.* == .object and lhs_entry.value_ptr.object == .map and lhs_entry.value_ptr.object.map == lhs.object.map) {
                                if (!(rhs_entry_value == .object and rhs_entry_value.object == .map and rhs_entry_value.object.map == lhs.object.map)) {
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
                .closure => return rhs == .object and rhs.object == .closure and lhs.object.closure == rhs.object.closure,
                .function => return rhs == .object and rhs.object == .function and lhs.object.function == rhs.object.function,
                .native_function => return rhs == .object and rhs.object == .native_function and lhs.object.native_function.call == rhs.object.native_function.call,
            },
        }

        return true;
    }
};

pub const Instruction = union(enum) {
    jump: usize,
    back: usize,
    jump_if_false: usize,
    load_constant: usize,
    load_global: Atom,
    load_local: usize,
    load_upvalue: usize,
    load_subscript: void,
    store_global: Atom,
    store_local: usize,
    store_upvalue: usize,
    store_subscript: void,
    make_array: usize,
    make_map: u32,
    make_closure: MakeClosure,
    close_upvalue: usize,
    call: usize,
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
    duplicate: void,
    pop: void,
    @"return": void,

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
