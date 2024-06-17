const std = @import("std");

const Parser = @import("../../compiler/ast.zig").Parser;
const CodeGen = @import("../../compiler/CodeGen.zig");
const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("export", Code.Value.Object.NativeFunction.init("export", 1, &@"export"));
    try vm.globals.put("import", Code.Value.Object.NativeFunction.init("import", 1, &import));
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

    if (std.mem.eql(u8, file_path, "math")) {
        return getMathModule(vm.gpa);
    } else if (std.mem.eql(u8, file_path, "fs")) {
        return getFileSystemModule(vm.gpa);
    } else if (std.mem.eql(u8, file_path, "process")) {
        return getProcessModule(vm);
    } else if (std.mem.eql(u8, file_path, "http")) {
        return getHttpModule(vm.gpa);
    } else {
        return getExportedValue(vm, file_path);
    }
}

fn getMathModule(gpa: std.mem.Allocator) Code.Value {
    const Math = @import("Math.zig");

    const exports = Math.getExports(gpa) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return exports;
}

fn getFileSystemModule(gpa: std.mem.Allocator) Code.Value {
    const FileSystem = @import("FileSystem.zig");

    const exports = FileSystem.getExports(gpa) catch |err| switch (err) {
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

fn getHttpModule(gpa: std.mem.Allocator) Code.Value {
    const Http = @import("Http.zig");

    const exports = Http.getExports(gpa) catch |err| switch (err) {
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
        else => return Code.Value{ .none = {} },
    };

    var gen = CodeGen.init(vm.gpa, .script);

    gen.compileRoot(root) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    var other_vm = VirtualMachine.init(vm.gpa, &.{resolved_file_path}) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    other_vm.addGlobals() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    other_vm.setCode(gen.code) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    _ = other_vm.run() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return other_vm.exported_value;
}
