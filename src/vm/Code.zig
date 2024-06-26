const std = @import("std");

const SourceLoc = @import("../compiler/ast.zig").SourceLoc;
const VirtualMachine = @import("VirtualMachine.zig");

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
            pub const Inner = std.HashMap(Value, Value, Value.HashContext, std.hash_map.default_max_load_percentage);

            inner: Inner,

            pub fn init(allocator: std.mem.Allocator, inner: Inner) std.mem.Allocator.Error!Value {
                const map: Map = .{ .inner = inner };

                const map_on_heap = try allocator.create(Map);
                map_on_heap.* = map;

                return Value{ .object = .{ .map = map_on_heap } };
            }

            pub fn fromStringHashMap(allocator: std.mem.Allocator, from: std.StringHashMap(Value)) std.mem.Allocator.Error!Value {
                var inner = Inner.init(allocator);

                var from_iterator = from.iterator();

                while (from_iterator.next()) |from_entry| {
                    const key: Value = .{ .object = .{ .string = .{ .content = from_entry.key_ptr.* } } };
                    const value = from_entry.value_ptr.*;

                    try inner.put(key, value);
                }

                return init(allocator, inner);
            }

            pub fn fromEnvMap(allocator: std.mem.Allocator, from: std.process.EnvMap) std.mem.Allocator.Error!Value {
                var inner = Inner.init(allocator);

                var from_iterator = from.iterator();

                while (from_iterator.next()) |from_entry| {
                    const key: Value = .{ .object = .{ .string = .{ .content = from_entry.key_ptr.* } } };
                    const value: Value = .{ .object = .{ .string = .{ .content = from_entry.value_ptr.* } } };

                    try inner.put(key, value);
                }

                return init(allocator, inner);
            }
        };

        pub const Function = struct {
            parameters: []const []const u8,
            code: Code,

            pub fn init(allocator: std.mem.Allocator, parameters: []const []const u8, code: Code) std.mem.Allocator.Error!Value {
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

        pub fn hash(ctx: HashContext, key: Value) u64 {
            _ = ctx;

            return switch (key) {
                .none => 0,

                .int => @bitCast(key.int),

                .float => @intFromFloat(key.float),

                .boolean => @intFromBool(key.boolean),

                .object => switch (key.object) {
                    .string => blk: {
                        var hasher = std.hash.Wyhash.init(0);

                        hasher.update(key.object.string.content);

                        break :blk hasher.final();
                    },

                    else => unreachable,
                },
            };
        }

        pub fn eql(ctx: HashContext, lhs: Value, rhs: Value) bool {
            _ = ctx;
            return lhs.eql(rhs, false);
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
        map: Map,

        pub const Array = struct {
            length: usize,
        };

        pub const Map = struct {
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
