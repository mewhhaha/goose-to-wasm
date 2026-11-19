// Audit fixed Goose-to-Wasm compiler modules with the known publisher and no prefix mapper.
// Reconstruct the entire candidate using only checked deletions in the baseline.
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, VecDeque};
use std::env;
use std::fs;
use std::ops::Range;
use wasmparser::{
    BinaryReader, ElementItems, Encoding, ExternalKind, FuncType, FunctionBody, Operator as Op, Parser,
    Payload, TypeRef, ValType, Validator,
};

const HEAD: u32 = 11;
const PUBLISH_32: &str = "9cfd92e5ef1dbd9371b4694a100e6e32034106665f9ade97a55299bd38ca943d";
const PUBLISH_64: &str = "22319828cc7ff0799029fa0199314eb72250495aed5c50e5d109c76414589144";

fn sha(data: &[u8]) -> String {
    format!("{:x}", Sha256::digest(data))
}

fn leb(mut value: usize, out: &mut Vec<u8>) {
    while value >= 128 {
        out.push((value as u8) | 0x80);
        value >>= 7;
    }
    out.push(value as u8);
}

fn section(data: &[u8], wanted: u8) -> Range<usize> {
    let mut stream = BinaryReader::new(&data[8..], 8);
    while !stream.eof() {
        let start = stream.original_position() as usize;
        let kind = stream.read_u8().unwrap();
        let length = stream.read_var_u32().unwrap() as usize;
        stream.read_bytes(length).unwrap();
        if kind == wanted {
            return start..stream.original_position() as usize;
        }
    }
    panic!("missing section {wanted}");
}

#[derive(Default)]
struct Module<'a> {
    imports: u32,
    types: Vec<FuncType>,
    functions: Vec<u32>,
    bodies: Vec<FunctionBody<'a>>,
    head_ok: bool,
    wide: bool,
    start: Option<u32>,
    reserve: Option<u32>,
    first_thunk: Option<u32>,
}

impl Module<'_> {
    fn signature(&self, function: u32) -> &FuncType {
        &self.types[self.functions[(function - self.imports) as usize] as usize]
    }

    fn addr(&self) -> ValType {
        if self.wide {
            ValType::I64
        } else {
            ValType::I32
        }
    }
}

fn parse(data: &[u8]) -> Module<'_> {
    Validator::new().validate_all(data).unwrap();
    let mut module = Module::default();
    for p in Parser::new(0).parse_all(data) {
        match p.unwrap() {
            Payload::Version { encoding, num, .. } => {
                assert_eq!(encoding, Encoding::Module);
                assert_eq!(num, 1);
            }
            Payload::TypeSection(types) => {
                module.types = types.into_iter_err_on_gc_types().map(Result::unwrap).collect();
            }
            Payload::ImportSection(imports) => {
                for import in imports.into_imports() {
                    assert!(
                        matches!(import.unwrap().ty, TypeRef::Func(_)),
                        "nonfunction import"
                    );
                    module.imports += 1;
                }
            }
            Payload::FunctionSection(functions) => {
                module.functions = functions.into_iter().map(Result::unwrap).collect();
            }
            Payload::MemorySection(memories) => {
                assert_eq!(memories.count(), 1);
                let memory = memories.into_iter().next().unwrap().unwrap();
                assert!(!memory.shared);
                module.wide = memory.memory64;
            }
            Payload::GlobalSection(globals) => {
                let head = globals.into_iter().nth(HEAD as usize).unwrap().unwrap();
                let mut initializer = head.init_expr.get_operators_reader();
                let zero = match initializer.read().unwrap() {
                    Op::I32Const { value: 0 } => !module.wide,
                    Op::I64Const { value: 0 } => module.wide,
                    _ => false,
                };
                assert!(zero && matches!(initializer.read().unwrap(), Op::End));
                assert!(initializer.eof() && head.ty.mutable && head.ty.content_type == module.addr());
                module.head_ok = true;
            }
            Payload::ExportSection(exports) => {
                for export in exports {
                    let export = export.unwrap();
                    match (export.kind, export.name) {
                        (ExternalKind::Func, "_start") => module.start = Some(export.index),
                        (ExternalKind::Func, "goose.reserve") => module.reserve = Some(export.index),
                        (ExternalKind::Func, _) => panic!("unexpected exported function {}", export.name),
                        (ExternalKind::Global, _) => {
                            assert_ne!(export.index, HEAD, "exported head")
                        }
                        _ => {}
                    }
                }
            }
            Payload::ElementSection(elements) => {
                assert_eq!(elements.count(), 1);
                let element = elements.into_iter().next().unwrap().unwrap();
                let ElementItems::Functions(thunks) = element.items else {
                    panic!("unexpected function table layout");
                };
                let thunks: Vec<_> = thunks.into_iter().map(Result::unwrap).collect();
                assert!(!thunks.is_empty());
                assert!(thunks.windows(2).all(|pair| pair[0] + 1 == pair[1]));
                module.first_thunk = thunks.first().copied();
            }
            Payload::CodeSectionEntry(body) => module.bodies.push(body),
            _ => {}
        }
    }
    assert!(module.head_ok, "missing private head");
    assert_eq!(module.functions.len(), module.bodies.len());
    module
}

fn offsets<'a>(body: &FunctionBody<'a>) -> Vec<(usize, Op<'a>)> {
    let mut reader = body.get_operators_reader().unwrap();
    let mut ops = Vec::new();
    while !reader.eof() {
        ops.push((reader.original_position() as usize, reader.read().unwrap()));
    }
    ops
}

// Resolve branch destinations using the structured Wasm labels, independently
// of Goose's local-slot allocator and of the byte sequences we plan to remove.
fn flow(ops: &[(usize, Op<'_>)], data: &[u8]) -> Vec<Vec<usize>> {
    let sentinel = ops.len();
    let mut stack = vec![sentinel];
    let mut end = vec![sentinel - 1; sentinel + 1];
    let mut otherwise = vec![None; sentinel];
    let mut edges = Vec::with_capacity(sentinel);
    enum Edge {
        Next(usize),
        ExitLabel(usize),
        FalsePath(usize),
    }
    for (index, (position, op)) in ops.iter().enumerate() {
        use Edge::{ExitLabel, FalsePath, Next};
        let target = |depth: u32| stack[stack.len() - 1 - depth as usize];
        let next = Next(index + 1);
        let successors = match op {
            Op::If { .. } => {
                stack.push(index);
                vec![next, FalsePath(index)]
            }
            Op::Block { .. } | Op::Loop { .. } => {
                stack.push(index);
                vec![next]
            }
            Op::Else => {
                let label = *stack.last().unwrap();
                otherwise[label] = Some(index);
                vec![ExitLabel(label)]
            }
            Op::End => {
                end[stack.pop().unwrap()] = index;
                vec![next]
            }
            Op::Br { relative_depth } => vec![ExitLabel(target(*relative_depth))],
            Op::BrIf { relative_depth } => vec![next, ExitLabel(target(*relative_depth))],
            Op::BrTable { targets } => targets
                .targets()
                .chain([Ok(targets.default())])
                .map(|depth| ExitLabel(target(depth.unwrap())))
                .collect(),
            Op::Return | Op::Unreachable => vec![],
            _ => {
                // The compiler artifacts use core structured control flow.
                // Reject other control families rather than assuming fallthrough.
                assert!(
                    !matches!(data[*position], 0x06..=0x09 | 0x0a | 0x12..=0x15 | 0x18..=0x19 | 0x1f | 0xd5..=0xfb),
                    "unexpected control instruction {op:?} at {position}"
                );
                vec![next]
            }
        };
        edges.push(successors);
    }
    assert!(stack.is_empty());
    edges
        .into_iter()
        .map(|edges| {
            edges
                .into_iter()
                .filter_map(|edge| {
                    let index = match edge {
                        Edge::Next(index) => index,
                        Edge::FalsePath(label) => otherwise[label].unwrap_or(end[label]) + 1,
                        Edge::ExitLabel(label)
                            if label < sentinel && matches!(ops[label].1, Op::Loop { .. }) =>
                        {
                            label + 1
                        }
                        Edge::ExitLabel(label) => end[label] + 1,
                    };
                    (index < sentinel).then_some(index)
                })
                .collect()
        })
        .collect()
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Access {
    Save,
    Restore,
}

fn verify_marks(ops: &[(usize, Op<'_>)], data: &[u8], marks: &[Option<Access>], function: u32) {
    let mut tracked = BTreeMap::new();
    for (index, (_, op)) in ops.iter().enumerate() {
        match (marks[index], op) {
            (Some(Access::Save), Op::LocalSet { local_index }) => {
                tracked.insert(*local_index, true);
            }
            (Some(Access::Restore), Op::LocalGet { local_index }) => {
                tracked.entry(*local_index).or_insert(false);
            }
            (None, _) => {}
            _ => unreachable!("a mark must be an ordinary local set or get"),
        }
    }
    if tracked.is_empty() {
        return;
    }

    const ORDINARY: u8 = 1;
    const SAVED: u8 = 2;
    let edges = flow(ops, data);
    for (local, has_save) in tracked {
        assert!(
            has_save,
            "restored slot {local} in function {function} has no save"
        );
        let mut entering = vec![0; ops.len()];
        entering[0] = ORDINARY;
        let mut todo = VecDeque::from([0]);
        while let Some(index) = todo.pop_front() {
            let mut state = entering[index];
            match ops[index].1 {
                Op::LocalGet { local_index } if local_index == local => {
                    let expected = if marks[index] == Some(Access::Restore) {
                        SAVED
                    } else {
                        ORDINARY
                    };
                    assert_eq!(
                        state, expected,
                        "slot {local} has an unexpected reaching write in function {function} at {}",
                        ops[index].0
                    );
                }
                Op::LocalSet { local_index } | Op::LocalTee { local_index } if local_index == local => {
                    state = if marks[index] == Some(Access::Save) {
                        SAVED
                    } else {
                        ORDINARY
                    };
                }
                _ => {}
            }
            for &next in &edges[index] {
                let merged = entering[next] | state;
                if merged != entering[next] {
                    entering[next] = merged;
                    todo.push_back(next);
                }
            }
        }
    }
}

#[derive(Default)]
struct Counts {
    calls: usize,
    saves: usize,
    restores: usize,
    deleted_bytes: usize,
}

fn rewritten(
    baseline: &[u8],
    body: &FunctionBody<'_>,
    module: &Module<'_>,
    function: u32,
    publisher: u32,
    counts: &mut Counts,
) -> Vec<u8> {
    let mut removals = Vec::new();
    let ops = offsets(body);
    let span = body.range().start as usize..body.range().end as usize;
    let mut marks = vec![None; ops.len()];
    let position = |index: usize| ops.get(index).map_or(span.end, |part| part.0);
    let mut local_end = span.start;
    let start = module.start.unwrap();
    let first_thunk = module.first_thunk.unwrap();
    let sig = module.signature(function);
    let word = module.addr();
    let allowed_helper = function == module.reserve.unwrap_or(u32::MAX)
        || (function > publisher
            && function < first_thunk
            && sig.results().is_empty()
            && (sig.params() == [word, word, word, ValType::I32]
                || sig.params() == [word, word, ValType::I32]));
    let mut index = 0;
    while index < ops.len() {
        let removed = match ops[index].1 {
            Op::GlobalGet { global_index: HEAD } => {
                assert!(function <= start, "head read outside user body {function}");
                assert!(
                    matches!(ops[index + 1].1, Op::LocalSet { .. }),
                    "head read is not a save"
                );
                marks[index + 1] = Some(Access::Save);
                counts.saves += 1;
                let removed = index..index + 2;
                index += 1;
                Some(removed)
            }
            Op::GlobalSet { global_index: HEAD } => {
                assert!(function <= start, "head write outside user body {function}");
                assert!(
                    index >= 1 && matches!(ops[index - 1].1, Op::LocalGet { .. }),
                    "head write is not a restore"
                );
                marks[index - 1] = Some(Access::Restore);
                counts.restores += 1;
                Some(index - 1..index + 1)
            }
            Op::Call { function_index } if function_index == publisher => {
                assert!(
                    function <= start || allowed_helper,
                    "publisher call outside eligible body {function}"
                );
                assert!(index >= 2 && matches!(ops[index - 2].1, Op::LocalGet { .. }));
                assert!(
                    match ops[index - 1].1 {
                        Op::I32Const { value: 0 | 4 } => !module.wide,
                        Op::I64Const { value: 0 | 8 } => module.wide,
                        _ => false,
                    },
                    "publisher operand is not a width-correct header word"
                );
                counts.calls += 1;
                Some(index - 2..index + 1)
            }
            Op::RefFunc { function_index } | Op::ReturnCall { function_index }
                if function_index == publisher =>
            {
                panic!("unexpected indirect publisher reference in {function}")
            }
            _ => None,
        };
        if let Some(removed) = removed {
            let begin = position(removed.start);
            let end = position(removed.end);
            assert!(begin >= local_end && end > begin);
            local_end = end;
            counts.deleted_bytes += end - begin;
            removals.push(begin..end);
        }
        index += 1;
    }
    verify_marks(&ops, baseline, &marks, function);
    let mut result = Vec::new();
    let mut copied = span.start;
    for omitted in removals {
        result.extend_from_slice(&baseline[copied..omitted.start]);
        copied = omitted.end;
    }
    result.extend_from_slice(&baseline[copied..span.end]);
    result
}

fn main() {
    let paths: Vec<_> = env::args_os().skip(1).collect();
    assert_eq!(paths.len(), 2, "usage: audit-publication BEFORE.wasm AFTER.wasm");
    let old = fs::read(&paths[0]).unwrap();
    let new = fs::read(&paths[1]).unwrap();
    let before = parse(&old);
    let after = parse(&new);
    let old_code = section(&old, 10);
    let new_code = section(&new, 10);
    assert!(
        old[..old_code.start] == new[..new_code.start],
        "declarations changed"
    );
    assert!(
        old[old_code.end..] == new[new_code.end..],
        "sections after code changed"
    );
    assert_eq!(before.bodies.len(), after.bodies.len(), "body count changed");
    let start = before.start.unwrap();
    let first_thunk = before.first_thunk.unwrap();
    let digest = if before.wide { PUBLISH_64 } else { PUBLISH_32 };
    let matches: Vec<_> = before
        .bodies
        .iter()
        .enumerate()
        .filter_map(|(ordinal, body)| {
            let index = before.imports + ordinal as u32;
            let range = body.range().start as usize..body.range().end as usize;
            (index > start && index < first_thunk && sha(&old[range]) == digest).then_some(index)
        })
        .collect();
    assert_eq!(matches.len(), 1, "publication helper identity is ambiguous");
    let publisher = matches[0];
    let sig = before.signature(publisher);
    assert_eq!(sig.params(), [before.addr(); 2]);
    assert!(sig.results().is_empty());
    assert_eq!(publisher, start + 3, "unexpected helper placement");

    let mut code = Vec::new();
    leb(before.bodies.len(), &mut code);
    let mut counts = Counts::default();
    let mut modified = Vec::new();
    for (ordinal, (lhs, rhs)) in before.bodies.iter().zip(&after.bodies).enumerate() {
        let index = before.imports + ordinal as u32;
        let old_body = &old[lhs.range().start as usize..lhs.range().end as usize];
        let expected = if index == publisher {
            old_body.to_vec()
        } else {
            rewritten(&old, lhs, &before, index, publisher, &mut counts)
        };
        let actual = &new[rhs.range().start as usize..rhs.range().end as usize];
        assert!(
            expected == actual,
            "unexpected byte difference in function {index}"
        );
        if expected.len() != old_body.len() {
            modified.push(index);
        }
        leb(expected.len(), &mut code);
        code.extend_from_slice(&expected);
    }
    assert!(counts.calls > 0 && counts.saves > 0 && counts.restores > 0);
    let mut reconstructed = old[..old_code.start].to_vec();
    reconstructed.push(10);
    leb(code.len(), &mut reconstructed);
    reconstructed.extend_from_slice(&code);
    reconstructed.extend_from_slice(&old[old_code.end..]);
    assert!(
        reconstructed == new,
        "module bytes differ from checked reconstruction"
    );

    let changed_helpers: Vec<_> = modified.iter().copied().filter(|index| *index > start).collect();
    println!(concat!(
        "{{\n  \"decoder\": \"wasmparser 0.261.0\",",
        "\n  \"baseline\": {{\"bytes\": {}, \"sha256\": \"{}\"}},",
        "\n  \"candidate\": {{\"bytes\": {}, \"sha256\": \"{}\"}},",
        "\n  \"memory_bits\": {},\n  \"global_head\": {{\"index\": 11, \"initial\": 0, \"private\": true}},",
        "\n  \"publisher\": {{\"index\": {}, \"body_sha256\": \"{}\", \"identical\": true}},",
        "\n  \"prefix_mapper_present\": false,\n  \"start_function\": {},\n  \"first_thunk\": {},\n  \"function_bodies\": {},",
        "\n  \"changed_bodies\": {},\n  \"unchanged_bodies\": {},\n  \"changed_non_user_bodies\": {:?},",
        "\n  \"removed_publisher_calls\": {},\n  \"removed_private_head_saves\": {},",
        "\n  \"removed_private_head_restores\": {},\n  \"removed_instruction_bytes\": {},",
        "\n  \"encoding_bytes_removed\": {},\n  \"all_non_code_sections_identical\": true,",
        "\n  \"entire_candidate_reconstructed\": true\n}}"),
        old.len(), sha(&old), new.len(), sha(&new), if before.wide { 64 } else { 32 },
        publisher, digest, start, first_thunk, before.bodies.len(), modified.len(),
        before.bodies.len() - modified.len(), changed_helpers, counts.calls, counts.saves,
        counts.restores, counts.deleted_bytes, old.len() - new.len() - counts.deleted_bytes);
}
