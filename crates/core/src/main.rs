use syphon_core::cli::{Command, CLI};

use clap::Parser;

use std::io;

use std::process::exit;

fn main() -> io::Result<()> {
    let cli = CLI::parse();

    match &cli.command {
        Command::Run { file_path } => {
            syphon_core::runner::run_file(file_path.to_string_lossy().to_string().as_str(), &cli)
                .unwrap_or_else(|err| {
                    eprintln!("{}: {}", file_path.display(), err);
                    exit(1)
                });

            Ok(())
        }

        Command::Repl => syphon_core::repl::start(&cli),
    }
}
