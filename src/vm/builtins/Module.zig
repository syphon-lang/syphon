const std = @import("std");

const Parser = @import("../../compiler/ast.zig").Parser;
const CodeGen = @import("../../compiler/CodeGen.zig");
const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

const NativeModuleGetters = std.StaticStringMap(*const fn (*VirtualMachine) std.mem.Allocator.Error!Code.Value).initComptime(.{
    .{ "fs", &(@import("FileSystem.zig").getExports) },
    .{ "io", &(@import("IO.zig").getExports) },
    .{ "math", &(@import("Math.zig").getExports) },
    .{ "process", &(@import("Process.zig").getExports) },
});

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("export", Code.Value.Object.NativeFunction.init(1, &@"export"));
    try vm.globals.put("import", Code.Value.Object.NativeFunction.init(1, &import));
}

fn @"export"(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    vm.exported = arguments[0];

    return Code.Value{ .none = {} };
}

fn import(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const file_path = arguments[0].object.string.content;

    if (NativeModuleGetters.get(file_path)) |getNativeModule| {
        return getNativeModule(vm) catch Code.Value{ .none = {} };
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
        else => return Code.Value{ .none = {} },
    };

    const file = std.fs.cwd().openFile(resolved_file_path, .{}) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    defer file.close();

    const file_content = file.reader().readAllAlloc(vm.allocator, std.math.maxInt(u32)) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    if (file_content.len == 0) {
        return Code.Value{ .none = {} };
    }

    const file_content_z = @as([:0]u8, @ptrCast(file_content));

    file_content_z[file_content.len] = 0;

    var parser = Parser.init(vm.allocator, file_content_z) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const root = parser.parseRoot() catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ resolved_file_path, parser.error_info.?.source_loc.line, parser.error_info.?.source_loc.column, parser.error_info.?.message });

            std.process.exit(1);
        },
    };

    var gen = CodeGen.init(vm.allocator, .script);

    gen.compileRoot(root) catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ resolved_file_path, gen.error_info.?.source_loc.line, gen.error_info.?.source_loc.column, gen.error_info.?.message });

            std.process.exit(1);
        },
    };

    var other_vm = VirtualMachine.init(vm.allocator, &.{resolved_file_path}) catch |err| switch (err) {
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

    return other_vm.exported;
}
