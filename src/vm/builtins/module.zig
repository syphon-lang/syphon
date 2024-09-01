const std = @import("std");

const Parser = @import("../../compiler/ast.zig").Parser;
const CodeGen = @import("../../compiler/CodeGen.zig");
const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");
const Atom = @import("../Atom.zig");

const NativeModuleGetters = std.StaticStringMap(*const fn (*VirtualMachine) std.mem.Allocator.Error!Code.Value).initComptime(.{
    .{ "fs", &(@import("file_system.zig").getExports) },
    .{ "ffi", &(@import("foreign_function_interface.zig").getExports) },
    .{ "io", &(@import("input_output.zig").getExports) },
    .{ "math", &(@import("math.zig").getExports) },
    .{ "os", &(@import("operating_system.zig").getExports) },
    .{ "process", &(@import("process.zig").getExports) },
    .{ "shell", &(@import("shell.zig").getExports) },
    .{ "threading", &(@import("threading.zig").getExports) },
    .{ "time", &(@import("time.zig").getExports) },
    .{ "unicode", &(@import("unicode.zig").getExports) },
});

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("export"), try Code.Value.NativeFunction.init(vm.allocator, 1, &@"export"));
    try vm.globals.put(try Atom.new("import"), try Code.Value.NativeFunction.init(vm.allocator, 1, &import));
    try vm.globals.put(try Atom.new("eval"), try Code.Value.NativeFunction.init(vm.allocator, 1, &eval));
}

fn @"export"(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    vm.exported = arguments[0];

    return .none;
}

fn import(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .string) {
        return .none;
    }

    const file_path = arguments[0].string.content;

    if (NativeModuleGetters.get(file_path)) |getNativeModule| {
        return getNativeModule(vm) catch .none;
    } else {
        return getUserModule(vm, file_path);
    }
}

var saved_user_modules: std.StringHashMapUnmanaged(UserModule) = .{};

const UserModule = struct {
    globals: VirtualMachine.Globals,
    exported: Code.Value,
};

fn getUserModule(vm: *VirtualMachine, file_path: []const u8) Code.Value {
    const source_file_path = vm.argv[0];

    const source_dir_path = blk: {
        if (std.fs.path.dirname(source_file_path)) |dir_path| {
            break :blk dir_path;
        } else {
            break :blk switch (source_file_path[0] == std.fs.path.sep) {
                true => std.fs.path.sep_str,
                false => "." ++ std.fs.path.sep_str,
            };
        }
    };

    const resolved_file_path = std.fs.path.resolve(vm.allocator, &.{ source_dir_path, file_path }) catch return .none;

    const file_content = blk: {
        const file = std.fs.cwd().openFile(resolved_file_path, .{}) catch return .none;
        defer file.close();

        break :blk file.readToEndAllocOptions(vm.allocator, std.math.maxInt(u32), null, @alignOf(u8), 0) catch return .none;
    };

    if (file_content.len == 0) {
        return .none;
    }

    var parser = Parser.init(vm.allocator, file_content) catch return .none;

    const root = parser.parseRoot() catch return .none;

    var gen = CodeGen.init(vm.allocator, .script) catch return .none;

    gen.compileRoot(root) catch return .none;

    if (saved_user_modules.get(resolved_file_path)) |saved_user_module| {
        return saved_user_module.exported;
    }

    const other_vm_argv = vm.allocator.alloc([]const u8, 1) catch return .none;
    other_vm_argv[0] = resolved_file_path;

    var other_vm = VirtualMachine.init(vm.allocator, other_vm_argv) catch return .none;

    other_vm.setCode(gen.code) catch return .none;

    other_vm.run() catch return .none;

    const saved_user_module = (saved_user_modules.getOrPutValue(vm.allocator, resolved_file_path, .{ .exported = other_vm.exported, .globals = other_vm.globals }) catch return .none).value_ptr;

    closeGlobalState(vm, &saved_user_module.globals, other_vm.exported);

    return saved_user_module.exported;
}

fn eval(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .string) {
        return .none;
    }

    if (arguments[0].string.content.len == 0) {
        return .none;
    }

    const source_code = vm.allocator.dupeZ(u8, arguments[0].string.content) catch return .none;

    var parser = Parser.init(vm.allocator, source_code) catch return .none;

    const root = parser.parseRoot() catch return .none;

    var gen = CodeGen.init(vm.allocator, .script) catch return .none;

    gen.compileRoot(root) catch return .none;

    var other_vm = VirtualMachine.init(vm.allocator, &.{"<eval>"}) catch return .none;

    other_vm.setCode(gen.code) catch return .none;

    other_vm.run() catch return .none;

    const globals_on_heap = vm.allocator.create(VirtualMachine.Globals) catch return .none;
    globals_on_heap.* = other_vm.globals;

    closeGlobalState(vm, globals_on_heap, other_vm.exported);

    return other_vm.exported;
}

fn closeGlobalState(vm: *VirtualMachine, globals_on_heap: *VirtualMachine.Globals, value: Code.Value) void {
    switch (value) {
        .closure => {
            value.closure.globals = globals_on_heap;
        },

        .map => {
            for (value.map.inner.values()) |map_value| {
                closeGlobalState(vm, globals_on_heap, map_value);
            }
        },

        else => {},
    }
}
