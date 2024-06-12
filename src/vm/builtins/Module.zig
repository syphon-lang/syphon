const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");
const Parser = @import("../../compiler/ast.zig").Parser;
const CodeGen = @import("../../compiler/CodeGen.zig");

pub fn addGlobals(vm: *VirtualMachine) std.mem.Allocator.Error!void {
    try vm.globals.put("export", .{ .object = .{ .native_function = .{ .name = "export", .required_arguments_count = 2, .call = &_export } } });
    try vm.globals.put("import", .{ .object = .{ .native_function = .{ .name = "import", .required_arguments_count = 1, .call = &import } } });
}

pub fn _export(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const name = arguments[0].object.string.content;

    const value = arguments[1];

    vm.exports.put(name, value) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("ran out of memory\n", .{});
            std.process.exit(1);
        },
    };

    return VirtualMachine.Code.Value{ .none = {} };
}

pub fn import(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const file_path = arguments[0].object.string.content;

    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    defer file.close();

    const file_content = file.reader().readAllAlloc(vm.gpa, std.math.maxInt(u32)) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    const file_content_z = @as([:0]u8, @ptrCast(file_content));

    if (file_content.len != 0) {
        file_content_z[file_content.len] = 0;
    }

    var parser = Parser.init(vm.gpa, file_content_z) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    const root = parser.parseRoot() catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    var gen = CodeGen.init(vm.gpa, .script);

    gen.compileRoot(root) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    var other_vm = VirtualMachine.init(vm.gpa) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    other_vm.addGlobals() catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    other_vm.setCode(gen.code) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    _ = other_vm.run() catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    var exports_map_inner = VirtualMachine.Code.Value.Object.Map.Inner.init(vm.gpa);

    var export_entries_iterator = other_vm.exports.iterator();

    while (export_entries_iterator.next()) |export_entry| {
        const export_entry_key: VirtualMachine.Code.Value = .{ .object = .{ .string = .{ .content = export_entry.key_ptr.* } } };

        exports_map_inner.put(export_entry_key, export_entry.value_ptr.*) catch |err| switch (err) {
            else => return VirtualMachine.Code.Value{ .none = {} },
        };
    }

    const exports_map: VirtualMachine.Code.Value.Object.Map = .{ .inner = exports_map_inner };

    var exports_map_on_heap = vm.gpa.alloc(VirtualMachine.Code.Value.Object.Map, 1) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    exports_map_on_heap[0] = exports_map;

    return VirtualMachine.Code.Value{ .object = .{ .map = &exports_map_on_heap[0] } };
}
