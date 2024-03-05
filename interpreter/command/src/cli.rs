use clap::{Parser, Subcommand};

use std::path::PathBuf;

#[derive(Parser, Clone)]
pub struct CLI {
    #[command(subcommand)]
    pub command: Command,

    #[arg(
        short = 'b',
        long = "emit-bytecode",
        help = "Print the bytecode when compiled (only for debugging purposes and also works in interactive mode)"
    )]
    pub emit_bytecode: bool,
}

#[derive(Subcommand, Clone)]
pub enum Command {
    #[command(about = "Run a specific script")]
    Run { file_path: PathBuf },

    #[command(about = "Run in interactive mode")]
    Repl,
}
