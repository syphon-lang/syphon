const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.allocator);

    try exports.put("spawn", try Code.Value.NativeFunction.init(vm.allocator, 2, &spawn));
    try exports.put("join", try Code.Value.NativeFunction.init(vm.allocator, 1, &join));

    return Code.Value.Map.fromStringHashMap(vm.allocator, exports);
}

fn spawn(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    if (arguments[0] != .closure) {
        return .none;
    }

    if (arguments[1] != .array) {
        return .none;
    }

    const thread_closure = arguments[0].closure;

    const thread_arguments = arguments[1].array;

    if (thread_arguments.inner.items.len != thread_closure.function.parameters.len) {
        return .none;
    }

    const thread = std.Thread.spawn(.{ .allocator = vm.allocator }, callThreadFunction, .{ vm, thread_closure, thread_arguments.inner.items }) catch return .none;

    vm.mutex.unlock();
    defer vm.mutex.lock();

    std.Thread.yield() catch {};

    const thread_on_heap = vm.allocator.create(std.Thread) catch return .none;

    thread_on_heap.* = thread;

    return Code.Value{ .int = @bitCast(@as(u64, @intFromPtr(thread_on_heap))) };
}

fn callThreadFunction(vm: *VirtualMachine, closure: *Code.Value.Closure, arguments: []const Code.Value) void {
    vm.mutex.lock();
    defer vm.mutex.unlock();

    vm.stack.appendSlice(arguments) catch return;

    vm.callUserFunction(closure) catch return;

    vm.run() catch return;
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
