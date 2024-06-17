const std = @import("std");

const Code = @import("../Code.zig");
const VirtualMachine = @import("../VirtualMachine.zig");

pub fn getExports(vm: *VirtualMachine) std.mem.Allocator.Error!Code.Value {
    var exports = std.StringHashMap(Code.Value).init(vm.gpa);

    try exports.put("listen", Code.Value.Object.NativeFunction.init(3, &listen));

    return Code.Value.Object.Map.fromStringHashMap(vm.gpa, exports);
}

fn listen(vm: *VirtualMachine, arguments: []const Code.Value) Code.Value {
    const Type = @import("Type.zig");

    if (!(arguments[0] == .object and arguments[0].object == .string)) {
        return Code.Value{ .none = {} };
    }

    const address = arguments[0].object.string.content;

    const port = Type.toInt(vm, arguments[1..]);

    if (port == .none) {
        return Code.Value{ .none = {} };
    }

    if (!(arguments[2] == .object and arguments[2].object == .function)) {
        return Code.Value{ .none = {} };
    }

    const handler = arguments[2].object.function;

    const resolved_address = std.net.Address.resolveIp(address, @intCast(port.int)) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    var net_server = resolved_address.listen(.{ .reuse_address = true }) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    var read_buffer: [1024]u8 = undefined;

    const frame = &vm.frames.items[vm.frames.items.len - 1];

    while (true) {
        const connection = net_server.accept() catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        var http_server = std.http.Server.init(connection, &read_buffer);

        var raw_request = http_server.receiveHead() catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };

        const return_value = callHandlerFunction(vm, frame, handler, &raw_request);

        if (return_value == .none) {
            return Code.Value{ .none = {} };
        }

        const response = Type.toString(vm, &.{return_value});

        raw_request.respond(response.object.string.content, .{}) catch |err| switch (err) {
            else => return Code.Value{ .none = {} },
        };
    }

    return Code.Value{ .none = {} };
}

fn callHandlerFunction(vm: *VirtualMachine, frame: *VirtualMachine.Frame, handler: *Code.Value.Object.Function, raw_request: *std.http.Server.Request) Code.Value {
    if (handler.parameters.len != 1) {
        return Code.Value{ .none = {} };
    }

    const request = rawRequestToMap(vm.gpa, raw_request) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const stack_start = vm.stack.items.len;

    frame.locals.newSnapshot();

    vm.stack.append(request) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    frame.locals.put(handler.parameters[0], stack_start) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    vm.frames.append(.{ .function = handler, .locals = frame.locals }) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const return_value = vm.run() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    vm.stack.shrinkRetainingCapacity(stack_start);

    frame.locals.destroySnapshot();

    _ = vm.frames.pop();

    return return_value;
}

fn rawRequestToMap(gpa: std.mem.Allocator, raw_request: *std.http.Server.Request) std.mem.Allocator.Error!Code.Value {
    var request = std.StringHashMap(Code.Value).init(gpa);

    var headers = std.ArrayList(Code.Value).init(gpa);

    var raw_headers_iterator = raw_request.iterateHeaders();

    while (raw_headers_iterator.next()) |raw_header| {
        var header = std.StringHashMap(Code.Value).init(gpa);

        const value: Code.Value = .{ .object = .{ .string = .{ .content = raw_header.value } } };

        try header.put(raw_header.name, value);

        try headers.append(try Code.Value.Object.Map.fromStringHashMap(gpa, header));
    }

    try request.put("headers", try Code.Value.Object.Array.init(gpa, headers));

    const method = switch (raw_request.head.method) {
        .GET => "GET",
        .PUT,
        => "PUT",
        .HEAD,
        => "HEAD",
        .POST,
        => "POST",
        .TRACE,
        => "TRACE",
        .PATCH,
        => "PATCH",
        .DELETE,
        => "DELETE",
        .CONNECT,
        => "CONNECT",
        .OPTIONS => "OPTIONS",
        _ => "",
    };

    try request.put("method", .{ .object = .{ .string = .{ .content = method } } });

    const raw_request_reader = raw_request.reader() catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    const body = raw_request_reader.readAllAlloc(gpa, std.math.maxInt(u32)) catch |err| switch (err) {
        else => return Code.Value{ .none = {} },
    };

    try request.put("body", .{ .object = .{ .string = .{ .content = body } } });

    return Code.Value.Object.Map.fromStringHashMap(gpa, request);
}
