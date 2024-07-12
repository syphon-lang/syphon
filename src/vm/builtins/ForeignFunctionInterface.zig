const std = @import("std");
const builtin = @import("builtin");
const ffi = @cImport(@cInclude("ffi.h"));

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("call", Code.Value.Object.NativeFunction.init(2, &call));
    try exports.put("to_cstring", Code.Value.Object.NativeFunction.init(1, &toCstring));
    try exports.put("allocate_callback", Code.Value.Object.NativeFunction.init(2, &allocateCallback));
    try exports.put("free_callback", Code.Value.Object.NativeFunction.init(1, &freeCallback));

    try exports.put("dll", try getDLLExports(vm));
    try exports.put("types", try getTypeExports(vm));

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, exports);
}

fn getDLLExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var dll_exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try dll_exports.put("open", Code.Value.Object.NativeFunction.init(2, dllOpen));
    try dll_exports.put("close", Code.Value.Object.NativeFunction.init(1, dllClose));

    const dll_suffix = switch (builtin.os.tag) {
        .linux, .freebsd, .openbsd, .solaris, .illumos => "so",
        .windows => "dll",
        .macos, .tvos, .watchos, .ios, .visionos => "dylib",
        else => @compileError("unsupported platform"),
    };

    try dll_exports.put("suffix", .{ .object = .{ .string = .{ .content = dll_suffix } } });

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, dll_exports);
}

fn getTypeExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
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

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, types_exports);
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

fn dllClose(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .map)) {
        return Code.Value{ .none = {} };
    }

    const dll = getPointerFromMap(std.DynLib, arguments[0]) orelse return Code.Value{ .none = {} };

    dll.close();

    return Code.Value{ .none = {} };
}

fn getPointerFromMap(comptime T: type, map: Code.Value) ?*T {
    const pointer = map.object.map.getWithString("pointer") orelse return null;
    if (pointer != .int) return null;

    return @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(pointer.int)))));
}

fn getFFITypeFromInt(from: i64) !*ffi.ffi_type {
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

        else => error.BadType,
    };
}

fn castArgumentToFFIArgument(argument: Code.Value, ffi_type: i64, destination: *anyopaque) !void {
    switch (ffi_type) {
        ffi.FFI_TYPE_VOID => return error.VoidShouldNotBeParameter,

        ffi.FFI_TYPE_UINT8 => {
            if (argument != .int) return error.ExpectedInt;

            const value: u8 = @intCast(std.math.mod(i64, argument.int, std.math.maxInt(u8)) catch unreachable);

            @as(*u8, @ptrCast(destination)).* = value;
        },

        ffi.FFI_TYPE_UINT16 => {
            if (argument != .int) return error.ExpectedInt;

            const value: u16 = @intCast(std.math.mod(i64, argument.int, std.math.maxInt(u16)) catch unreachable);

            @as(*u16, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_UINT32 => {
            if (argument != .int) return error.ExpectedInt;

            const value: u32 = @intCast(std.math.mod(i64, argument.int, std.math.maxInt(u16)) catch unreachable);

            @as(*u32, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_UINT64 => {
            if (argument != .int) return error.ExpectedInt;

            const value: u64 = @bitCast(argument.int);

            @as(*u64, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_SINT8 => {
            if (argument != .int) return error.ExpectedInt;

            const value: i8 = @intCast(std.math.mod(i64, argument.int, std.math.maxInt(i8)) catch unreachable);

            @as(*i8, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_SINT16 => {
            if (argument != .int) return error.ExpectedInt;

            const value: i16 = @intCast(std.math.mod(i64, argument.int, std.math.maxInt(i16)) catch unreachable);

            @as(*i16, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_SINT32 => {
            if (argument != .int) return error.ExpectedInt;

            const value: i32 = @intCast(std.math.mod(i64, argument.int, std.math.maxInt(i32)) catch unreachable);

            @as(*i32, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_SINT64 => {
            if (argument != .int) return error.ExpectedInt;

            const value = argument.int;

            @as(*i64, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_FLOAT => {
            if (argument != .float) return error.ExpectedFloat;

            const value: f32 = @floatCast(std.math.mod(f64, argument.float, @floatCast(std.math.floatMax(f32))) catch unreachable);

            @as(*f32, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_DOUBLE => {
            if (argument != .float) return error.ExpectedFloat;

            const value = argument.float;

            @as(*f64, @ptrCast(@alignCast(destination))).* = value;
        },

        ffi.FFI_TYPE_POINTER => {
            if (argument != .int) return error.ExpectedInt;

            const value: ?*anyopaque = @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(argument.int)))));

            @as(*?*anyopaque, @ptrCast(@alignCast(destination))).* = value;
        },

        else => return error.BadType,
    }
}

fn putArgumentInFFIArguments(allocator: std.mem.Allocator, argument: Code.Value, ffi_type: i64, ffi_arguments: *std.ArrayList(?*anyopaque)) !void {
    switch (ffi_type) {
        ffi.FFI_TYPE_VOID => return error.VoidShouldNotBeParameter,

        ffi.FFI_TYPE_UINT8 => {
            const value_on_heap = try allocator.create(u8);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_UINT16 => {
            const value_on_heap = try allocator.create(u16);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_UINT32 => {
            const value_on_heap = try allocator.create(u32);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_UINT64 => {
            const value_on_heap = try allocator.create(u64);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_SINT8 => {
            const value_on_heap = try allocator.create(i8);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_SINT16 => {
            const value_on_heap = try allocator.create(i16);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_SINT32 => {
            const value_on_heap = try allocator.create(i32);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_SINT64 => {
            const value_on_heap = try allocator.create(i64);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_FLOAT => {
            const value_on_heap = try allocator.create(f32);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_DOUBLE => {
            const value_on_heap = try allocator.create(f64);
            try castArgumentToFFIArgument(argument, ffi_type, value_on_heap);

            try ffi_arguments.append(value_on_heap);
        },

        ffi.FFI_TYPE_POINTER => {
            const value_on_heap = try allocator.create(*anyopaque);
            try castArgumentToFFIArgument(argument, ffi_type, @ptrCast(value_on_heap));

            try ffi_arguments.append(@ptrCast(value_on_heap));
        },

        else => return error.BadType,
    }
}

fn doFFICall(cif: *ffi.ffi_cif, function_pointer: *anyopaque, arguments: []?*anyopaque, return_type: i64) Code.Value {
    switch (return_type) {
        ffi.FFI_TYPE_VOID => {
            ffi.ffi_call(cif, @ptrCast(function_pointer), null, arguments.ptr);

            return Code.Value{ .none = {} };
        },

        ffi.FFI_TYPE_UINT8 => {
            var result: ffi.ffi_arg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @intCast(@as(u8, @truncate(result))) };
        },

        ffi.FFI_TYPE_UINT16 => {
            var result: ffi.ffi_arg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @intCast(@as(u16, @truncate(result))) };
        },

        ffi.FFI_TYPE_UINT32 => {
            var result: ffi.ffi_arg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @intCast(@as(u32, @truncate(result))) };
        },

        ffi.FFI_TYPE_UINT64 => {
            var result: ffi.ffi_arg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @intCast(result) };
        },

        ffi.FFI_TYPE_SINT8 => {
            var result: ffi.ffi_sarg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @intCast(@as(i8, @truncate(result))) };
        },

        ffi.FFI_TYPE_SINT16 => {
            var result: ffi.ffi_sarg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @intCast(@as(i16, @truncate(result))) };
        },

        ffi.FFI_TYPE_SINT32 => {
            var result: ffi.ffi_sarg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @intCast(@as(i32, @truncate(result))) };
        },

        ffi.FFI_TYPE_SINT64 => {
            var result: ffi.ffi_sarg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @bitCast(result) };
        },

        ffi.FFI_TYPE_FLOAT => {
            var result: ffi.ffi_arg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .float = @floatCast(@as(f32, @bitCast(@as(u32, @truncate(result))))) };
        },

        ffi.FFI_TYPE_DOUBLE => {
            var result: ffi.ffi_arg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .float = @bitCast(result) };
        },

        ffi.FFI_TYPE_POINTER => {
            var result: ffi.ffi_arg = undefined;

            ffi.ffi_call(cif, @ptrCast(function_pointer), &result, arguments.ptr);

            return Code.Value{ .int = @bitCast(result) };
        },

        else => return Code.Value{ .none = {} },
    }
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

    const dll_function_arguments = arguments[1].object.array;

    var ffi_cif: ffi.ffi_cif = undefined;

    var ffi_parameter_types = std.ArrayList(?*ffi.ffi_type).init(vm.allocator);

    const ffi_return_type = getFFITypeFromInt(dll_function_return_type.int) catch return Code.Value{ .none = {} };

    var ffi_arguments = std.ArrayList(?*anyopaque).init(vm.allocator);

    for (dll_function_parameter_types.object.array.values.items) |dll_function_parameter_type| {
        if (dll_function_parameter_type != .int) {
            return Code.Value{ .none = {} };
        }

        const ffi_parameter_type = getFFITypeFromInt(dll_function_parameter_type.int) catch return Code.Value{ .none = {} };

        ffi_parameter_types.append(ffi_parameter_type) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };
    }

    if (dll_function_arguments.values.items.len != ffi_parameter_types.items.len) {
        return Code.Value{ .none = {} };
    }

    for (dll_function_arguments.values.items, 0..) |dll_function_argument, i| {
        putArgumentInFFIArguments(vm.allocator, dll_function_argument, dll_function_parameter_types.object.array.values.items[i].int, &ffi_arguments) catch return Code.Value{ .none = {} };
    }

    switch (ffi.ffi_prep_cif(&ffi_cif, ffi.FFI_DEFAULT_ABI, @intCast(ffi_parameter_types.items.len), ffi_return_type, ffi_parameter_types.items.ptr)) {
        ffi.FFI_OK => {},
        else => return Code.Value{ .none = {} },
    }

    return doFFICall(&ffi_cif, dll_function_pointer, ffi_arguments.items, dll_function_return_type.int);
}

fn toCstring(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const original = arguments[0].object.string.content;

    const duplicated = vm.allocator.dupeZ(u8, original) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .int = @bitCast(@as(u64, @intFromPtr(duplicated.ptr))) };
}

const CallbackData = struct {
    vm: *VirtualMachine,
    function: *Code.Value.Object.Function,
};

fn evaluateCallbackFailed() noreturn {
    std.debug.print("syphon: failed to evaluate a ffi callback\n", .{});
    std.process.exit(1);
}

export fn evaluateCallback(cif: [*c]ffi.ffi_cif, maybe_return_address: ?*anyopaque, arguments: [*c]?*anyopaque, maybe_data: ?*anyopaque) void {
    const maybe_callback_data: ?*CallbackData = @ptrCast(@alignCast(maybe_data));

    const vm = maybe_callback_data.?.vm;
    const function = maybe_callback_data.?.function;

    for (arguments[0..cif.*.nargs], 0..) |argument, i| {
        switch (cif.*.arg_types[i].*.type) {
            ffi.FFI_TYPE_VOID => evaluateCallbackFailed(),

            ffi.FFI_TYPE_UINT8 => {
                const value = @as(*u8, @ptrCast(argument.?)).*;

                vm.stack.append(Code.Value{ .int = @intCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_UINT16 => {
                const value = @as(*u16, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .int = @intCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_UINT32 => {
                const value = @as(*u32, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .int = @intCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_UINT64 => {
                const value = @as(*u64, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .int = @intCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_SINT8 => {
                const value = @as(*i8, @ptrCast(argument.?)).*;

                vm.stack.append(Code.Value{ .int = @intCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_SINT16 => {
                const value = @as(*i16, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .int = @intCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_SINT32 => {
                const value = @as(*i32, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .int = @intCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_SINT64 => {
                const value = @as(*i64, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .int = value }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_FLOAT => {
                const value = @as(*f32, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .float = @floatCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_DOUBLE => {
                const value = @as(*f64, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .float = @floatCast(value) }) catch evaluateCallbackFailed();
            },

            ffi.FFI_TYPE_POINTER => {
                const value = @as(*ffi.ffi_arg, @ptrCast(@alignCast(argument.?))).*;

                vm.stack.append(Code.Value{ .int = @bitCast(value) }) catch evaluateCallbackFailed();
            },

            else => evaluateCallbackFailed(),
        }
    }

    const frame = &vm.frames.items[vm.frames.items.len - 1];

    vm.callUserFunction(function, frame) catch evaluateCallbackFailed();

    vm.run() catch evaluateCallbackFailed();

    const return_value = vm.stack.pop();

    if (cif.*.rtype.*.type != ffi.FFI_TYPE_VOID) {
        castArgumentToFFIArgument(return_value, @intCast(cif.*.rtype.*.type), maybe_return_address.?) catch evaluateCallbackFailed();
    }
}

var writeable_memory_allocated = std.AutoHashMapUnmanaged(i64, *anyopaque){};

fn allocateCallback(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .function)) {
        return Code.Value{ .none = {} };
    }

    if (!(arguments[1] == .object and arguments[1].object == .map)) {
        return Code.Value{ .none = {} };
    }

    const user_function = arguments[0].object.function;

    const user_function_prototype = arguments[1].object.map;

    const user_function_parameter_types = user_function_prototype.getWithString("parameters") orelse return Code.Value{ .none = {} };
    if (!(user_function_parameter_types == .object and user_function_parameter_types.object == .array)) {
        return Code.Value{ .none = {} };
    }

    const user_function_return_type = user_function_prototype.getWithString("returns") orelse return Code.Value{ .none = {} };
    if (user_function_return_type != .int) {
        return Code.Value{ .none = {} };
    }

    var ffi_cif: ffi.ffi_cif = undefined;

    var ffi_parameter_types = std.ArrayList(?*ffi.ffi_type).init(vm.allocator);

    const ffi_return_type = getFFITypeFromInt(user_function_return_type.int) catch return Code.Value{ .none = {} };

    for (user_function_parameter_types.object.array.values.items) |dll_function_parameter_type| {
        if (dll_function_parameter_type != .int) {
            return Code.Value{ .none = {} };
        }

        const ffi_parameter_type = getFFITypeFromInt(dll_function_parameter_type.int) catch return Code.Value{ .none = {} };

        ffi_parameter_types.append(ffi_parameter_type) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };
    }

    switch (ffi.ffi_prep_cif(&ffi_cif, ffi.FFI_DEFAULT_ABI, @intCast(ffi_parameter_types.items.len), ffi_return_type, ffi_parameter_types.items.ptr)) {
        ffi.FFI_OK => {},
        else => return Code.Value{ .none = {} },
    }

    const ffi_cif_on_heap = vm.allocator.create(ffi.ffi_cif) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    ffi_cif_on_heap.* = ffi_cif;

    var ffi_function_pointer: ?*anyopaque = undefined;

    const maybe_ffi_closure: ?*ffi.ffi_closure = @ptrCast(@alignCast(ffi.ffi_closure_alloc(@sizeOf(ffi.ffi_closure), &ffi_function_pointer)));

    if (maybe_ffi_closure) |ffi_closure| {
        const callback_data_on_heap = vm.allocator.create(CallbackData) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        callback_data_on_heap.* = .{ .vm = vm, .function = user_function };

        switch (ffi.ffi_prep_closure_loc(ffi_closure, ffi_cif_on_heap, &evaluateCallback, callback_data_on_heap, ffi_function_pointer)) {
            ffi.FFI_OK => {},
            else => return Code.Value{ .none = {} },
        }

        const ffi_function_pointer_casted: i64 = @bitCast(@as(u64, @intFromPtr(ffi_function_pointer)));

        writeable_memory_allocated.put(vm.allocator, ffi_function_pointer_casted, ffi_closure) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        return Code.Value{ .int = ffi_function_pointer_casted };
    }

    return Code.Value{ .none = {} };
}

fn freeCallback(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] != .int) {
        return Code.Value{ .none = {} };
    }

    const maybe_writeable_memory = writeable_memory_allocated.get(arguments[0].int);

    if (maybe_writeable_memory != null) {
        ffi.ffi_closure_free(maybe_writeable_memory);

        _ = writeable_memory_allocated.remove(arguments[0].int);
    }

    return Code.Value{ .none = {} };
}
