const std = @import("std");
const ffi = @cImport(@cInclude("ffi.h"));

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    var dll_exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try dll_exports.put("open", Code.Value.Object.NativeFunction.init(2, dllOpen));
    try dll_exports.put("close", Code.Value.Object.NativeFunction.init(1, dllClose));

    try exports.put("dll", try Code.Value.Object.Map.fromStringHashMap(vm.allocator, dll_exports));

    var types_exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try types_exports.put("void", .{ .int = @intCast(ffi.FFI_TYPE_VOID) });

    try types_exports.put("u8", .{ .int = @intCast(ffi.FFI_TYPE_UINT8) });
    try types_exports.put("u16", .{ .int = @intCast(ffi.FFI_TYPE_UINT16) });
    try types_exports.put("u32", .{ .int = @intCast(ffi.FFI_TYPE_UINT32) });
    try types_exports.put("u64", .{ .int = @intCast(ffi.FFI_TYPE_UINT64) });

    try types_exports.put("i8", .{ .int = @intCast(ffi.FFI_TYPE_SINT8) });
    try types_exports.put("i16", .{ .int = @intCast(ffi.FFI_TYPE_SINT16) });
    try types_exports.put("i32", .{ .int = @intCast(ffi.FFI_TYPE_SINT32) });
    try types_exports.put("i64", .{ .int = @intCast(ffi.FFI_TYPE_SINT64) });

    try types_exports.put("f32", .{ .int = @intCast(ffi.FFI_TYPE_FLOAT) });
    try types_exports.put("f64", .{ .int = @intCast(ffi.FFI_TYPE_DOUBLE) });

    try types_exports.put("pointer", .{ .int = @intCast(ffi.FFI_TYPE_POINTER) });

    try exports.put("types", try Code.Value.Object.Map.fromStringHashMap(vm.allocator, types_exports));

    try exports.put("call", Code.Value.Object.NativeFunction.init(2, &call));

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, exports);
}

fn dllOpen(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    if (!(arguments[1] == .object and arguments[1].object == .map)) {
        return Code.Value{ .none = {} };
    }

    const dll_path = arguments[0].object.string.content;
    const dll_wanted_functions = arguments[1].object.map;

    const dll = std.DynLib.open(dll_path) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const dll_on_heap = vm.allocator.create(std.DynLib) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    dll_on_heap.* = dll;

    var dll_map = std.StringHashMap(Code.Value).init(vm.allocator);

    dll_map.put("pointer", .{ .int = @bitCast(@as(u64, @intFromPtr(dll_on_heap))) }) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    var dll_wanted_function_iterator = dll_wanted_functions.inner.iterator();

    while (dll_wanted_function_iterator.next()) |dll_wanted_function| {
        if (!(dll_wanted_function.key_ptr.* == .object and dll_wanted_function.key_ptr.object == .string)) {
            return Code.Value{ .none = {} };
        }

        if (!(dll_wanted_function.value_ptr.* == .object and dll_wanted_function.value_ptr.object == .map)) {
            return Code.Value{ .none = {} };
        }

        const dll_wanted_function_name = dll_wanted_function.key_ptr.object.string.content;

        const dll_wanted_function_name_z = vm.allocator.dupeZ(u8, dll_wanted_function_name) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        var dll_function = std.StringHashMap(Code.Value).init(vm.allocator);

        const dll_function_pointer = dll_on_heap.lookup(*anyopaque, dll_wanted_function_name_z) orelse return Code.Value{ .none = {} };

        dll_function.put("pointer", .{ .int = @bitCast(@as(u64, @intFromPtr(dll_function_pointer))) }) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        dll_function.put("prototype", dll_wanted_function.value_ptr.*) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        dll_map.put(dll_wanted_function_name, Code.Value.Object.Map.fromStringHashMap(vm.allocator, dll_function) catch return Code.Value{ .none = {} }) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };
    }

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, dll_map) catch Code.Value{ .none = {} };
}

fn getPointerFromMap(comptime T: type, map: Code.Value) ?*T {
    const pointer = map.object.map.getWithString("pointer") orelse return null;
    if (pointer != .int) return null;

    return @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(pointer.int)))));
}

fn dllClose(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .map)) {
        return Code.Value{ .none = {} };
    }

    const dll = getPointerFromMap(std.DynLib, arguments[0]) orelse return Code.Value{ .none = {} };

    dll.close();

    return Code.Value{ .none = {} };
}

fn getFFITypeFromInt(from: i64) *ffi.ffi_type {
    return switch (from) {
        ffi.FFI_TYPE_VOID => &ffi.ffi_type_void,

        ffi.FFI_TYPE_UINT8 => &ffi.ffi_type_uint8,
        ffi.FFI_TYPE_UINT16 => &ffi.ffi_type_uint16,
        ffi.FFI_TYPE_UINT32 => &ffi.ffi_type_uint32,
        ffi.FFI_TYPE_UINT64 => &ffi.ffi_type_uint64,

        ffi.FFI_TYPE_SINT8 => &ffi.ffi_type_sint8,
        ffi.FFI_TYPE_SINT16 => &ffi.ffi_type_sint16,
        ffi.FFI_TYPE_SINT32 => &ffi.ffi_type_sint32,
        ffi.FFI_TYPE_SINT64 => &ffi.ffi_type_sint64,

        ffi.FFI_TYPE_FLOAT => &ffi.ffi_type_float,
        ffi.FFI_TYPE_DOUBLE => &ffi.ffi_type_double,

        ffi.FFI_TYPE_POINTER => &ffi.ffi_type_pointer,

        else => unreachable,
    };
}

fn call(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .map)) {
        return Code.Value{ .none = {} };
    }

    if (!(arguments[1] == .object and arguments[1].object == .array)) {
        return Code.Value{ .none = {} };
    }

    const dll_function_pointer = getPointerFromMap(anyopaque, arguments[0]) orelse return Code.Value{ .none = {} };

    const dll_function_prototype = arguments[0].object.map.getWithString("prototype") orelse return Code.Value{ .none = {} };
    if (!(dll_function_prototype == .object and dll_function_prototype.object == .map)) {
        return Code.Value{ .none = {} };
    }

    const dll_function_parameter_types = dll_function_prototype.object.map.getWithString("parameters") orelse return Code.Value{ .none = {} };
    if (!(dll_function_parameter_types == .object and dll_function_parameter_types.object == .array)) {
        return Code.Value{ .none = {} };
    }

    const dll_function_return_type = dll_function_prototype.object.map.getWithString("returns") orelse return Code.Value{ .none = {} };
    if (dll_function_return_type != .int) {
        return Code.Value{ .none = {} };
    }

    const dll_function_is_variadic = dll_function_prototype.object.map.getWithString("variadic") orelse return Code.Value{ .none = {} };
    if (dll_function_is_variadic != .boolean) {
        return Code.Value{ .none = {} };
    }

    const dll_function_arguments = arguments[1].object.array;

    var ffi_cif: ffi.ffi_cif = undefined;

    var ffi_parameter_types = std.ArrayList(?*ffi.ffi_type).init(vm.allocator);

    const ffi_return_type = getFFITypeFromInt(dll_function_return_type.int);

    var ffi_arguments = std.ArrayList(?*anyopaque).init(vm.allocator);

    for (dll_function_parameter_types.object.array.values.items) |dll_function_parameter_type| {
        if (dll_function_parameter_type != .int) {
            return Code.Value{ .none = {} };
        }

        ffi_parameter_types.append(getFFITypeFromInt(dll_function_parameter_type.int)) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };
    }

    if (dll_function_is_variadic.boolean) {
        if (dll_function_arguments.values.items.len < ffi_parameter_types.items.len) {
            return Code.Value{ .none = {} };
        }

        for (dll_function_arguments.values.items, 0..) |dll_function_argument, i| {
            _ = dll_function_argument;
            _ = i;
        }

        @panic("TODO");
    } else {
        if (dll_function_arguments.values.items.len != ffi_parameter_types.items.len) {
            return Code.Value{ .none = {} };
        }

        for (dll_function_arguments.values.items, 0..) |dll_function_argument, i| {
            switch (dll_function_parameter_types.object.array.values.items[i].int) {
                ffi.FFI_TYPE_VOID => return Code.Value{ .none = {} },

                ffi.FFI_TYPE_UINT8 => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    const value: u8 = @intCast(std.math.mod(i64, dll_function_argument.int, std.math.maxInt(u8)) catch unreachable);

                    const value_on_heap = vm.allocator.create(u8) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_UINT16 => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    const value: u16 = @intCast(std.math.mod(i64, dll_function_argument.int, std.math.maxInt(u16)) catch unreachable);

                    const value_on_heap = vm.allocator.create(u16) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_UINT32 => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    const value: u32 = @intCast(std.math.mod(i64, dll_function_argument.int, std.math.maxInt(u16)) catch unreachable);

                    const value_on_heap = vm.allocator.create(u32) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_UINT64 => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    const value: u64 = @bitCast(dll_function_argument.int);

                    const value_on_heap = vm.allocator.create(u64) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_SINT8 => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    const value: i8 = @intCast(std.math.mod(i64, dll_function_argument.int, std.math.maxInt(i8)) catch unreachable);

                    const value_on_heap = vm.allocator.create(i8) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_SINT16 => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    const value: i16 = @intCast(std.math.mod(i64, dll_function_argument.int, std.math.maxInt(i16)) catch unreachable);

                    const value_on_heap = vm.allocator.create(i16) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_SINT32 => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    const value: i32 = @intCast(std.math.mod(i64, dll_function_argument.int, std.math.maxInt(i32)) catch unreachable);

                    const value_on_heap = vm.allocator.create(i32) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_SINT64 => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    const value = dll_function_argument.int;

                    const value_on_heap = vm.allocator.create(i64) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_FLOAT => {
                    if (dll_function_argument != .float) {
                        return Code.Value{ .none = {} };
                    }

                    const value: f32 = @floatCast(std.math.mod(f64, dll_function_argument.float, @floatCast(std.math.floatMax(f32))) catch unreachable);

                    const value_on_heap = vm.allocator.create(f32) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_DOUBLE => {
                    if (dll_function_argument != .float) {
                        return Code.Value{ .none = {} };
                    }

                    const value = dll_function_argument.float;

                    const value_on_heap = vm.allocator.create(f64) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };

                    value_on_heap.* = value;

                    ffi_arguments.append(value_on_heap) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                ffi.FFI_TYPE_POINTER => {
                    if (dll_function_argument != .int) {
                        return Code.Value{ .none = {} };
                    }

                    ffi_arguments.append(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(dll_function_argument.int)))))) catch |err| switch (err) {
                        else => return Code.Value{ .none = {} },
                    };
                },

                else => unreachable,
            }
        }

        switch (ffi.ffi_prep_cif(&ffi_cif, ffi.FFI_DEFAULT_ABI, @intCast(ffi_parameter_types.items.len), ffi_return_type, ffi_parameter_types.items.ptr)) {
            ffi.FFI_OK => {},
            else => return Code.Value{ .none = {} },
        }
    }

    std.debug.print("{any}\n", .{ffi_arguments.items});

    switch (dll_function_return_type.int) {
        ffi.FFI_TYPE_VOID => {
            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), null, ffi_arguments.items.ptr);

            return Code.Value{ .none = {} };
        },

        ffi.FFI_TYPE_UINT8 => {
            var ffi_result: ffi.ffi_arg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @intCast(@as(u8, @truncate(ffi_result))) };
        },

        ffi.FFI_TYPE_UINT16 => {
            var ffi_result: ffi.ffi_arg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @intCast(@as(u16, @truncate(ffi_result))) };
        },

        ffi.FFI_TYPE_UINT32 => {
            var ffi_result: ffi.ffi_arg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @intCast(@as(u32, @truncate(ffi_result))) };
        },

        ffi.FFI_TYPE_UINT64 => {
            var ffi_result: ffi.ffi_arg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @intCast(ffi_result) };
        },

        ffi.FFI_TYPE_SINT8 => {
            var ffi_result: ffi.ffi_sarg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @intCast(@as(i8, @truncate(ffi_result))) };
        },

        ffi.FFI_TYPE_SINT16 => {
            var ffi_result: ffi.ffi_sarg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @intCast(@as(i16, @truncate(ffi_result))) };
        },

        ffi.FFI_TYPE_SINT32 => {
            var ffi_result: ffi.ffi_sarg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @intCast(@as(i32, @truncate(ffi_result))) };
        },

        ffi.FFI_TYPE_SINT64 => {
            var ffi_result: ffi.ffi_sarg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @bitCast(ffi_result) };
        },

        ffi.FFI_TYPE_FLOAT => {
            var ffi_result: ffi.ffi_arg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .float = @floatCast(@as(f32, @bitCast(@as(u32, @truncate(ffi_result))))) };
        },

        ffi.FFI_TYPE_DOUBLE => {
            var ffi_result: ffi.ffi_arg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .float = @bitCast(ffi_result) };
        },

        ffi.FFI_TYPE_POINTER => {
            var ffi_result: ffi.ffi_arg = undefined;

            ffi.ffi_call(&ffi_cif, @ptrCast(dll_function_pointer), &ffi_result, ffi_arguments.items.ptr);

            return Code.Value{ .int = @intCast(ffi_result) };
        },

        else => unreachable,
    }
}
