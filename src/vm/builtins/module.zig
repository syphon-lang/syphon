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
});

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put(try Atom.new("export"), Code.Value.Object.NativeFunction.init(1, &@"export"));
    try vm.globals.put(try Atom.new("import"), Code.Value.Object.NativeFunction.init(1, &import));
    try vm.globals.put(try Atom.new("eval"), Code.Value.Object.NativeFunction.init(1, &eval));
}

fn @"export"(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    vm.exported = arguments[0];

    return .none;
}

fn import(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return .none;
    }

    const file_path = arguments[0].object.string.content;

    if (NativeModuleGetters.get(file_path)) |getNativeModule| {
        return getNativeModule(vm) catch .none;
    } else {
        return getExported(vm, file_path);
    }
}

fn getExported(vm: *VirtualMachine, file_path: []const u8) Code.Value {
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

    const resolved_file_path = std.fs.path.resolve(vm.allocator, &.{ source_dir_path, file_path }) catch |err| switch (err) {
        else => return .none,
    };

    const file = std.fs.cwd().openFile(resolved_file_path, .{}) catch |err| switch (err) {
        else => return .none,
    };

    defer file.close();

    const file_content = file.reader().readAllAlloc(vm.allocator, std.math.maxInt(u32)) catch |err| switch (err) {
        else => return .none,
    };

    if (file_content.len == 0) {
        return .none;
    }

    const file_content_z = @as([:0]u8, @ptrCast(file_content));

    file_content_z[file_content.len] = 0;

    var parser = Parser.init(vm.allocator, file_content_z) catch |err| switch (err) {
        else => return .none,
    };

    const root = parser.parseRoot() catch |err| switch (err) {
        else => return .none,
    };

    var gen = CodeGen.init(vm.allocator, .script) catch |err| switch (err) {
        else => return .none,
    };

    gen.compileRoot(root) catch |err| switch (err) {
        else => return .none,
    };

    const internal_vm = vm.internal_vms.addOneAssumeCapacity();

    const internal_vm_argv = vm.allocator.alloc([]const u8, 1) catch |err| switch (err) {
        else => return .none,
    };

    internal_vm_argv[0] = resolved_file_path;

    internal_vm.* = VirtualMachine.init(vm.allocator, internal_vm_argv) catch |err| switch (err) {
        else => return .none,
    };

    internal_vm.setCode(gen.code) catch |err| switch (err) {
        else => return .none,
    };

    internal_vm.run() catch |err| switch (err) {
        else => return .none,
    };

    addForeignFunction(vm, internal_vm, internal_vm.exported);

    return internal_vm.exported;
}

fn eval(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return .none;
    }

    if (arguments[0].object.string.content.len == 0) {
        return .none;
    }

    const source_code = vm.allocator.dupeZ(u8, arguments[0].object.string.content) catch |err| switch (err) {
        else => return .none,
    };

    var parser = Parser.init(vm.allocator, source_code) catch |err| switch (err) {
        else => return .none,
    };

    const root = parser.parseRoot() catch |err| switch (err) {
        else => return .none,
    };

    var gen = CodeGen.init(vm.allocator, .script) catch |err| switch (err) {
        else => return .none,
    };

    gen.compileRoot(root) catch |err| switch (err) {
        else => return .none,
    };

    const internal_vm = vm.internal_vms.addOneAssumeCapacity();

    internal_vm.* = VirtualMachine.init(vm.allocator, &.{"<eval>"}) catch |err| switch (err) {
        else => return .none,
    };

    internal_vm.setCode(gen.code) catch |err| switch (err) {
        else => return .none,
    };

    internal_vm.run() catch |err| switch (err) {
        else => return .none,
    };

    addForeignFunction(vm, internal_vm, internal_vm.exported);

    return internal_vm.exported;
}

fn addForeignFunction(vm: *VirtualMachine, internal_vm: *VirtualMachine, value: Code.Value) void {
    switch (value) {
        .object => switch (value.object) {
            .closure => {
                vm.internal_functions.put(value.object.closure, internal_vm) catch |err| switch (err) {
                    else => return,
                };
            },

            .map => {
                for (value.object.map.inner.values()) |map_value| {
                    addForeignFunction(vm, internal_vm, map_value);
                }
            },

            else => {},
        },

        else => {},
    }
}
