use syphon_location::Location;

use derive_more::{Display, Error};

#[derive(Error, Display, Debug, Clone)]
pub enum SyphonError {
    #[display(fmt = "{location}: {content}")]
    Message { location: Location, content: String },

    #[display(fmt = " maximum call stack size exceeded")]
    StackOverflow,
}

impl SyphonError {
    pub fn new_message(location: Location, content: String) -> SyphonError {
        SyphonError::Message { location, content }
    }

    pub fn invalid(location: Location, stmt: &str) -> SyphonError {
        SyphonError::new_message(location, format!("invalid {}", stmt))
    }

    pub fn unsupported(location: Location, stmt: &str) -> SyphonError {
        SyphonError::new_message(location, format!("unsupported {}", stmt))
    }

    pub fn undefined(location: Location, stmt: &str, identifier: &str) -> SyphonError {
        SyphonError::new_message(location, format!("undefined {} '{}'", stmt, identifier))
    }

    pub fn unexpected(location: Location, stmt: &str, got: &str) -> SyphonError {
        SyphonError::new_message(location, format!("unexpected {} '{}'", stmt, got))
    }

    pub fn expected(location: Location, expected: &str) -> SyphonError {
        SyphonError::new_message(location, format!("expected {}", expected))
    }

    pub fn expected_got(location: Location, expected: &str, got: &str) -> SyphonError {
        SyphonError::new_message(location, format!("expected {} got {}", expected, got))
    }

    pub fn unable_to(location: Location, stmt: &str) -> SyphonError {
        SyphonError::new_message(location, format!("unable to {}", stmt))
    }

    pub fn mismatched(location: Location, stmt: &str) -> SyphonError {
        SyphonError::new_message(location, format!("mismatched {}", stmt))
    }
}
