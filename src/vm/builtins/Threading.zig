const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("spawn", Code.Value.Object.NativeFunction.init(2, &spawn));
    try exports.put("join", Code.Value.Object.NativeFunction.init(1, &join));

    return Code.Value.Object.Map.fromStringHashMap(vm.allocator, exports);
}

fn spawn(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (!(arguments[0] == .object and arguments[0].object == .function)) {
        return .none;
    }

    if (!(arguments[1] == .object and arguments[1].object == .array)) {
        return .none;
    }

    const thread_function = arguments[0].object.function;

    const thread_arguments = arguments[1].object.array;

    if (thread_arguments.values.items.len != thread_function.parameters.len) {
        return .none;
    }

    const thread = std.Thread.spawn(.{ .allocator = vm.allocator }, callThreadFunction, .{ vm, thread_function, thread_arguments.values.items }) catch |err| switch (err) {
        else => return .none,
    };

    vm.mutex.unlock();
    defer vm.mutex.lock();

    std.Thread.yield() catch {};

    const thread_on_heap = vm.allocator.create(std.Thread) catch |err| switch (err) {
        else => return .none,
    };

    thread_on_heap.* = thread;

    return Code.Value{ .int = @bitCast(@as(u64, @intFromPtr(thread_on_heap))) };
}

fn callThreadFunction(vm: *VirtualMachine, function: *Code.Value.Object.Function, arguments: []const Code.Value) void {
    vm.mutex.lock();
    defer vm.mutex.unlock();

    vm.stack.appendSlice(arguments) catch |err| switch (err) {
        else => return,
    };

    vm.callUserFunction(function) catch |err| switch (err) {
        else => return,
    };

    vm.run() catch |err| switch (err) {
        else => return,
    };
}

fn join(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .int) {
        return .none;
    }

    const thread: *std.Thread = @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(arguments[0].int)))));

    vm.mutex.unlock();
    defer vm.mutex.lock();

    std.Thread.yield() catch {};

    thread.join();

    return .none;
}
