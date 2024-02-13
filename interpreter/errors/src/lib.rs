use syphon_location::Location;

use derive_more::{Display, Error};

#[derive(Error, Display, Debug, Clone)]
#[display(fmt = "at {location}: {message}")]
pub struct SyphonError {
    location: Location,
    message: String,
}

impl SyphonError {
    pub fn new(location: Location, message: String) -> SyphonError {
        SyphonError { location, message }
    }

    pub fn invalid(location: Location, stmt: &str) -> SyphonError {
        SyphonError::new(location, format!("invalid {}", stmt))
    }

    pub fn unsupported(location: Location, stmt: &str) -> SyphonError {
        SyphonError::new(location, format!("unsupported {}", stmt))
    }

    pub fn undefined(location: Location, stmt: &str, identifier: &str) -> SyphonError {
        SyphonError::new(location, format!("undefined {} '{}'", stmt, identifier))
    }

    pub fn unexpected(location: Location, stmt: &str, got: &str) -> SyphonError {
        SyphonError::new(location, format!("unexpected {} '{}'", stmt, got))
    }

    pub fn expected(location: Location, expected: &str) -> SyphonError {
        SyphonError::new(location, format!("expected {}", expected))
    }

    pub fn expected_got(location: Location, expected: &str, got: &str) -> SyphonError {
        SyphonError::new(location, format!("expected {} got {}", expected, got))
    }

    pub fn unable_to(location: Location, stmt: &str) -> SyphonError {
        SyphonError::new(location, format!("unable to {}", stmt))
    }

    pub fn mismatched(location: Location, stmt: &str) -> SyphonError {
        SyphonError::new(location, format!("mismatched {}", stmt))
    }
}
