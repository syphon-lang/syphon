pub mod cli;
pub mod repl;
pub mod runner;

use cli::Arguments;

use syphon_bytecode::disassembler;

use rustc_hash::FxHashMap;

use io::{BufRead, BufReader};
use std::io;

use std::fs::File;

use std::process::exit;

pub fn run_file(file_path: &str, args: Arguments) -> io::Result<()> {
    let file = File::open(file_path)?;
    let reader = BufReader::new(file);

    let mut file_content = String::new();

    for line in reader.lines() {
        file_content.push_str(line?.as_str());
        file_content.push('\n');
    }

    let mut globals = FxHashMap::default();

    let Ok((_, chunk)) = runner::run(file_path, file_content, &mut globals) else {
        exit(1);
    };

    if args.emit_bytecode {
        println!("------------------------------------");
        println!("{}", disassembler::disassmeble(file_path, &chunk));
        println!("------------------------------------");
        println!();
    }

    Ok(())
}
