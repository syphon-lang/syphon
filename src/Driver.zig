const std = @import("std");

const Parser = @import("compiler/ast.zig").Parser;
const CodeGen = @import("compiler/CodeGen.zig");
const VirtualMachine = @import("vm/VirtualMachine.zig");

const Driver = @This();

gpa: std.mem.Allocator,

cli: CLI,

const CLI = struct {
    command: ?Command = null,

    const Command = union(enum) {
        run: Run,

        const Run = struct {
            file_path: []const u8,
        };
    };
};

const usage =
    \\Usage: 
    \\  {s} <command> [arguments]
    \\
    \\Commands:
    \\  run <file_path>     -- run certain file
    \\
    \\
;

const run_command_usage =
    \\Usage:
    \\  {s} run <file_path>
    \\
    \\
;

pub fn errorDescription(e: anyerror) []const u8 {
    return switch (e) {
        error.OutOfMemory => "ran out of memory",
        error.FileNotFound => "no such file or directory",
        error.IsDir => "is a directory",
        error.NotDir => "is not a directory",
        error.NotOpenForReading => "is not open for reading",
        error.NotOpenForWriting => "is not open for writing",
        error.InvalidUtf8 => "invalid UTF-8",
        error.FileBusy => "file is busy",
        error.NameTooLong => "name is too long",
        error.AccessDenied => "access denied",
        error.FileTooBig, error.StreamTooLong => "file is too big",
        error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded => "ran out of file descriptors",
        error.SystemResources => "ran out of system resources",
        error.FatalError => "a fatal error occurred",
        error.Unexpected => "an unexpected error occurred",
        error.Unsupported => "this platform is unsupported",
        else => @errorName(e),
    };
}

pub fn init(gpa: std.mem.Allocator) Driver {
    return Driver{ .gpa = gpa, .cli = .{} };
}

fn parseArgs(self: *Driver, args_iterator: *std.process.ArgIterator) bool {
    const program = args_iterator.next().?;

    while (args_iterator.next()) |arg| {
        if (std.mem.eql(u8, arg, "run")) {
            if (args_iterator.next()) |file_path| {
                self.cli.command = .{ .run = .{ .file_path = file_path } };

                return false;
            } else {
                std.debug.print(run_command_usage, .{program});

                std.debug.print("Error: expected a file path\n", .{});
            }
        } else {
            std.debug.print(usage, .{program});

            std.debug.print("Error: {s} is an unknown command\n", .{arg});
        }

        return true;
    }

    if (self.cli.command != null) {
        return false;
    }

    std.debug.print(usage, .{program});

    std.debug.print("Error: no command provided\n", .{});

    return true;
}

pub fn run(self: *Driver, args_iterator: *std.process.ArgIterator) u8 {
    if (self.parseArgs(args_iterator)) return 1;

    switch (self.cli.command.?) {
        .run => return self.runRunCommand(),
    }

    return 0;
}

fn readAllFileSentinel(gpa: std.mem.Allocator, file_path: []const u8) ?[:0]u8 {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        std.debug.print("{s}: {s}\n", .{ file_path, errorDescription(err) });

        return null;
    };
    defer file.close();

    const file_content = file.reader().readAllAlloc(gpa, std.math.maxInt(u32)) catch |err| {
        std.debug.print("{s}: {s}\n", .{ file_path, errorDescription(err) });

        return null;
    };

    const file_content_z = @as([:0]u8, @ptrCast(file_content));

    if (file_content.len != 0) {
        file_content_z[file_content.len] = 0;
    }

    return file_content_z;
}

fn runRunCommand(self: *Driver) u8 {
    const options = self.cli.command.?.run;

    const file_content = readAllFileSentinel(self.gpa, options.file_path) orelse return 1;

    if (file_content.len == 0) {
        return 0;
    }

    var parser = Parser.init(self.gpa, file_content) catch |err| {
        std.debug.print("{s}\n", .{errorDescription(err)});

        return 1;
    };

    const root = parser.parseRoot() catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ options.file_path, parser.error_info.?.source_loc.line, parser.error_info.?.source_loc.column, parser.error_info.?.message });

            return 1;
        },
    };

    var gen = CodeGen.init(self.gpa, .script);

    gen.compileRoot(root) catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ options.file_path, gen.error_info.?.source_loc.line, gen.error_info.?.source_loc.column, gen.error_info.?.message });

            return 1;
        },
    };

    var vm = VirtualMachine.init(self.gpa) catch |err| {
        std.debug.print("{s}\n", .{errorDescription(err)});

        return 1;
    };

    vm.addGlobals() catch |err| {
        std.debug.print("{s}\n", .{errorDescription(err)});

        return 1;
    };

    vm.setCode(gen.code) catch |err| {
        std.debug.print("{s}\n", .{errorDescription(err)});

        return 1;
    };

    _ = vm.run() catch |err| switch (err) {
        error.DivisionByZero => {
            const last_frame = vm.frames.getLast();

            const source_loc = last_frame.function.code.source_locations.items[last_frame.ip - 1];

            std.debug.print("{s}:{}:{}: division by zero\n", .{ options.file_path, source_loc.line, source_loc.column });

            return 1;
        },

        error.NegativeDenominator => {
            const last_frame = vm.frames.getLast();

            const source_loc = last_frame.function.code.source_locations.items[last_frame.ip - 1];

            std.debug.print("{s}:{}:{}: negative denominator\n", .{ options.file_path, source_loc.line, source_loc.column });

            return 1;
        },

        error.StackOverflow => {
            const last_frame = vm.frames.getLast();

            const source_loc = last_frame.function.code.source_locations.items[last_frame.ip - 1];

            std.debug.print("{s}:{}:{}: stack overflow\n", .{ options.file_path, source_loc.line, source_loc.column });

            return 1;
        },

        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ options.file_path, vm.error_info.?.source_loc.line, vm.error_info.?.source_loc.column, vm.error_info.?.message });

            return 1;
        },
    };

    return 0;
}
