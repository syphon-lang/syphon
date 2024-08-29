const std = @import("std");

const Atom = @This();

var atoms: std.StringHashMap(Atom) = undefined;

id: u32,

pub fn init(allocator: std.mem.Allocator) void {
    atoms = std.StringHashMap(Atom).init(allocator);
}

pub fn new(name: []const u8) std.mem.Allocator.Error!Atom {
    if (atoms.get(name)) |atom| {
        return atom;
    }

    const atom: Atom = .{ .id = atoms.count() };

    try atoms.put(name, atom);

    return atom;
}

pub fn toName(self: Atom) []const u8 {
    var atom_iterator = atoms.iterator();

    while (atom_iterator.next()) |atom_entry| {
        if (atom_entry.value_ptr.id == self.id) {
            return atom_entry.key_ptr.*;
        }
    }

    unreachable;
}
