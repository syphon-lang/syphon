use crate::cli::Arguments;

use crate::runner;

use syphon_bytecode::disassembler::disassmeble;

use rustc_hash::FxHashMap;

use io::{BufRead, BufReader};
use std::io;

use std::path::PathBuf;

use std::fs::File;

use std::process::exit;

pub fn run_file(file_path: PathBuf, args: Arguments) -> io::Result<()> {
    let file = File::open(file_path.clone())?;
    let reader = BufReader::new(file);

    let mut file_content = String::new();

    for line in reader.lines() {
        file_content.push_str(line?.as_str());
        file_content.push('\n');
    }

    let mut globals = FxHashMap::default();

    let Ok((_, chunk)) = runner::run(
        file_path.to_str().unwrap_or_default().to_string(),
        file_content,
        &mut globals,
    ) else {
        exit(1);
    };

    if args.emit_bytecode {
        println!("------------------------------------");
        println!(
            "{}",
            disassmeble(file_path.to_str().unwrap_or_default(), &chunk)
        );
        println!("------------------------------------");
        println!();
    }

    Ok(())
}
