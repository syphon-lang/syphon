use syphon_bytecode::chunk::Chunk;
use syphon_bytecode::compiler::{Compiler, CompilerMode};
use syphon_bytecode::disassembler::disassemble;
use syphon_bytecode::value::Value;
use syphon_gc::GarbageCollector;
use syphon_parser::Parser;
use syphon_vm::VirtualMachine;

use std::fs::File;
use std::io::{self, BufRead, BufReader, BufWriter, Read, Write};
use std::path::PathBuf;
use std::process::exit;

fn parse_syc(input: Vec<u8>, gc: &mut GarbageCollector) -> Option<Chunk> {
    let mut bytes = input.into_iter();

    if bytes.next().is_some_and(|b| b != 0x10) || bytes.next().is_some_and(|b| b != 0x07) {
        return None;
    }

    Some(Chunk::parse(&mut bytes, gc))
}

fn load_syc(input: Vec<u8>, vm: &mut VirtualMachine) -> bool {
    let Some(chunk) = parse_syc(input, vm.gc) else {
        return false;
    };

    vm.load_chunk(chunk);

    true
}

pub fn load_script(
    file_path: &str,
    input: &str,
    mode: CompilerMode,
    vm: &mut VirtualMachine,
) -> bool {
    let mut parser = Parser::new(input);

    let module = match parser.parse() {
        Ok(module) => module,
        Err(err) => {
            eprintln!("{}:{}", file_path, err);

            return false;
        }
    };

    let mut compiler = Compiler::new(mode, vm.gc);

    match compiler.compile(module) {
        Ok(()) => (),
        Err(err) => {
            eprintln!("{}:{}", file_path, err);

            return false;
        }
    };

    let chunk = compiler.get_chunk();

    vm.load_chunk(chunk);

    true
}

pub fn run_file(file_path: &PathBuf) -> io::Result<()> {
    let file = File::open(file_path)?;

    let mut reader = BufReader::new(file);

    let mut file_content = Vec::new();

    reader.read_to_end(&mut file_content)?;

    if file_content.is_empty() {
        return Ok(());
    }

    let mut gc = GarbageCollector::new();

    let mut vm = VirtualMachine::new(&mut gc);

    if !load_syc(file_content.clone(), &mut vm) {
        let file_content = String::from_utf8(file_content).unwrap();

        if !load_script(
            file_path.to_string_lossy().to_string().as_str(),
            &file_content,
            CompilerMode::Script,
            &mut vm,
        ) {
            exit(1);
        }
    }

    vm.init_globals();

    if let Err(err) = vm.run() {
        eprintln!("{}:{}", file_path.display(), err);

        exit(1);
    }

    Ok(())
}

pub fn compile_file(input_file_path: &PathBuf) -> io::Result<()> {
    let input_file = File::open(input_file_path)?;

    let reader = BufReader::new(input_file);

    let mut input_file_content = String::new();

    for line in reader.lines() {
        input_file_content.push_str(line?.as_str());
        input_file_content.push('\n');
    }

    let mut parser = Parser::new(&input_file_content);

    let module = match parser.parse() {
        Ok(module) => module,
        Err(err) => {
            eprintln!("{}:{}", input_file_path.display(), err);

            exit(1);
        }
    };

    let mut gc = GarbageCollector::new();

    let mut compiler = Compiler::new(CompilerMode::Script, &mut gc);

    match compiler.compile(module) {
        Ok(()) => (),
        Err(err) => {
            eprintln!("{}:{}", input_file_path.display(), err);

            exit(1);
        }
    };

    let chunk = compiler.get_chunk();

    let mut output_file_path = input_file_path.clone();
    output_file_path.set_extension("syc");

    let output_file = File::create(output_file_path)?;

    let mut writer = BufWriter::new(output_file);

    writer.write_all(&[0x10, 0x07]).unwrap();

    writer.write_all(&chunk.to_bytes(&gc)).unwrap();

    writer.flush().unwrap();

    Ok(())
}

pub fn run_repl(file_path: &str, input: String, vm: &mut VirtualMachine) -> Option<Value> {
    if !load_script(file_path, &input, CompilerMode::REPL, vm) {
        return None;
    }

    match vm.run() {
        Ok(value) => Some(value),

        Err(err) => {
            eprintln!("{}:{}", file_path, err);

            None
        }
    }
}

pub fn disassemble_file(file_path: &PathBuf) -> io::Result<()> {
    let file = File::open(file_path)?;

    let mut reader = BufReader::new(file);

    let mut file_content = Vec::new();

    reader.read_to_end(&mut file_content)?;

    let mut gc = GarbageCollector::new();

    let Some(chunk) = parse_syc(file_content, &mut gc) else {
        eprintln!("invalid syc file: invalid file magic number");

        exit(1);
    };

    let disassembled_chunk = disassemble(
        file_path.to_string_lossy().to_string().as_str(),
        &chunk,
        &gc,
    );

    println!("{}", disassembled_chunk);

    Ok(())
}
