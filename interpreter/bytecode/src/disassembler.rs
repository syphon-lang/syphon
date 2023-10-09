use crate::chunk::*;
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
    let disassmebled_instruction: String;

    match instruction {
        Instruction::LoadConstant(index) => {
            disassmebled_instruction = format!(
                "LoadConstant {} ({})",
                index,
                chunk.get_constant(*index).unwrap_or(&Value::None)
            )
        }

        Instruction::Return => disassmebled_instruction = format!("Return"),
    }

    disassmebled_instruction
}
