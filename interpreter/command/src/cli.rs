use clap::Parser;

use std::path::PathBuf;

#[derive(Parser)]
pub struct Arguments {
    #[arg(help = "Read the program from a file")]
    pub file_path: Option<PathBuf>,

    #[arg(
        short = 'b',
        long = "emit-bytecode",
        help = "Print the bytecode generated during assembling the program"
    )]
    pub emit_bytecode: bool,
}
