use clap::Parser;

use std::path::PathBuf;

#[derive(Parser)]
pub struct Arguments {
    #[arg(
        help = "The file path of the program to run, If not provided the interpreter will work as a REPL"
    )]
    pub file_path: Option<PathBuf>,

    #[arg(
        short = 'b',
        long = "emit-bytecode",
        help = "Print the bytecode when the source code is compiled (only for debugging purposes and works also for REPL mode)"
    )]
    pub emit_bytecode: bool,
}
