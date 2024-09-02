const std = @import("std");
const build_options = @import("build_options");

const Parser = @import("compiler/ast.zig").Parser;
const CodeGen = @import("compiler/CodeGen.zig");
const VirtualMachine = @import("vm/VirtualMachine.zig");
const Atom = @import("vm/Atom.zig");

const Cli = @This();

allocator: std.mem.Allocator,

program: []const u8 = "",
command: ?Command = null,

const Command = union(enum) {
    run: Run,
    version,
    help,

    const Run = struct {
        argv: []const []const u8,
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

pub fn parse(allocator: std.mem.Allocator, argument_iterator: *std.process.ArgIterator) ?Cli {
    var self: Cli = .{
        .allocator = allocator,
        .program = argument_iterator.next().?,
    };

    while (argument_iterator.next()) |argument| {
        if (std.mem.eql(u8, argument, "run")) {
            var argv = std.ArrayList([]const u8).init(self.allocator);

            while (argument_iterator.next()) |remaining_argument| {
                argv.append(remaining_argument) catch |err| {
                    std.debug.print("{s}\n", .{errorDescription(err)});

                    return null;
                };
            }

            if (argv.items.len == 0) {
                std.debug.print(run_command_usage, .{self.program});

                std.debug.print("Error: expected a file_path\n", .{});

                return null;
            }

            self.command = .{ .run = .{ .argv = argv.items } };
        } else if (std.mem.eql(u8, argument, "version")) {
            self.command = .version;
        } else if (std.mem.eql(u8, argument, "help")) {
            self.command = .help;
        } else {
            std.debug.print(usage, .{self.program});

            std.debug.print("Error: {s} is an unknown command\n", .{argument});

            return null;
        }
    }

    if (self.command == null) {
        std.debug.print(usage, .{self.program});

        std.debug.print("Error: no command provided\n", .{});

        return null;
    }

    return self;
}

pub fn run(self: Cli) u8 {
    switch (self.command.?) {
        .run => return self.executeRunCommand(),
        .version => return executeVersionCommand(),
        .help => return self.executeHelpCommand(),
    }

    return 0;
}

fn executeRunCommand(self: Cli) u8 {
    const options = self.command.?.run;

    const file_path = options.argv[0];

    const file_content = blk: {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            std.debug.print("{s}: {s}\n", .{ file_path, errorDescription(err) });

            return 1;
        };

        defer file.close();

        break :blk file.readToEndAllocOptions(self.allocator, std.math.maxInt(u32), null, @alignOf(u8), 0) catch |err| switch (err) {
            error.OutOfMemory => {
                std.debug.print("{s}\n", .{errorDescription(err)});

                return 1;
            },

            else => {
                std.debug.print("{s}: {s}\n", .{ file_path, errorDescription(err) });

                return 1;
            },
        };
    };

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

    var gen = CodeGen.init(self.allocator, .script) catch |err| {
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

            const source_loc = last_frame.closure.function.code.source_locations.items[last_frame.counter - 1];

            std.debug.print("{s}:{}:{}: division by zero\n", .{ vm.argv[0], source_loc.line, source_loc.column });

            return 1;
        },

        error.NegativeDenominator => {
            const last_frame = vm.frames.getLast();

            const source_loc = last_frame.closure.function.code.source_locations.items[last_frame.counter - 1];

            std.debug.print("{s}:{}:{}: negative denominator\n", .{ vm.argv[0], source_loc.line, source_loc.column });

            return 1;
        },

        error.StackOverflow => {
            const last_frame = vm.frames.getLast();

            const source_loc = last_frame.closure.function.code.source_locations.items[last_frame.counter];

            std.debug.print("{s}:{}:{}: stack overflow\n", .{ vm.argv[0], source_loc.line, source_loc.column });

            return 1;
        },

        error.OutOfMemory => {
            std.debug.print("{s}\n", .{errorDescription(err)});

            return 1;
        },

        else => {
            std.debug.print("{s}:{}:{}: {s}\n", .{ vm.argv[0], vm.error_info.?.source_loc.line, vm.error_info.?.source_loc.column, vm.error_info.?.message });

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

fn executeHelpCommand(self: Cli) u8 {
    std.debug.print(usage, .{self.program});

    return 0;
}
