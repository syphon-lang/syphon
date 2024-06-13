const std = @import("std");

const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(gpa: std.mem.Allocator) std.mem.Allocator.Error!VirtualMachine.Code.Value {
    var exports = std.StringHashMap(VirtualMachine.Code.Value).init(gpa);

    try exports.put("open", .{ .object = .{ .native_function = .{ .name = "open", .required_arguments_count = 1, .call = &open } } });
    try exports.put("delete", .{ .object = .{ .native_function = .{ .name = "delete", .required_arguments_count = 1, .call = &delete } } });
    try exports.put("close", .{ .object = .{ .native_function = .{ .name = "close", .required_arguments_count = 1, .call = &close } } });
    try exports.put("close_all", .{ .object = .{ .native_function = .{ .name = "close_all", .required_arguments_count = 0, .call = &closeAll } } });
    try exports.put("cwd", .{ .object = .{ .native_function = .{ .name = "cwd", .required_arguments_count = 0, .call = &cwd } } });
    try exports.put("chdir", .{ .object = .{ .native_function = .{ .name = "chdir", .required_arguments_count = 1, .call = &chdir } } });
    try exports.put("write", .{ .object = .{ .native_function = .{ .name = "write", .required_arguments_count = 2, .call = &write } } });
    try exports.put("read", .{ .object = .{ .native_function = .{ .name = "read", .required_arguments_count = 1, .call = &read } } });
    try exports.put("read_line", .{ .object = .{ .native_function = .{ .name = "read_line", .required_arguments_count = 1, .call = &readLine } } });
    try exports.put("read_all", .{ .object = .{ .native_function = .{ .name = "read_all", .required_arguments_count = 1, .call = &readAll } } });

    return VirtualMachine.Code.Value.Object.Map.fromStringHashMap(gpa, exports);
}

fn open(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const file_path = arguments[0].object.string.content;

    const file = std.fs.cwd().createFile(file_path, .{ .truncate = false, .read = true }) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    vm.open_files.put(file.handle, file) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    return VirtualMachine.Code.Value{ .int = @intCast(file.handle) };
}

fn delete(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const file_path = arguments[0].object.string.content;

    std.fs.cwd().deleteFile(file_path) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    return VirtualMachine.Code.Value{ .none = {} };
}

fn close(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    if (arguments[0] != .int) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const file_location: i32 = @intCast(arguments[0].int);

    if (vm.open_files.get(file_location)) |file| {
        file.close();

        _ = vm.open_files.remove(file_location);
    }

    return VirtualMachine.Code.Value{ .none = {} };
}

fn closeAll(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = arguments;

    var open_files_iterator = vm.open_files.iterator();

    while (open_files_iterator.next()) |file_entry| {
        file_entry.value_ptr.close();
    }

    return VirtualMachine.Code.Value{ .none = {} };
}

fn cwd(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = arguments;

    const cwd_file_path = std.fs.cwd().realpathAlloc(vm.gpa, ".") catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    return VirtualMachine.Code.Value{ .object = .{ .string = .{ .content = cwd_file_path } } };
}

fn chdir(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const dir_path = arguments[0].object.string.content;

    const dir = std.fs.cwd().openDir(dir_path, .{}) catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    dir.setAsCwd() catch |err| switch (err) {
        else => return VirtualMachine.Code.Value{ .none = {} },
    };

    return VirtualMachine.Code.Value{ .none = {} };
}

fn write(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    if (arguments[0] != .int) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    if (!(arguments[1] == .object and arguments[1].object == .string)) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const file_location: i32 = @intCast(arguments[0].int);

    const write_content = arguments[1].object.string.content;

    if (vm.open_files.get(file_location)) |file| {
        var buffered_writer = std.io.bufferedWriter(file.writer());

        buffered_writer.writer().writeAll(write_content) catch |err| switch (err) {
            else => return VirtualMachine.Code.Value{ .none = {} },
        };

        buffered_writer.flush() catch |err| switch (err) {
            else => return VirtualMachine.Code.Value{ .none = {} },
        };
    }

    return VirtualMachine.Code.Value{ .none = {} };
}

fn read(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    if (arguments[0] != .int) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const file_location: i32 = @intCast(arguments[0].int);

    if (vm.open_files.get(file_location)) |file| {
        const buf = vm.gpa.alloc(u8, 1) catch |err| switch (err) {
            else => return VirtualMachine.Code.Value{ .none = {} },
        };

        const n = file.reader().read(buf) catch |err| switch (err) {
            else => return VirtualMachine.Code.Value{ .none = {} },
        };

        if (n == 0) {
            return VirtualMachine.Code.Value{ .object = .{ .string = .{ .content = "" } } };
        }

        return VirtualMachine.Code.Value{ .object = .{ .string = .{ .content = buf } } };
    }

    return VirtualMachine.Code.Value{ .none = {} };
}

fn readLine(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    if (arguments[0] != .int) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const file_location: i32 = @intCast(arguments[0].int);

    if (vm.open_files.get(file_location)) |file| {
        const file_content = file.reader().readUntilDelimiterOrEofAlloc(vm.gpa, '\n', std.math.maxInt(u32)) catch |err| switch (err) {
            else => return VirtualMachine.Code.Value{ .none = {} },
        } orelse "";

        return VirtualMachine.Code.Value{ .object = .{ .string = .{ .content = file_content } } };
    }

    return VirtualMachine.Code.Value{ .none = {} };
}

fn readAll(vm: *VirtualMachine, arguments: []const VirtualMachine.Code.Value) VirtualMachine.Code.Value {
    if (arguments[0] != .int) {
        return VirtualMachine.Code.Value{ .none = {} };
    }

    const file_location: i32 = @intCast(arguments[0].int);

    if (vm.open_files.get(file_location)) |file| {
        const file_content = file.reader().readAllAlloc(vm.gpa, std.math.maxInt(u32)) catch |err| switch (err) {
            else => return VirtualMachine.Code.Value{ .none = {} },
        };

        return VirtualMachine.Code.Value{ .object = .{ .string = .{ .content = file_content } } };
    }

    return VirtualMachine.Code.Value{ .none = {} };
}
