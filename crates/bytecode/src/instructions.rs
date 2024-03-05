use syphon_location::Location;

#[derive(Clone, PartialEq)]
#[repr(u8)]
pub enum Instruction {
    Neg {
        location: Location,
    },
    LogicalNot {
        location: Location,
    },

    Add {
        location: Location,
    },
    Sub {
        location: Location,
    },
    Div {
        location: Location,
    },
    Mult {
        location: Location,
    },
    Exponent {
        location: Location,
    },
    Modulo {
        location: Location,
    },

    Equals {
        location: Location,
    },
    NotEquals {
        location: Location,
    },
    LessThan {
        location: Location,
    },
    GreaterThan {
        location: Location,
    },

    StoreName {
        name: String,
        mutable: bool,
    },

    Assign {
        name: String,
        location: Location,
    },

    LoadName {
        name: String,
        location: Location,
    },

    Call {
        function_name: String,
        arguments_count: usize,
        location: Location,
    },

    LoadConstant {
        index: usize,
    },

    Return,
}
