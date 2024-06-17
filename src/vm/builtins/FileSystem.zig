const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.gpa);

    try exports.put("open", Code.Value.Object.NativeFunction.init("open", 1, &open));
    try exports.put("delete", Code.Value.Object.NativeFunction.init("delete", 1, &delete));
    try exports.put("close", Code.Value.Object.NativeFunction.init("close", 1, &close));
    try exports.put("cwd", Code.Value.Object.NativeFunction.init("cwd", 0, &cwd));
    try exports.put("chdir", Code.Value.Object.NativeFunction.init("chdir", 1, &chdir));
    try exports.put("access", Code.Value.Object.NativeFunction.init("access", 1, &access));
    try exports.put("write", Code.Value.Object.NativeFunction.init("write", 2, &write));
    try exports.put("read", Code.Value.Object.NativeFunction.init("read", 1, &read));
    try exports.put("read_line", Code.Value.Object.NativeFunction.init("read_line", 1, &readLine));
    try exports.put("read_all", Code.Value.Object.NativeFunction.init("read_all", 1, &readAll));

    return Code.Value.Object.Map.fromStringHashMap(vm.gpa, exports);
}

fn open(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const file_path = arguments[0].object.string.content;

    const file = std.fs.cwd().createFile(file_path, .{ .truncate = false, .read = true }) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .int = @intCast(file.handle) };
}

fn delete(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const file_path = arguments[0].object.string.content;

    std.fs.cwd().deleteFile(file_path) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .none = {} };
}

fn close(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] != .int) {
        return Code.Value{ .none = {} };
    }

    const fd: i32 = @intCast(arguments[0].int);

    const file: std.fs.File = .{ .handle = fd };

    file.close();

    return Code.Value{ .none = {} };
}

fn cwd(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = arguments;

    const cwd_file_path = std.fs.cwd().realpathAlloc(vm.gpa, ".") catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .object = .{ .string = .{ .content = cwd_file_path } } };
}

fn chdir(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const dir_path = arguments[0].object.string.content;

    const dir = std.fs.cwd().openDir(dir_path, .{}) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    dir.setAsCwd() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .none = {} };
}

fn access(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const file_path = arguments[0].object.string.content;

    std.fs.cwd().access(file_path, .{ .mode = .read_write }) catch |err| switch (err) {
        else => return Code.Value{ .boolean = false },
    };

    return Code.Value{ .boolean = true };
}

fn write(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] != .int) {
        return Code.Value{ .none = {} };
    }

    if (!(arguments[1] == .object and arguments[1].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const fd: i32 = @intCast(arguments[0].int);

    const file: std.fs.File = .{ .handle = fd };

    const write_content = arguments[1].object.string.content;

    var buffered_writer = std.io.bufferedWriter(file.writer());

    buffered_writer.writer().writeAll(write_content) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    buffered_writer.flush() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .none = {} };
}

fn read(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return Code.Value{ .none = {} };
    }

    const fd: i32 = @intCast(arguments[0].int);

    const file: std.fs.File = .{ .handle = fd };

    const buf = vm.gpa.alloc(u8, 1) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const n = file.reader().read(buf) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    if (n == 0) {
        return Code.Value{ .object = .{ .string = .{ .content = "" } } };
    }

    return Code.Value{ .object = .{ .string = .{ .content = buf } } };
}

fn readLine(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return Code.Value{ .none = {} };
    }

    const fd: i32 = @intCast(arguments[0].int);

    const file: std.fs.File = .{ .handle = fd };

    const file_content = file.reader().readUntilDelimiterOrEofAlloc(vm.gpa, '\n', std.math.maxInt(u32)) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    } orelse "";

    return Code.Value{ .object = .{ .string = .{ .content = file_content } } };
}

fn readAll(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return Code.Value{ .none = {} };
    }

    const fd: i32 = @intCast(arguments[0].int);

    const file: std.fs.File = .{ .handle = fd };

    const file_content = file.reader().readAllAlloc(vm.gpa, std.math.maxInt(u32)) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    return Code.Value{ .object = .{ .string = .{ .content = file_content } } };
}
