const std = @import("std");

const bdwgc = @cImport({
    @cInclude("gc.h");
});

pub fn allocator() std.mem.Allocator {
    if (bdwgc.GC_is_init_called() == 0) {
        bdwgc.GC_init();
    }

    bdwgc.GC_set_warn_proc(&bdwgc.GC_ignore_warn_proc);

    bdwgc.GC_enable_incremental();

    return std.mem.Allocator{
        .ptr = undefined,
        .vtable = &.{
            .alloc = &alloc,
            .resize = &resize,
            .free = &free,
        },
    };
}

fn getHeader(ptr: [*]u8) *[*]u8 {
    return @as(*[*]u8, @ptrFromInt(@intFromPtr(ptr) - @sizeOf(usize)));
}

fn alignedAlloc(len: usize, log2_align: u8) ?[*]u8 {
    const alignment = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_align));

    // Thin wrapper around regular malloc, overallocate to account for
    // alignment padding and store the original malloc()'ed pointer before
    // the aligned address.
    const unaligned_ptr = @as([*]u8, @ptrCast(bdwgc.GC_malloc(len + alignment - 1 + @sizeOf(usize)) orelse return null));
    const unaligned_addr = @intFromPtr(unaligned_ptr);
    const aligned_addr = std.mem.alignForward(usize, unaligned_addr + @sizeOf(usize), alignment);
    const aligned_ptr = unaligned_ptr + (aligned_addr - unaligned_addr);
    getHeader(aligned_ptr).* = unaligned_ptr;

    return aligned_ptr;
}

fn alignedFree(ptr: [*]u8) void {
    const unaligned_ptr = getHeader(ptr).*;
    bdwgc.GC_free(unaligned_ptr);
}

fn alignedAllocSize(ptr: [*]u8) usize {
    const unaligned_ptr = getHeader(ptr).*;
    const delta = @intFromPtr(ptr) - @intFromPtr(unaligned_ptr);
    return bdwgc.GC_size(unaligned_ptr) - delta;
}

fn alloc(
    _: *anyopaque,
    len: usize,
    log2_align: u8,
    return_address: usize,
) ?[*]u8 {
    _ = return_address;
    std.debug.assert(len > 0);
    return alignedAlloc(len, log2_align);
}

fn resize(
    _: *anyopaque,
    buf: []u8,
    log2_buf_align: u8,
    new_len: usize,
    return_address: usize,
) bool {
    _ = log2_buf_align;
    _ = return_address;
    if (new_len <= buf.len) {
        return true;
    }

    const full_len = alignedAllocSize(buf.ptr);
    if (new_len <= full_len) {
        return true;
    }

    return false;
}

fn free(
    _: *anyopaque,
    buf: []u8,
    log2_buf_align: u8,
    return_address: usize,
) void {
    _ = log2_buf_align;
    _ = return_address;
    alignedFree(buf.ptr);
}
