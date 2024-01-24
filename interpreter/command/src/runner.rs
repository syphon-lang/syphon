use syphon_bytecode::chunk::Chunk;
use syphon_bytecode::compiler::*;
use syphon_bytecode::values::*;
use syphon_lexer::Lexer;
use syphon_parser::Parser;
use syphon_vm::VirtualMachine;

use rustc_hash::FxHashMap;

pub fn run(
    file_path: &str,
    input: String,
    globals: &mut FxHashMap<String, ValueInfo>,
) -> Result<(Value, Chunk), ()> {
    let lexer = Lexer::new(&input);

    let mut parser = Parser::new(lexer);

    let module = match parser.parse() {
        Ok(module) => module,
        Err(err) => {
            eprintln!("{} {}", file_path, err);

            return Err(());
        }
    };

    let mut compiler = Compiler::new(CompilerMode::Script);

    match compiler.compile(module) {
        Ok(()) => (),
        Err(err) => {
            eprintln!("{} {}", file_path, err);

            return Err(());
        }
    };

    let chunk = compiler.to_chunk();

    let mut vm = VirtualMachine::new(chunk.clone(), globals);

    match vm.run() {
        Ok(value) => Ok((value, chunk)),
        Err(err) => {
            eprintln!("{} {}", file_path, err);

            Err(())
        }
    }
}
