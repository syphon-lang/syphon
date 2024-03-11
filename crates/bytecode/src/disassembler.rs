use crate::chunk::Chunk;
use crate::instruction::Instruction;
use crate::value::Value;

pub fn disassmeble(chunk_name: &str, chunk: &Chunk) -> String {
    let mut disassembled = String::new();

    disassembled.push_str(format!("\nDisassembly of '{}'\n", chunk_name).as_str());

    for instruction in chunk.code.iter() {
        disassembled.push('\t');
        disassembled.push_str(disassmeble_instruction(chunk, instruction).as_str());
        disassembled.push('\n');
    }

    for constant in chunk.constants.iter() {
        if let Value::Function(function) = constant {
            disassembled.push_str(disassmeble(&function.name, &function.body).as_str());
        }
    }

    disassembled
}

fn disassmeble_instruction(chunk: &Chunk, instruction: &Instruction) -> String {
    match instruction {
        Instruction::Neg { .. } => "Neg".to_string(),
        Instruction::LogicalNot => "LogicalNot".to_string(),

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

        Instruction::StoreName { atom, .. } => {
            format!("StoreName {} ({})", atom, atom.get_name())
        }

        Instruction::Assign { atom, .. } => {
            format!("Assign {} ({})", atom, atom.get_name())
        }

        Instruction::LoadName { atom, .. } => {
            format!("LoadName {} ({})", atom, atom.get_name())
        }

        Instruction::LoadConstant { index } => {
            format!("LoadConstant {} ({})", index, chunk.get_constant(*index))
        }

        Instruction::Call {
            arguments_count, ..
        } => {
            format!("Call ({})", arguments_count)
        }

        Instruction::Return => "Return".to_string(),

        Instruction::JumpIfFalse { offset } => {
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
