use clap::{Parser, Subcommand};

use std::path::PathBuf;

#[derive(Parser)]
pub struct CLI {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    #[command(about = "Compile a specific script to bytecode")]
    Compile { file_path: PathBuf },

    #[command(about = "Disassemble a specific bytecode file")]
    Disassemble { file_path: PathBuf },

    #[command(about = "Run a specific script or bytecode")]
    Run { file_path: PathBuf },

    #[command(about = "Run in interactive mode")]
    Repl,
}
