const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(gpa: std.mem.Allocator) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(gpa);

    try exports.put("listen", Code.Value.Object.NativeFunction.init("listen", 2, &listen));

    return Code.Value.Object.Map.fromStringHashMap(gpa, exports);
}

fn listen(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Console = @import("Console.zig");
    const Type = @import("Type.zig");

    const port = Type.to_int(vm, arguments);

    if (port == .none) {
        return Code.Value{ .none = {} };
    }

    if (!(arguments[1] == .object and arguments[1].object == .function)) {
        return Code.Value{ .none = {} };
    }

    const handler = arguments[1].object.function;

    const address = std.net.Address.resolveIp("0.0.0.0", @intCast(port.int)) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    var listener = address.listen(.{ .reuse_address = true }) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    var read_buffer: [1024]u8 = undefined;

    const frame = &vm.frames.items[vm.frames.items.len - 1];

    while (true) {
        const connection = listener.accept() catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        var server = std.http.Server.init(connection, &read_buffer);

        var request = server.receiveHead() catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        const stack_start = vm.stack.items.len;

        frame.locals.newSnapshot();

        vm.frames.append(.{ .function = handler, .locals = frame.locals }) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        const response_value = vm.run() catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        vm.stack.shrinkRetainingCapacity(stack_start);

        frame.locals.destroySnapshot();

        _ = vm.frames.pop();

        var response = std.ArrayList(u8).init(vm.gpa);

        var buffered_writer = std.io.bufferedWriter(response.writer());

        Console._print(std.ArrayList(u8).Writer, &buffered_writer, &.{response_value}, false) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        buffered_writer.flush() catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        const response_owned = response.toOwnedSlice() catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        request.respond(response_owned, .{}) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };
    }

    return Code.Value{ .none = {} };
}
