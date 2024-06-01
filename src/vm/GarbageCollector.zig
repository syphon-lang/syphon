const std = @import("std");

const VirtualMachine = @import("VirtualMachine.zig");

const GarbageCollector = @This();

gpa: std.mem.Allocator,

roots: std.ArrayList(*std.ArrayList(VirtualMachine.Code.Value)),

objects: std.ArrayList(ObjectInfo),

strings: std.ArrayList([]u8),

bytes_allocated: usize = 0,
next_collect: usize = 1024 * 1024,

debug: bool = false,

pub const ObjectInfo = struct {
    value: VirtualMachine.Code.Value,
    marked: bool,
};

pub fn init(gpa: std.mem.Allocator) GarbageCollector {
    return GarbageCollector{ .gpa = gpa, .roots = std.ArrayList(*std.ArrayList(VirtualMachine.Code.Value)).init(gpa), .objects = std.ArrayList(ObjectInfo).init(gpa), .strings = std.ArrayList([]u8).init(gpa) };
}

pub fn allocator(self: *GarbageCollector) std.mem.Allocator {
    return std.mem.Allocator{ .ptr = self, .vtable = &.{
        .alloc = &alloc,
        .resize = &resize,
        .free = &free,
    } };
}

fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    const self: *GarbageCollector = @ptrCast(@alignCast(ctx));

    const buf = self.gpa.rawAlloc(len, ptr_align, ret_addr);

    if (buf != null) {
        self.bytes_allocated += len;

        self.collect() catch |err| switch (err) {
            error.OutOfMemory => return null,
        };
    }

    return buf;
}

fn resize(
    ctx: *anyopaque,
    buf: []u8,
    log2_buf_align: u8,
    new_len: usize,
    ret_addr: usize,
) bool {
    const self: *GarbageCollector = @ptrCast(@alignCast(ctx));

    const old_len = buf.len;

    const resized = self.gpa.rawResize(buf, log2_buf_align, new_len, ret_addr);

    if (resized and new_len > old_len) {
        self.bytes_allocated += new_len - old_len;

        self.collect() catch |err| switch (err) {
            error.OutOfMemory => return false,
        };
    }

    return resized;
}

fn free(
    ctx: *anyopaque,
    buf: []u8,
    log2_buf_align: u8,
    ret_addr: usize,
) void {
    const self: *GarbageCollector = @ptrCast(@alignCast(ctx));

    const len = buf.len;

    self.gpa.rawFree(buf, log2_buf_align, ret_addr);

    self.bytes_allocated -= len;
}

pub fn intern(self: *GarbageCollector, string: []const u8) std.mem.Allocator.Error![]u8 {
    for (self.strings.items) |internal_string| {
        if (std.mem.eql(u8, internal_string, string)) {
            return internal_string;
        }
    }

    const internal_string = try self.allocator().alloc(u8, string.len);
    std.mem.copyForwards(u8, internal_string, string);

    try self.strings.append(internal_string);

    return internal_string;
}

fn should_collect(self: GarbageCollector) bool {
    return self.bytes_allocated > self.next_collect;
}

pub fn collect(self: *GarbageCollector) std.mem.Allocator.Error!void {
    if (self.should_collect()) {
        const old_size = self.bytes_allocated;

        try self.markRoots();

        try self.traceReferences();

        self.removeUnusedStrings();

        self.sweep();

        const new_size = self.bytes_allocated;

        self.next_collect = self.bytes_allocated * 2;

        if (self.debug) {
            std.debug.print("gc: collect(old_size = {}, new_size = {}, freed = {}, next_collect = {})\n", .{ old_size, new_size, old_size - new_size, self.next_collect });
        }
    }
}

pub fn traceReferences(self: *GarbageCollector) std.mem.Allocator.Error!void {
    for (self.objects.items) |object_info| {
        if (object_info.marked) {
            try self.markValueReferences(object_info.value);
        }
    }
}

pub fn markRoots(self: *GarbageCollector) std.mem.Allocator.Error!void {
    for (self.roots.items) |root_value_list| {
        for (root_value_list.items) |root_value| {
            try self.markValue(root_value);
        }
    }
}

pub fn markValueReferences(self: *GarbageCollector, value: VirtualMachine.Code.Value) std.mem.Allocator.Error!void {
    switch (value) {
        .object => switch (value.object) {
            .string => {},

            .array => {
                try self.markValueList(value.object.array.values);
            },

            .function => {
                try self.markValueList(value.object.function.code.constants);
            },

            .native_function => {},
        },

        else => {},
    }
}

pub fn markValueList(self: *GarbageCollector, value_list: std.ArrayList(VirtualMachine.Code.Value)) std.mem.Allocator.Error!void {
    for (value_list.items) |value| {
        try self.markValue(value);
    }
}

pub fn markValue(self: *GarbageCollector, value: VirtualMachine.Code.Value) std.mem.Allocator.Error!void {
    if (self.debug) {
        std.debug.print("gc: mark()\n", .{});
    }

    for (0..self.objects.items.len) |i| {
        if (self.objects.items[i].value.eql(value, true)) {
            self.objects.items[i].marked = true;
        } else {
            try self.objects.append(.{ .value = value, .marked = true });
        }
    }
}

pub fn sweep(self: *GarbageCollector) void {
    if (self.debug) {
        std.debug.print("gc: sweep()\n", .{});
    }

    var i: usize = 0;

    while (i < self.objects.items.len) {
        if (self.objects.items[i].marked) {
            self.objects.items[i].marked = false;
        } else {
            self.destroyObject(self.objects.items[i]);

            _ = self.objects.swapRemove(i);

            continue;
        }

        i += 1;
    }
}

fn destroyObject(self: *GarbageCollector, object_info: ObjectInfo) void {
    if (self.debug) {
        std.debug.print("gc: destroy()\n", .{});
    }

    switch (object_info.value) {
        .object => switch (object_info.value.object) {
            .string => self.allocator().free(object_info.value.object.string.content),

            .array => {
                object_info.value.object.array.values.deinit();
                self.allocator().destroy(object_info.value.object.array);
            },

            .function => {
                object_info.value.object.function.code.constants.deinit();
                object_info.value.object.function.code.instructions.deinit();
                self.allocator().destroy(object_info.value.object.function);
            },

            .native_function => {},
        },

        else => {},
    }
}

fn removeUnusedStrings(self: *GarbageCollector) void {
    var i: usize = 0;

    while (i < self.strings.items.len) {
        var used = false;

        for (self.objects.items) |object_info| {
            if (object_info.value == .object and object_info.value.object == .string and object_info.value.object.string.content.ptr == self.strings.items[i].ptr and object_info.marked) {
                used = true;
            }
        }

        if (!used) {
            self.allocator().free(self.strings.items[i]);

            _ = self.strings.swapRemove(i);

            continue;
        }

        i += 1;
    }
}
