const std = @import("std");
const build_options = @import("build_options");

const Parser = @import("compiler/ast.zig").Parser;
const CodeGen = @import("compiler/CodeGen.zig");
const VirtualMachine = @import("vm/VirtualMachine.zig");
const Atom = @import("vm/Atom.zig");

const Driver = @This();

allocator: std.mem.Allocator,

cli: CLI,

const CLI = struct {
    program: []const u8 = "",
    command: ?Command = null,

    const Command = union(enum) {
        run: Run,
        version: void,
        help: void,

        const Run = struct {
            argv: []const []const u8,
        };
    };
};

const usage =
    \\Usage: 
    \\  {s} <command> [arguments]
    \\
    \\Commands:
    \\  run <file_path>     -- run certain file
    \\  version             -- print version
    \\  help                -- print this help message
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
        else => @errorName(e),
    };
}

pub fn init(allocator: std.mem.Allocator) Driver {
    return Driver{
        .allocator = allocator,
        .cli = .{},
    };
}

fn parseArgs(self: *Driver, arg_iterator: *std.process.ArgIterator) bool {
    const program = arg_iterator.next().?;

    self.cli.program = program;

    while (arg_iterator.next()) |arg| {
        if (std.mem.eql(u8, arg, "run")) {
            var argv = std.ArrayList([]const u8).init(self.allocator);

            while (arg_iterator.next()) |remaining_arg| {
                argv.append(remaining_arg) catch |err| {
                    std.debug.print("{s}\n", .{errorDescription(err)});

                    return true;
                };
            }

            if (argv.items.len == 0) {
                std.debug.print(run_command_usage, .{program});

                std.debug.print("Error: expected a file_path\n", .{});

                return true;
            }

            const owned_argv = argv.toOwnedSlice() catch |err| {
                std.debug.print("{s}\n", .{errorDescription(err)});

                return true;
            };

            self.cli.command = .{ .run = .{ .argv = owned_argv } };
        } else if (std.mem.eql(u8, arg, "version")) {
            self.cli.command = .{ .version = {} };
        } else if (std.mem.eql(u8, arg, "help")) {
            self.cli.command = .{ .help = {} };
        } else {
            std.debug.print(usage, .{program});

            std.debug.print("Error: {s} is an unknown command\n", .{arg});

            return true;
        }
    }

    if (self.cli.command == null) {
        std.debug.print(usage, .{program});

        std.debug.print("Error: no command provided\n", .{});

        return true;
    }

    return false;
}

pub fn run(self: *Driver, arg_iterator: *std.process.ArgIterator) u8 {
    if (self.parseArgs(arg_iterator)) return 1;

    switch (self.cli.command.?) {
        .run => return self.executeRunCommand(),
        .version => return executeVersionCommand(),
        .help => return self.executeHelpCommand(),
    }

    return 0;
}

fn readAllZ(allocator: std.mem.Allocator, file_path: []const u8) ?[:0]u8 {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        std.debug.print("{s}: {s}\n", .{ file_path, errorDescription(err) });

        return null;
    };

    defer file.close();

    const file_content = file.reader().readAllAlloc(allocator, std.math.maxInt(u32)) catch |err| {
        std.debug.print("{s}: {s}\n", .{ file_path, errorDescription(err) });

        return null;
    };

    const file_content_z = @as([:0]u8, @ptrCast(file_content));

    if (file_content.len != 0) {
        file_content_z[file_content.len] = 0;
    }

    return file_content_z;
}

fn executeRunCommand(self: *Driver) u8 {
    const options = self.cli.command.?.run;

    const file_path = options.argv[0];

    const file_content = readAllZ(self.allocator, file_path) orelse return 1;

    if (file_content.len == 0) {
        return 0;
    }

    var parser = Parser.init(self.allocator, file_content) catch |err| {
        std.debug.print("{s}\n", .{errorDescription(err)});

        return 1;
    };

    const root = parser.parseRoot() catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("{s}\n", .{errorDescription(err)});

            return 1;
        },

        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ file_path, parser.error_info.?.source_loc.line, parser.error_info.?.source_loc.column, parser.error_info.?.message });

            return 1;
        },
    };

    Atom.init(self.allocator);

    var gen = CodeGen.init(self.allocator, .script, null) catch |err| {
        std.debug.print("{s}\n", .{errorDescription(err)});

        return 1;
    };

    gen.compileRoot(root) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("{s}\n", .{errorDescription(err)});

            return 1;
        },

        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ file_path, gen.error_info.?.source_loc.line, gen.error_info.?.source_loc.column, gen.error_info.?.message });

            return 1;
        },
    };

    var vm = VirtualMachine.init(self.allocator, options.argv) catch |err| {
        std.debug.print("{s}\n", .{errorDescription(err)});

        return 1;
    };

    vm.setCode(gen.code) catch |err| {
        std.debug.print("{s}\n", .{errorDescription(err)});

        return 1;
    };

    vm.run() catch |err| switch (err) {
        error.DivisionByZero => {
            const last_frame = vm.frames.getLast();

            const source_loc = last_frame.function.code.source_locations.items[last_frame.ip - 1];

            std.debug.print("{s}:{}:{}: division by zero\n", .{ file_path, source_loc.line, source_loc.column });

            return 1;
        },

        error.NegativeDenominator => {
            const last_frame = vm.frames.getLast();

            const source_loc = last_frame.function.code.source_locations.items[last_frame.ip - 1];

            std.debug.print("{s}:{}:{}: negative denominator\n", .{ file_path, source_loc.line, source_loc.column });

            return 1;
        },

        error.StackOverflow => {
            const last_frame = vm.frames.getLast();

            const source_loc = last_frame.function.code.source_locations.items[last_frame.ip];

            std.debug.print("{s}:{}:{}: stack overflow\n", .{ file_path, source_loc.line, source_loc.column });

            return 1;
        },

        error.OutOfMemory => {
            std.debug.print("{s}\n", .{errorDescription(err)});

            return 1;
        },

        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ file_path, vm.error_info.?.source_loc.line, vm.error_info.?.source_loc.column, vm.error_info.?.message });

            return 1;
        },
    };

    return 0;
}

fn executeVersionCommand() u8 {
    const stdout = std.io.getStdOut();

    stdout.writer().print("Syphon {s}\n", .{build_options.version}) catch return 1;

    return 0;
}

fn executeHelpCommand(self: Driver) u8 {
    std.debug.print(usage, .{self.cli.program});

    return 0;
}
