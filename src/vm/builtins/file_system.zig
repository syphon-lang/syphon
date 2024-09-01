const std = @import("std");
const builtin = @import("builtin");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("open", try Code.Value.NativeFunction.init(vm.allocator, 1, &open));
    try exports.put("create", try Code.Value.NativeFunction.init(vm.allocator, 1, &create));
    try exports.put("delete", try Code.Value.NativeFunction.init(vm.allocator, 1, &delete));
    try exports.put("close", try Code.Value.NativeFunction.init(vm.allocator, 1, &close));
    try exports.put("cwd", try Code.Value.NativeFunction.init(vm.allocator, 0, &cwd));
    try exports.put("chdir", try Code.Value.NativeFunction.init(vm.allocator, 1, &chdir));
    try exports.put("access", try Code.Value.NativeFunction.init(vm.allocator, 1, &access));
    try exports.put("write", try Code.Value.NativeFunction.init(vm.allocator, 2, &write));
    try exports.put("read", try Code.Value.NativeFunction.init(vm.allocator, 1, &read));
    try exports.put("read_line", try Code.Value.NativeFunction.init(vm.allocator, 1, &readLine));
    try exports.put("read_all", try Code.Value.NativeFunction.init(vm.allocator, 1, &readAll));

    return Code.Value.Map.fromStringHashMap(vm.allocator, exports);
}

fn open(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] == .string) {
        return .none;
    }

    const file_path = arguments[0].string.content;

    const file = std.fs.cwd().openFile(file_path, .{ .mode = .read_write }) catch return .none;

    if (builtin.os.tag == .windows) {
        return Code.Value{ .int = @bitCast(@as(u64, @intFromPtr(file.handle))) };
    } else {
        return Code.Value{ .int = @intCast(file.handle) };
    }
}

fn create(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] == .string) {
        return .none;
    }

    const file_path = arguments[0].string.content;

    const file = std.fs.cwd().createFile(file_path, .{ .truncate = false, .read = true }) catch return .none;

    if (builtin.os.tag == .windows) {
        return Code.Value{ .int = @bitCast(@as(u64, @intFromPtr(file.handle))) };
    } else {
        return Code.Value{ .int = @intCast(file.handle) };
    }
}

fn getFile(argument: Code.Value) std.fs.File {
    if (builtin.os.tag == .windows) {
        return std.fs.File{ .handle = @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(argument.int))))) };
    } else {
        return std.fs.File{ .handle = @intCast(argument.int) };
    }
}

fn delete(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] == .string) {
        return .none;
    }

    const file_path = arguments[0].string.content;

    std.fs.cwd().deleteFile(file_path) catch return .none;

    return .none;
}

fn close(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] != .int) {
        return .none;
    }

    const file = getFile(arguments[0]);

    file.close();

    return .none;
}

fn cwd(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = arguments;

    const cwd_file_path = std.fs.cwd().realpathAlloc(vm.allocator, ".") catch return .none;

    return Code.Value{ .string = .{ .content = cwd_file_path } };
}

fn chdir(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] == .string) {
        return .none;
    }

    const dir_path = arguments[0].string.content;

    const dir = std.fs.cwd().openDir(dir_path, .{}) catch return .none;

    dir.setAsCwd() catch return .none;

    return .none;
}

fn access(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] == .string) {
        return .none;
    }

    const file_path = arguments[0].string.content;

    std.fs.cwd().access(file_path, .{ .mode = .read_write }) catch return Code.Value{ .boolean = false };

    return Code.Value{ .boolean = true };
}

fn write(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    _ = vm;

    if (arguments[0] != .int) {
        return .none;
    }

    if (arguments[1] == .string) {
        return .none;
    }

    const file = getFile(arguments[0]);

    const write_content = arguments[1].string.content;

    var buffered_writer = std.io.bufferedWriter(file.writer());

    buffered_writer.writer().writeAll(write_content) catch return .none;

    buffered_writer.flush() catch return .none;

    return .none;
}

fn read(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return .none;
    }

    const file = getFile(arguments[0]);

    const buffer = vm.allocator.alloc(u8, 1) catch return .none;

    const read_amount = file.reader().read(buffer) catch return .none;

    if (read_amount == 0) {
        return .none;
    }

    return Code.Value{ .string = .{ .content = buffer } };
}

fn readLine(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return .none;
    }

    const file = getFile(arguments[0]);

    const file_content = file.reader().readUntilDelimiterOrEofAlloc(vm.allocator, '\n', std.math.maxInt(u32)) catch return .none;

    if (file_content == null) {
        return .none;
    }

    return Code.Value{ .string = .{ .content = file_content.? } };
}

fn readAll(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return .none;
    }

    const file = getFile(arguments[0]);

    const file_content = file.readToEndAlloc(vm.allocator, std.math.maxInt(u32)) catch return .none;

    return Code.Value{ .string = .{ .content = file_content } };
}
