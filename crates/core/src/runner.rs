use syphon_bytecode::chunk::Chunk;
use syphon_bytecode::compiler::{Compiler, CompilerMode};
use syphon_bytecode::disassembler::disassmeble;
use syphon_bytecode::value::Value;
use syphon_lexer::Lexer;
use syphon_parser::Parser;
use syphon_vm::VirtualMachine;

use std::fs::File;
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::path::PathBuf;
use std::process::exit;

pub fn load_syc(input: &str, vm: &mut VirtualMachine) -> bool {
    let mut bytes = input.bytes();

    if bytes.next().is_some_and(|b| b != 0x10) || bytes.next().is_some_and(|b| b != 0x07) {
        eprintln!("invalid syc file: invalid file magic number");

        return false;
    }

    let Some(chunk) = Chunk::parse(&mut bytes) else {
        return false;
    };

    vm.load_chunk(chunk);

    true
}

pub fn load_regular(file_path: &str, input: &str, vm: &mut VirtualMachine) -> bool {
    let lexer = Lexer::new(input);

    let mut parser = Parser::new(lexer);

    let module = match parser.parse() {
        Ok(module) => module,
        Err(err) => {
            eprintln!("{} {}", file_path, err);

            return false;
        }
    };

    let mut compiler = Compiler::new(CompilerMode::Script);

    match compiler.compile(module) {
        Ok(()) => (),
        Err(err) => {
            eprintln!("{} {}", file_path, err);

            return false;
        }
    };

    let chunk = compiler.get_chunk();

    vm.load_chunk(chunk);

    true
}

pub fn run(file_path: &str, input: String, vm: &mut VirtualMachine) -> Option<Value> {
    if !load_syc(&input, vm) {
        if !load_regular(file_path, &input, vm) {
            return None;
        }
    }

    match vm.run() {
        Ok(value) => Some(value),

        Err(err) => {
            eprintln!("{} {}", file_path, err);

            None
        }
    }
}

pub fn run_file(file_path: &PathBuf) -> io::Result<()> {
    let file = File::open(file_path)?;

    let reader = BufReader::new(file);

    let mut file_content = String::new();

    for line in reader.lines() {
        file_content.push_str(line?.as_str());
        file_content.push('\n');
    }

    let mut vm = VirtualMachine::new();

    match run(
        file_path.to_string_lossy().to_string().as_str(),
        file_content,
        &mut vm,
    ) {
        Some(_) => Ok(()),
        None => exit(1),
    }
}

pub fn compile_file(input_file_path: &PathBuf) -> io::Result<()> {
    let input_file = File::open(input_file_path)?;

    let reader = BufReader::new(input_file);

    let mut file_content = String::new();

    for line in reader.lines() {
        file_content.push_str(line?.as_str());
        file_content.push('\n');
    }

    let lexer = Lexer::new(&file_content);

    let mut parser = Parser::new(lexer);

    let module = match parser.parse() {
        Ok(module) => module,
        Err(err) => {
            eprintln!("{} {}", input_file_path.display(), err);

            exit(1);
        }
    };

    let mut compiler = Compiler::new(CompilerMode::Script);

    match compiler.compile(module) {
        Ok(()) => (),
        Err(err) => {
            eprintln!("{} {}", input_file_path.display(), err);

            exit(1);
        }
    };

    let chunk = compiler.get_chunk();

    let mut output_file_path = input_file_path.clone();
    output_file_path.set_extension("syc");

    let output_file = File::create(output_file_path)?;

    let mut writer = BufWriter::new(output_file);

    writer.write_all(&[0x10, 0x07]).unwrap();
    writer.write_all(&chunk.to_bytes()).unwrap();

    writer.flush().unwrap();

    Ok(())
}

pub fn disassemble_file(file_path: &PathBuf) -> io::Result<()> {
    let file = File::open(file_path)?;

    let reader = BufReader::new(file);

    let mut file_content = String::new();

    for line in reader.lines() {
        file_content.push_str(line?.as_str());
        file_content.push('\n');
    }

    let mut file_bytes = file_content.bytes();

    if file_bytes.next().is_some_and(|b| b != 0x10) || file_bytes.next().is_some_and(|b| b != 0x07) {
        eprintln!("invalid syc file: invalid file magic number");

        exit(1);
    }

    let Some(chunk) = Chunk::parse(&mut file_bytes) else {
        exit(1);
    };

    let disassembled_chunk = disassmeble(file_path.to_string_lossy().to_string().as_str(), &chunk);

    println!("{}", disassembled_chunk);

    Ok(())
}
