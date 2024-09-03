const std = @import("std");

const Ast = @import("compiler/Ast.zig");
const Compiler = @import("compiler/Compiler.zig");
const VirtualMachine = @import("vm/VirtualMachine.zig");
const Code = @import("vm/Code.zig");
const Atom = @import("vm/Atom.zig");

const Interpreter = @This();

allocator: std.mem.Allocator,

argv: []const []const u8,
file_content: [:0]const u8,

error_info: ?ErrorInfo = null,

pub const Error = Ast.Parser.Error || Compiler.Error || VirtualMachine.Error || std.mem.Allocator.Error;

pub const ErrorInfo = struct {
    message: []const u8,
    source_loc: Ast.SourceLoc,
};

pub fn init(allocator: std.mem.Allocator, argv: []const []const u8, file_content: [:0]const u8) Interpreter {
    if (!Atom.initialized) Atom.init(allocator);

    return Interpreter{
        .allocator = allocator,
        .argv = argv,
        .file_content = file_content,
    };
}

pub const FinalState = struct {
    exported: Code.Value,
    globals: VirtualMachine.Globals,
};

pub fn run(self: *Interpreter) Error!FinalState {
    var ast_parser = try Ast.Parser.init(self.allocator, self.file_content);

    const ast = ast_parser.parse() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,

        else => {
            self.error_info = .{ .message = ast_parser.error_info.?.message, .source_loc = ast_parser.error_info.?.source_loc };

            return err;
        },
    };

    var compiler = try Compiler.init(self.allocator, .script);

    compiler.compile(ast) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,

        else => {
            self.error_info = .{ .message = compiler.error_info.?.message, .source_loc = compiler.error_info.?.source_loc };

            return err;
        },
    };

    var vm = try VirtualMachine.init(self.allocator, self.argv);

    try vm.setCode(compiler.code);

    vm.run() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,

        error.DivisionByZero => {
            const frame = vm.frames.getLast();

            self.error_info = .{ .message = "division by zero", .source_loc = frame.closure.function.code.source_locations.items[frame.counter - 1] };

            return error.DivisionByZero;
        },

        error.NegativeDenominator => {
            const frame = vm.frames.getLast();

            self.error_info = .{ .message = "negative denominator", .source_loc = frame.closure.function.code.source_locations.items[frame.counter - 1] };

            return error.NegativeDenominator;
        },

        error.StackOverflow => {
            const frame = vm.frames.getLast();

            self.error_info = .{ .message = "stack overflow", .source_loc = frame.closure.function.code.source_locations.items[frame.counter] };

            return error.StackOverflow;
        },

        else => {
            self.error_info = .{ .message = vm.error_info.?.message, .source_loc = vm.error_info.?.source_loc };

            return err;
        },
    };

    return FinalState{
        .exported = vm.exported,
        .globals = vm.globals,
    };
}
