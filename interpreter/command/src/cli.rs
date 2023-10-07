use clap::Parser;

use std::path::PathBuf;

#[derive(Parser)]
pub struct Arguments {
    pub file_name: Option<PathBuf>,
}
