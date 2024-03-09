use crate::chunk::Chunk;
use crate::instruction::Instruction;
use crate::value::Value;

pub fn disassmeble(chunk_name: &str, chunk: &Chunk) -> String {
    let mut disassmebled = String::new();

    disassmebled.push_str(format!("\nDisassembly of '{}'\n", chunk_name).as_str());

    for instruction in chunk.code.iter() {
        disassmebled.push('\t');
        disassmebled.push_str(disassmeble_instruction(chunk, instruction).as_str());
        disassmebled.push('\n');
    }

    for constant in chunk.constants.iter() {
        match constant {
            Value::Function(function) => {
                disassmebled.push_str(disassmeble(&function.name, &function.body).as_str());
            }

            _ => (),
        }
    }

    disassmebled
}

fn disassmeble_instruction(chunk: &Chunk, instruction: &Instruction) -> String {
    match instruction {
        Instruction::Neg { .. } => "Neg".to_string(),
        Instruction::LogicalNot { .. } => "LogicalNot".to_string(),

        Instruction::Add { .. } => "Add".to_string(),
        Instruction::Sub { .. } => "Sub".to_string(),
        Instruction::Div { .. } => "Div".to_string(),
        Instruction::Mult { .. } => "Mult".to_string(),
        Instruction::Exponent { .. } => "Exponent".to_string(),
        Instruction::Modulo { .. } => "Modulo".to_string(),

        Instruction::Equals { .. } => "Equals".to_string(),
        Instruction::NotEquals { .. } => "NotEquals".to_string(),
        Instruction::LessThan { .. } => "LessThan".to_string(),
        Instruction::GreaterThan { .. } => "GreaterThan".to_string(),

        Instruction::StoreName { name, .. } => {
            format!("StoreName ({})", name)
        }

        Instruction::Assign { name, .. } => {
            format!("Assign ({})", name)
        }

        Instruction::LoadName { name, .. } => {
            format!("LoadName ({})", name)
        }

        Instruction::LoadConstant { index } => {
            format!(
                "LoadConstant {} ({})",
                index,
                chunk.get_constant(*index).unwrap_or(&Value::None)
            )
        }

        Instruction::Call {
            arguments_count, ..
        } => {
            format!("Call ({})", arguments_count)
        }

        Instruction::Return => "Return".to_string(),

        Instruction::JumpIfFalse { offset, .. } => {
            format!("JumpIfFalse ({})", offset)
        }

        Instruction::Jump { offset } => {
            format!("Jump ({})", offset)
        }

        Instruction::Back { offset } => {
            format!("Back ({})", offset)
        }
    }
}
