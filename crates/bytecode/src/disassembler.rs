use crate::chunk::Chunk;
use crate::instruction::Instruction;
use crate::value::Value;

use syphon_gc::{GarbageCollector, TraceFormatter};

pub fn disassemble(chunk_name: &str, chunk: &Chunk, gc: &GarbageCollector) -> String {
    let mut disassembled = String::new();

    disassembled.push_str(format!("\nDisassembly of '{}'\n", chunk_name).as_str());

    chunk.code.iter().for_each(|instruction| {
        disassembled.push('\t');
        disassembled.push_str(disassemble_instruction(chunk, instruction, gc).as_str());
        disassembled.push('\n');
    });

    chunk.constants.iter().for_each(|constant| {
        if let Value::Function(reference) = constant {
            let function = gc.deref(*reference);

            disassembled
                .push_str(disassemble(&function.name.get_name(), &function.body, gc).as_str());
        }
    });

    disassembled
}

fn disassemble_instruction(
    chunk: &Chunk,
    instruction: &Instruction,
    gc: &GarbageCollector,
) -> String {
    match instruction {
        Instruction::Neg { .. } => "Neg".to_owned(),
        Instruction::LogicalNot => "LogicalNot".to_owned(),

        Instruction::Add { .. } => "Add".to_owned(),
        Instruction::Sub { .. } => "Sub".to_owned(),
        Instruction::Div { .. } => "Div".to_owned(),
        Instruction::Mult { .. } => "Mult".to_owned(),
        Instruction::Exponent { .. } => "Exponent".to_owned(),
        Instruction::Modulo { .. } => "Modulo".to_owned(),

        Instruction::Equals { .. } => "Equals".to_owned(),
        Instruction::NotEquals { .. } => "NotEquals".to_owned(),
        Instruction::LessThan { .. } => "LessThan".to_owned(),
        Instruction::GreaterThan { .. } => "GreaterThan".to_owned(),

        Instruction::StoreName { atom, .. } => format!("StoreName {} ({})", atom, atom.get_name()),

        Instruction::Assign { atom, .. } => format!("Assign {} ({})", atom, atom.get_name()),

        Instruction::LoadName { atom, .. } => format!("LoadName {} ({})", atom, atom.get_name()),

        Instruction::LoadConstant { index } => {
            let constant = *chunk.get_constant(*index);

            format!(
                "LoadConstant {} ({})",
                index,
                TraceFormatter::new(constant, gc)
            )
        }

        Instruction::Call {
            arguments_count, ..
        } => format!("Call ({})", arguments_count),

        Instruction::Return => "Return".to_owned(),

        Instruction::JumpIfFalse { offset } => format!("JumpIfFalse ({})", offset),

        Instruction::Jump { offset } => format!("Jump ({})", offset),

        Instruction::Back { offset } => format!("Back ({})", offset),

        Instruction::Pop => "Pop".to_owned(),

        Instruction::MakeArray { length } => format!("MakeArray ({})", length),

        Instruction::LoadSubscript { .. } => "LoadSubscript".to_owned(),

        Instruction::StoreSubscript { .. } => "StoreSubscript".to_owned(),
    }
}
