use syphon_bytecode::chunk::Chunk;
use syphon_bytecode::compiler::*;
use syphon_bytecode::values::*;
use syphon_errors::ErrorHandler;
use syphon_lexer::Lexer;
use syphon_parser::Parser;
use syphon_vm::VirtualMachine;

use rustc_hash::FxHashMap;

pub fn run(
    file_path: String,
    input: String,
    globals: &mut FxHashMap<String, ValueInfo>,
) -> Result<(Value, Chunk), ()> {
    let lexer = Lexer::new(&input);

    let mut parser = Parser::new(lexer);
    let module = parser.module();

    if !parser.lexer.errors.is_empty() {
        ErrorHandler::handle_errors(file_path, parser.lexer.errors);

        return Err(());
    }

    if !parser.errors.is_empty() {
        ErrorHandler::handle_errors(file_path, parser.errors);

        return Err(());
    }

    let mut compiler = Compiler::new(CompilerMode::Script);

    compiler.compile(module);

    if !compiler.errors.is_empty() {
        ErrorHandler::handle_errors(file_path, compiler.errors);

        return Err(());
    }

    let chunk = compiler.to_chunk();

    let mut vm = VirtualMachine::new(chunk.clone(), globals);

    match vm.run() {
        Ok(value) => Ok((value, chunk)),
        Err(err) => {
            ErrorHandler::handle_error(file_path, err);

            Err(())
        }
    }
}
