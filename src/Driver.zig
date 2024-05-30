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
    \\  run <file_path>     --  run certain file
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

fn parseArgs(self: *Driver, argiterator: *std.process.ArgIterator) bool {
    const program = argiterator.next().?;

    var arg = argiterator.next();

    while (arg != null) : (arg = argiterator.next()) {
        if (std.mem.eql(u8, arg.?, "run")) {
            const file_path = argiterator.next();

            if (file_path == null) {
                std.debug.print(run_command_usage, .{program});

                std.debug.print("Error: expected a file path\n", .{});

                return true;
            }

            self.cli.command = .{ .run = .{ .file_path = file_path.? } };

            return false;
        } else {
            std.debug.print(usage, .{program});

            std.debug.print("Error: {s} is an unknown command\n", .{arg.?});

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

pub fn run(self: *Driver, argiterator: *std.process.ArgIterator) u8 {
    if (self.parseArgs(argiterator)) return 1;

    switch (self.cli.command.?) {
        .run => return self.runRunCommand(),
    }

    return 0;
}

fn readAllFileSentinel(gpa: std.mem.Allocator, file_path: []const u8) ?[:0]const u8 {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        std.debug.print("{s}: {s}\n", .{ file_path, errorDescription(err) });

        return null;
    };
    defer file.close();

    const file_content = file.reader().readAllAlloc(gpa, std.math.maxInt(u32)) catch |err| {
        std.debug.print("{s}: {s}\n", .{ file_path, errorDescription(err) });

        return null;
    };

    var file_content_z = @as([:0]u8, @ptrCast(file_content));
    file_content_z[file_content_z.len] = 0;

    return file_content_z;
}

fn runRunCommand(self: *Driver) u8 {
    const options = self.cli.command.?.run;

    const file_content = readAllFileSentinel(self.gpa, options.file_path) orelse return 1;
    defer self.gpa.free(file_content);

    var parser = Parser.init(self.gpa, file_content) catch |err| {
        std.debug.print("{s}", .{errorDescription(err)});

        return 1;
    };

    const root = parser.parseRoot() catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}", .{ options.file_path, parser.error_info.?.source_loc.line, parser.error_info.?.source_loc.column, parser.error_info.?.message });

            return 1;
        },
    };

    var gen = CodeGen.init(self.gpa, .script);

    gen.compileRoot(root) catch |err| switch (err) {
        else => {
            std.debug.print("{s}:{}:{}: {s}", .{ options.file_path, gen.error_info.?.source_loc.line, gen.error_info.?.source_loc.column, gen.error_info.?.message });

            return 1;
        },
    };

    var vm = VirtualMachine.init(self.gpa) catch |err| {
        std.debug.print("{s}", .{errorDescription(err)});

        return 1;
    };

    vm.addGlobals() catch |err| {
        std.debug.print("{s}", .{errorDescription(err)});

        return 1;
    };

    vm.setCode(gen.code) catch |err| {
        std.debug.print("{s}", .{errorDescription(err)});

        return 1;
    };

    _ = vm.run() catch |err| switch (err) {
        // TODO: Handle these cases properly
        error.DivisionByZero, error.NegativeDenominator => {
            return 1;
        },

        else => {
            std.debug.print("{s}:{}:{}: {s}", .{ options.file_path, vm.error_info.?.source_loc.line, vm.error_info.?.source_loc.column, vm.error_info.?.message });

            return 1;
        },
    };

    return 0;
}