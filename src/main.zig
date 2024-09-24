const std = @import("std");
const build_options = @import("build_options");

const Interpreter = @import("interpreter/Interpreter.zig");

const gc = @import("gc.zig");

const Cli = struct {
    allocator: std.mem.Allocator,

    program: []const u8 = "",
    command: ?Command = null,

    const Command = union(enum) {
        run: Run,
        version,
        help,

        const Run = struct {
            argv: []const []const u8,

            const usage =
                \\Usage:
                \\  {s} run <file_path>
                \\
                \\
            ;
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

    fn errorDescription(e: anyerror) []const u8 {
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

    fn parse(allocator: std.mem.Allocator, argument_iterator: *std.process.ArgIterator) ?Cli {
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
                    std.debug.print(Command.Run.usage, .{self.program});

                    std.debug.print("Error: expected a file path\n", .{});

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

        var interpreter = Interpreter.init(self.allocator, options.argv, file_content);

        _ = interpreter.run() catch |err| switch (err) {
            error.OutOfMemory => {
                std.debug.print("{s}\n", .{errorDescription(err)});

                return 1;
            },

            else => {
                std.debug.print("{s}:{}:{}: {s}\n", .{ interpreter.error_info.?.source_loc.file_path, interpreter.error_info.?.source_loc.line, interpreter.error_info.?.source_loc.column, interpreter.error_info.?.message });
            },
        };

        return 0;
    }

    fn executeVersionCommand() u8 {
        const stdout = std.io.getStdOut();

        stdout.writer().print("{s}\n", .{build_options.version}) catch return 1;

        return 0;
    }

    fn executeHelpCommand(self: Cli) u8 {
        std.debug.print(usage, .{self.program});

        return 0;
    }
};

pub fn main() u8 {
    const allocator = gc.allocator();

    var argument_iterator = std.process.argsWithAllocator(allocator) catch |err| {
        std.debug.print("{s}\n", .{Cli.errorDescription(err)});

        return 1;
    };

    const cli = Cli.parse(allocator, &argument_iterator) orelse return 1;

    switch (cli.command.?) {
        .run => return cli.executeRunCommand(),
        .version => return Cli.executeVersionCommand(),
        .help => return cli.executeHelpCommand(),
    }

    return 0;
}
