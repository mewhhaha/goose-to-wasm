// Write function-body-relative instruction offsets for byte-exact counter insertion.
use std::{env, fs, io::{self, Write}};
use wasmparser::{Operator::*, Parser, Payload};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = fs::read(env::args().nth(1).expect("named Wasm input"))?;
    let disassemble = env::args().nth(2).map(|v| v.parse::<usize>().unwrap());
    let mut out = io::BufWriter::new(io::stdout().lock());
    let mut function = 0;
    for payload in Parser::new(0).parse_all(&input) {
        let Payload::CodeSectionEntry(body) = payload? else { continue };
        let mut ops = body.get_operators_reader()?;
        let mut immediate = None;
        let mut previous_load = None;
        while !ops.eof() {
            let (op, absolute) = ops.read_with_offset()?;
            let offset = absolute - body.range().start;
            if let Some(which) = disassemble {
                if function == which { writeln!(out, "{offset:06x} {op:?}")?; }
            } else {
                let bulk = match op {
                    MemoryCopy {dst_mem: 0, src_mem: 0} => Some("copy"),
                    MemoryFill {mem: 0} => Some("fill"),
                    _ => None,
                };
                if let Some(kind) = bulk {
                    writeln!(out, "{function} {offset} {kind} {}", immediate.unwrap_or(-1))?;
                } else {
                    // Exact adjacent equal-width load and store, including truncating stores.
                    // This includes scalar assignments. Report apart from explicit memory.copy.
                    let store = match op {
                        I32Store8 {..} | I64Store8 {..} => Some(1),
                        I32Store16 {..} | I64Store16 {..} => Some(2),
                        I32Store {..} | F32Store {..} | I64Store32 {..} => Some(4),
                        I64Store {..} | F64Store {..} => Some(8),
                        V128Store {..} => Some(16),
                        _ => None,
                    };
                    if let Some(width) = store {
                        if previous_load == store { writeln!(out, "{function} {offset} adjacent {width}")?; }
                    }
                }
                previous_load = match op {
                    I32Load8S {..} | I32Load8U {..} | I64Load8S {..} | I64Load8U {..} => Some(1),
                    I32Load16S {..} | I32Load16U {..} | I64Load16S {..} | I64Load16U {..} => Some(2),
                    I32Load {..} | F32Load {..} | I64Load32S {..} | I64Load32U {..} => Some(4),
                    I64Load {..} | F64Load {..} => Some(8),
                    V128Load {..} => Some(16),
                    _ => None,
                };
                immediate = match op { I64Const { value } => Some(value), _ => None };
            }
        }
        function += 1;
    }
    Ok(())
}
