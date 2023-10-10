use crate::chunk::*;
use crate::instructions::Instruction;
use crate::values::Value;

pub fn disassmeble(label: &str, chunk: &Chunk) -> String {
    let mut disassmebled = String::new();

    disassmebled.push_str(format!("\nDisassembly of label '{}'\n\n", label).as_str());

    for instruction in chunk.code.iter() {
        disassmebled.push_str(disassmeble_instruction(chunk, instruction).as_str());
        disassmebled.push('\n');
    }

    disassmebled
}

fn disassmeble_instruction(chunk: &Chunk, instruction: &Instruction) -> String {
    match instruction {
        Instruction::UnaryOperation { operator, .. } => {
            format!("UnaryOperation ({})", operator)
        }

        Instruction::BinaryOperation { operator, .. } => {
            format!("BinaryOperation ({})", operator)
        }

        Instruction::LoadConstant { index } => {
            format!(
                "LoadConstant {} ({})",
                index,
                chunk.get_constant(*index).unwrap_or(&Value::None)
            )
        }

        Instruction::Return => "Return".to_string(),
    }
}
