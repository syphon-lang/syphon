const std = @import("std");

const Parser = @import("../../compiler/ast.zig").Parser;
const CodeGen = @import("../../compiler/CodeGen.zig");
const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("export", Code.Value.Object.NativeFunction.init(1, &@"export"));
    try vm.globals.put("import", Code.Value.Object.NativeFunction.init(1, &import));
}

fn @"export"(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    vm.exported_value = arguments[0];

    return Code.Value{ .none = {} };
}

fn import(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const file_path = arguments[0].object.string.content;

    if (NativeModules.get(file_path)) |getNativeModule| {
        return getNativeModule(vm);
    } else {
        return getExportedValue(vm, file_path);
    }
}

const NativeModules = std.StaticStringMap(*const fn (*VirtualMachine) Code.Value).initComptime(.{
    .{ "fs", &getFileSystemModule },
    .{ "io", &getIOModule },
    .{ "math", &getMathModule },
    .{ "process", &getProcessModule },
});

fn getFileSystemModule(vm: *VirtualMachine) Code.Value {
    const FileSystem = @import("FileSystem.zig");

    const exports = FileSystem.getExports(vm) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return exports;
}

fn getIOModule(vm: *VirtualMachine) Code.Value {
    const IO = @import("IO.zig");

    const exports = IO.getExports(vm) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return exports;
}

fn getMathModule(vm: *VirtualMachine) Code.Value {
    const Math = @import("Math.zig");

    const exports = Math.getExports(vm) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return exports;
}

fn getProcessModule(vm: *VirtualMachine) Code.Value {
    const Process = @import("Process.zig");

    const exports = Process.getExports(vm) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return exports;
}

fn getExportedValue(vm: *VirtualMachine, file_path: []const u8) Code.Value {
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

    const resolved_file_path = std.fs.path.resolve(vm.gpa, &.{ source_dir_path, file_path }) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const file = std.fs.cwd().openFile(resolved_file_path, .{}) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    defer file.close();

    const file_content = file.reader().readAllAlloc(vm.gpa, std.math.maxInt(u32)) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    if (file_content.len == 0) {
        return Code.Value{ .none = {} };
    }

    const file_content_z = @as([:0]u8, @ptrCast(file_content));

    file_content_z[file_content.len] = 0;

    var parser = Parser.init(vm.gpa, file_content_z) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const root = parser.parseRoot() catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ resolved_file_path, parser.error_info.?.source_loc.line, parser.error_info.?.source_loc.column, parser.error_info.?.message });

            std.process.exit(1);
        },
    };

    var gen = CodeGen.init(vm.gpa, .script);

    gen.compileRoot(root) catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ resolved_file_path, gen.error_info.?.source_loc.line, gen.error_info.?.source_loc.column, gen.error_info.?.message });

            std.process.exit(1);
        },
    };

    var other_vm = VirtualMachine.init(vm.gpa, &.{resolved_file_path}) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    other_vm.setCode(gen.code) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    _ = other_vm.run() catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ resolved_file_path, other_vm.error_info.?.source_loc.line, other_vm.error_info.?.source_loc.column, other_vm.error_info.?.message });

            std.process.exit(1);
        },
    };

    return other_vm.exported_value;
}
