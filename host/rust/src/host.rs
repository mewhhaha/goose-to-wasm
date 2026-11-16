//! The imports of a direct Goose module, as scripts/run_wasmtime.py has them.
//!
//! Each is defined with the type the module declares for it, so one handler
//! serves both kinds of module: an address is an i32 in a 32-bit memory and an
//! i64 in a 64-bit one, and a slice is one packed i64 or two i64 (`Arguments`).
//! A handler reads integers as the signed numbers the Python runner sees and
//! refuses what it refuses, with the same words.

use std::collections::HashSet;
use std::ffi::OsStr;
use std::fs;
use std::io::Write;
use std::ops::Range;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::time::{SystemTime, UNIX_EPOCH};

use wasmtime::{Caller, Error, Extern, ExternType, Func, Linker, Memory, Module, Result, Val, ValType};

use crate::float::{f32_text, f64_text};
use crate::pytext::{normalized_path, parse_float, parse_int};

/// What a run keeps outside the module: its input, its output so far, and its
/// program arguments.
pub struct Host {
    input: Vec<u8>,
    /// Where the next whitespace-separated token of `input` starts.
    token_at: usize,
    /// Where `fd_read` continues.
    input_position: usize,
    pub out: Vec<u8>,
    pub err: Vec<u8>,
    arguments: Vec<Vec<u8>>,
    memory: Option<Memory>,
    /// The module's exported `goose.reserve`, once looked for.
    reserve: Option<Option<Func>>,
}

impl Host {
    pub fn new(input: Vec<u8>, arguments: Vec<Vec<u8>>) -> Host {
        Host { input, token_at: 0, input_position: 0, out: Vec::new(), err: Vec::new(), arguments, memory: None, reserve: None }
    }

    /// The next token of the input, split on ASCII whitespace.
    fn token(&mut self) -> Result<&[u8]> {
        let space = |byte: &u8| matches!(byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c);
        let rest = &self.input[self.token_at..];
        let Some(start) = rest.iter().position(|byte| !space(byte)) else {
            self.token_at = self.input.len();
            // What Python makes of the exhausted token generator.
            return Err(failure("generator raised StopIteration"));
        };
        let start = self.token_at + start;
        let end = self.input[start..].iter().position(space).map_or(self.input.len(), |length| start + length);
        self.token_at = end;
        Ok(&self.input[start..end])
    }
}

/// The program ended itself with this code.
#[derive(Debug)]
pub struct ProgramExit(pub i64);

impl std::fmt::Display for ProgramExit {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "program exit {}", self.0)
    }
}

impl std::error::Error for ProgramExit {}

/// A failure of the host's own, reported by its text alone (the Python
/// runner's exceptions), unlike a trap, which Wasmtime describes.
#[derive(Debug)]
pub struct HostFailure(pub String);

impl std::fmt::Display for HostFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl std::error::Error for HostFailure {}

pub fn failure(text: impl Into<String>) -> Error {
    Error::new(HostFailure(text.into()))
}

/// What an import gives back, before the type the module declared for it.
enum Out {
    Nothing,
    Integer(i64),
    Float(f64),
}

type Handler = for<'a, 'b> fn(&'a mut Caller<'b, Host>, &[Val]) -> Result<Out>;

/// Defines every import of `module`, each with the type declared for it.
pub fn define_imports(linker: &mut Linker<Host>, module: &Module) -> Result<()> {
    let mut defined = HashSet::new();
    for import in module.imports() {
        let key = (import.module(), import.name());
        if defined.contains(&key) {
            continue;
        }
        let (Some(handler), ExternType::Func(ty)) = (handler_for(import.module(), import.name()), import.ty()) else {
            return Err(failure(format!("unsupported direct host import: {}.{}", import.module(), import.name())));
        };
        let declared: Vec<ValType> = ty.results().collect();
        linker.func_new(import.module(), import.name(), ty, move |mut caller, values, results| {
            let out = handler(&mut caller, values)?;
            match (out, declared.as_slice()) {
                (Out::Nothing, []) => {}
                (_, []) => return Err(failure("callback produced results when it shouldn't")),
                (Out::Integer(value), [ValType::I32]) => results[0] = Val::I32(value as i32),
                (Out::Integer(value), [ValType::I64]) => results[0] = Val::I64(value),
                (Out::Float(value), [ValType::F64]) => results[0] = Val::F64(value.to_bits()),
                (Out::Float(value), [ValType::F32]) => results[0] = Val::F32((value as f32).to_bits()),
                _ => return Err(failure("host import result does not fit its declared type")),
            }
            Ok(())
        })?;
        defined.insert(key);
    }
    Ok(())
}

fn handler_for(module: &str, name: &str) -> Option<Handler> {
    let handler: Handler = match (module, name) {
        ("goose", "write") => goose_write,
        ("goose", "print_i64") => |caller, values| print(caller, integer(values, 0)?.to_string().as_bytes()),
        ("goose", "print_u64") => |caller, values| print(caller, (integer(values, 0)? as u64).to_string().as_bytes()),
        ("goose", "print_f64") => |caller, values| print(caller, f64_text(float(values, 0)?).as_bytes()),
        ("goose", "print_f32") => |caller, values| print(caller, f32_text(float(values, 0)? as f32).as_bytes()),
        ("goose", "format_f64") => |caller, values| format_float(caller, values, f64_text(float(values, 1)?)),
        ("goose", "format_f32") => |caller, values| format_float(caller, values, f32_text(float(values, 1)? as f32)),
        ("goose", "print_bool") => |caller, values| print(caller, if truth(values, 0)? { b"true" } else { b"false" }),
        ("goose", "newline") => |caller, _| print(caller, b"\n"),
        ("goose", "abort") => goose_abort,
        ("goose", "exit") | ("wasi_snapshot_preview1", "proc_exit") => |_, values| Err(Error::new(ProgramExit(integer(values, 0)?))),
        ("env", "bench_input") => |caller, _| {
            let token = caller.data_mut().token()?;
            parse_int(token).map(Out::Integer).map_err(failure)
        },
        ("env", "bench_input_f64") => |caller, _| {
            let token = caller.data_mut().token()?;
            parse_float(token).map(Out::Float).map_err(failure)
        },
        ("env", "bench_clock") | ("env", "gs_os_clock_ns") => |_, _| Ok(Out::Integer(monotonic_ns())),
        ("env", "bench_barrier") => |_, values| match values.first() {
            Some(Val::F32(_) | Val::F64(_)) => Ok(Out::Float(float(values, 0)?)),
            _ => Ok(Out::Integer(integer(values, 0)?)),
        },
        ("env", "bench_sink") | ("env", "emscripten_notify_memory_growth") | ("env", "gs_os_flush_stdout") => {
            |_, _| Ok(Out::Nothing)
        }
        // The stdlib's `os` externs, for a program that reads and writes
        // files (the compiler itself among them).
        ("env", "gs_os_read_file") => os_read_file,
        ("env", "gs_os_write_file") => |caller, values| os_write_file(caller, values, false),
        ("env", "gs_os_append_file") => |caller, values| os_write_file(caller, values, true),
        ("env", "gs_os_file_exists") => |caller, values| os_stat(caller, values, |kind| kind.is_file()),
        ("env", "gs_os_is_dir") => |caller, values| os_stat(caller, values, |kind| kind.is_dir()),
        ("env", "gs_os_write_stdout") => |caller, values| os_write(caller, values, false),
        ("env", "gs_os_write_stderr") => |caller, values| os_write(caller, values, true),
        ("env", "gs_os_arg_count") => |caller, _| Ok(Out::Integer(caller.data().arguments.len() as i64)),
        ("env", "gs_os_arg") => os_arg,
        ("env", "gs_os_getenv") => os_getenv,
        ("env", "gs_os_resource_dir") => |_, _| Ok(Out::Integer(0)),
        ("env", "gs_os_time_ns") => |_, _| Ok(Out::Integer(wall_ns())),
        ("env", "gs_find_any") => find_any,
        ("env", "gs_find_pair") => find_pair,
        // No process can be started from here: libc's system fails.
        ("env", "system") => |_, _| Ok(Out::Integer(-1)),
        ("wasi_snapshot_preview1", "args_sizes_get") => |caller, values| {
            write64(caller, integer(values, 0)?, 1)?;
            write64(caller, integer(values, 1)?, 8)?;
            Ok(Out::Integer(0))
        },
        ("wasi_snapshot_preview1", "args_get") => |caller, values| {
            let (argv, buffer) = (integer(values, 0)?, integer(values, 1)?);
            write64(caller, argv, buffer.into())?;
            write_bytes(caller, buffer.into(), b"program\0")?;
            Ok(Out::Integer(0))
        },
        ("wasi_snapshot_preview1", "environ_sizes_get") => |caller, values| {
            write64(caller, integer(values, 0)?, 0)?;
            write64(caller, integer(values, 1)?, 0)?;
            Ok(Out::Integer(0))
        },
        ("wasi_snapshot_preview1", "environ_get") => |_, _| Ok(Out::Integer(0)),
        ("wasi_snapshot_preview1", "clock_time_get") => |caller, values| {
            let value = match integer(values, 0)? {
                0 => wall_ns(),
                1 => monotonic_ns(),
                _ => return Ok(Out::Integer(28)),
            };
            write64(caller, integer(values, 2)?, value.into())?;
            Ok(Out::Integer(0))
        },
        ("wasi_snapshot_preview1", "fd_write") => fd_write,
        ("wasi_snapshot_preview1", "fd_read") => fd_read,
        ("wasi_snapshot_preview1", "fd_close") => {
            |_, values| Ok(Out::Integer(if (0..=2).contains(&integer(values, 0)?) { 0 } else { 8 }))
        }
        ("wasi_snapshot_preview1", "fd_seek") => {
            |_, values| Ok(Out::Integer(if (0..=2).contains(&integer(values, 0)?) { 70 } else { 8 }))
        }
        _ => return None,
    };
    Some(handler)
}

// Arguments.

fn value(values: &[Val], index: usize) -> Result<&Val> {
    values.get(index).ok_or_else(|| failure("host import declared with too few parameters"))
}

/// An integer argument as a signed number, an i32 widened.
fn integer(values: &[Val], index: usize) -> Result<i64> {
    match value(values, index)? {
        Val::I32(value) => Ok(i64::from(*value)),
        Val::I64(value) => Ok(*value),
        _ => Err(failure("host import declared with a parameter that is not an integer")),
    }
}

fn float(values: &[Val], index: usize) -> Result<f64> {
    match value(values, index)? {
        Val::F32(bits) => Ok(f64::from(f32::from_bits(*bits))),
        Val::F64(bits) => Ok(f64::from_bits(*bits)),
        _ => Err(failure("host import declared with a parameter that is not a float")),
    }
}

fn truth(values: &[Val], index: usize) -> Result<bool> {
    match value(values, index)? {
        Val::F32(_) | Val::F64(_) => Ok(float(values, index)? != 0.0),
        _ => Ok(integer(values, index)? != 0),
    }
}

/// The arguments of an import that takes slices. A 32-bit module passes a
/// slice as one i64 of pointer (low 32 bits) and element count; a 64-bit one
/// passes the pointer and the count as two i64. Which it is shows in how many
/// parameters there are for the `kinds` the import takes.
struct Arguments<'a> {
    values: &'a [Val],
    at: usize,
    wide: bool,
}

impl<'a> Arguments<'a> {
    fn new(values: &'a [Val], kinds: usize) -> Arguments<'a> {
        Arguments { values, at: 0, wide: values.len() > kinds }
    }

    fn integer(&mut self) -> Result<i64> {
        self.at += 1;
        integer(self.values, self.at - 1)
    }

    /// The pointer and count of a slice, not yet held to the memory.
    fn slice(&mut self) -> Result<(i128, i128)> {
        if self.wide {
            Ok((self.integer()?.into(), self.integer()?.into()))
        } else {
            let packed = self.integer()? as u64;
            Ok(((packed & 0xffff_ffff).into(), (packed >> 32).into()))
        }
    }
}

/// An address that may be an i32 above 2 GiB, which arrives negative; an i64
/// of a 64-bit memory keeps all its bits.
fn address(value: i64) -> i128 {
    if value < 0 {
        (value & 0xffff_ffff).into()
    } else {
        value.into()
    }
}

// Memory.

fn memory(caller: &mut Caller<'_, Host>) -> Result<Memory> {
    if let Some(memory) = caller.data().memory {
        return Ok(memory);
    }
    match caller.get_export("memory") {
        Some(Extern::Memory(memory)) => {
            caller.data_mut().memory = Some(memory);
            Ok(memory)
        }
        _ => Err(failure("module does not export memory")),
    }
}

/// The bytes of a memory of `size` bytes that `length` bytes at `pointer` are.
fn span(size: usize, pointer: i128, length: i128) -> Result<Range<usize>> {
    if pointer < 0 || length < 0 {
        return Err(failure("negative host address"));
    }
    if pointer + length > size as i128 {
        return Err(failure("host write is outside exported memory"));
    }
    Ok(pointer as usize..(pointer + length) as usize)
}

fn read_bytes(caller: &mut Caller<'_, Host>, pointer: i128, length: i128) -> Result<Vec<u8>> {
    let data = memory(caller)?.data(&*caller);
    Ok(data[span(data.len(), pointer, length)?].to_vec())
}

fn write_bytes(caller: &mut Caller<'_, Host>, pointer: i128, bytes: &[u8]) -> Result<()> {
    let data = memory(caller)?.data_mut(&mut *caller);
    let range = span(data.len(), pointer, bytes.len() as i128)?;
    data[range].copy_from_slice(bytes);
    Ok(())
}

fn write64(caller: &mut Caller<'_, Host>, pointer: i64, value: i128) -> Result<()> {
    // An unsigned 64-bit word, as Python's struct packs it or refuses to.
    let value = u64::try_from(value).map_err(|_| failure("'Q' format requires 0 <= number <= 18446744073709551615"))?;
    write_bytes(caller, pointer.into(), &value.to_le_bytes())
}

// The goose module.

fn print(caller: &mut Caller<'_, Host>, text: &[u8]) -> Result<Out> {
    caller.data_mut().out.extend_from_slice(text);
    Ok(Out::Nothing)
}

fn goose_write(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let (pointer, length) = (integer(values, 0)?, integer(values, 1)?);
    let (data, host) = memory(caller)?.data_and_store_mut(&mut *caller);
    host.out.extend_from_slice(&data[span(data.len(), pointer.into(), length.into())?]);
    Ok(Out::Nothing)
}

fn format_float(caller: &mut Caller<'_, Host>, values: &[Val], text: String) -> Result<Out> {
    if text.len() > 32 {
        return Err(failure("formatted float exceeds host buffer"));
    }
    let pointer = address(integer(values, 0)?);
    let data = memory(caller)?.data_mut(&mut *caller);
    let buffer = span(data.len(), pointer, 32)?;
    data[buffer.start..buffer.start + text.len()].copy_from_slice(text.as_bytes());
    Ok(Out::Integer(text.len() as i64))
}

fn goose_abort(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let (pointer, length, line) = (integer(values, 0)?, integer(values, 1)?, integer(values, 2)?);
    let message = read_bytes(caller, pointer.into(), length.into())?;
    Err(failure(format!("goose runtime error: {} (line {line})", String::from_utf8_lossy(&message))))
}

// The stdlib's os externs.

fn os_read_file(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let mut arguments = Arguments::new(values, 2);
    let (pointer, length) = arguments.slice()?;
    let control = arguments.integer()?;
    let path = read_bytes(caller, pointer, length)?;
    if path.contains(&0) {
        return Err(failure("embedded null byte"));
    }
    match fs::read(OsStr::from_bytes(&normalized_path(&path))) {
        Ok(contents) => {
            append_bytes(caller, control, &contents)?;
            Ok(Out::Integer(1))
        }
        Err(_) => Ok(Out::Integer(0)),
    }
}

fn os_write_file(caller: &mut Caller<'_, Host>, values: &[Val], append: bool) -> Result<Out> {
    let mut arguments = Arguments::new(values, 2);
    let (path_pointer, path_length) = arguments.slice()?;
    let (pointer, length) = arguments.slice()?;
    let data = memory(caller)?.data(&*caller);
    let path = &data[span(data.len(), path_pointer, path_length)?];
    let contents = &data[span(data.len(), pointer, length)?];
    if path.contains(&0) {
        return Err(failure("embedded null byte"));
    }
    let mut options = fs::OpenOptions::new();
    if append {
        options.append(true).create(true);
    } else {
        options.write(true).create(true).truncate(true);
    }
    let written = options.open(OsStr::from_bytes(path)).and_then(|mut file| file.write_all(contents));
    Ok(Out::Integer(written.is_ok().into()))
}

fn os_stat(caller: &mut Caller<'_, Host>, values: &[Val], is: fn(&fs::Metadata) -> bool) -> Result<Out> {
    let (pointer, length) = Arguments::new(values, 1).slice()?;
    let data = memory(caller)?.data(&*caller);
    let path = &data[span(data.len(), pointer, length)?];
    Ok(Out::Integer(fs::metadata(OsStr::from_bytes(path)).is_ok_and(|kind| is(&kind)).into()))
}

fn os_write(caller: &mut Caller<'_, Host>, values: &[Val], error: bool) -> Result<Out> {
    let (pointer, length) = Arguments::new(values, 1).slice()?;
    let (data, host) = memory(caller)?.data_and_store_mut(&mut *caller);
    let text = &data[span(data.len(), pointer, length)?];
    if error { &mut host.err } else { &mut host.out }.extend_from_slice(text);
    Ok(Out::Nothing)
}

fn os_arg(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let (index, control) = (integer(values, 0)?, integer(values, 1)?);
    let argument = usize::try_from(index).ok().and_then(|index| caller.data().arguments.get(index).cloned());
    if let Some(argument) = argument {
        append_bytes(caller, control, &argument)?;
    }
    Ok(Out::Nothing)
}

fn os_getenv(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let mut arguments = Arguments::new(values, 2);
    let (pointer, length) = arguments.slice()?;
    let control = arguments.integer()?;
    let name = read_bytes(caller, pointer, length)?;
    match std::env::var_os(OsStr::from_bytes(&name)) {
        Some(value) => {
            append_bytes(caller, control, &value.into_vec())?;
            Ok(Out::Integer(1))
        }
        None => Ok(Out::Integer(0)),
    }
}

/// Appends to the growable byte array whose control is at `control`: the
/// module's exported `goose.reserve(control, count) -> address` makes the
/// room, as a push in the program would (it grows memory, moves the array's
/// length and its region's cursor, and aborts if there is no room), and says
/// where the bytes go (docs/TARGET.md). An address is an i32 in a 32-bit
/// memory and an i64 in a 64-bit one.
fn append_bytes(caller: &mut Caller<'_, Host>, control: i64, bytes: &[u8]) -> Result<()> {
    let reserve = match caller.data().reserve {
        Some(found) => found,
        None => {
            let found = match caller.get_export("goose.reserve") {
                Some(Extern::Func(function)) => Some(function),
                _ => None,
            };
            caller.data_mut().reserve = Some(found);
            found
        }
    };
    let Some(reserve) = reserve else {
        return Err(failure("module does not export goose.reserve"));
    };
    let ty = reserve.ty(&*caller);
    let fitted = |kind: ValType, value: i64| match kind {
        ValType::I32 => Ok(Val::I32(value as i32)),
        ValType::I64 => Ok(Val::I64(value)),
        _ => Err(failure("goose.reserve is not (address, address) -> address")),
    };
    let mut kinds = ty.params();
    let arguments = match (kinds.next(), kinds.next(), kinds.next(), ty.results().len()) {
        (Some(first), Some(second), None, 1) => [fitted(first, control)?, fitted(second, bytes.len() as i64)?],
        _ => return Err(failure("goose.reserve is not (address, address) -> address")),
    };
    let mut destination = [Val::I64(0)];
    // A trap in there is reported as that call's own, as the Python runner
    // reports it, not as one more cause under this import's.
    reserve.call(&mut *caller, &arguments, &mut destination).map_err(|error| {
        if error.is::<ProgramExit>() || error.is::<HostFailure>() {
            error
        } else {
            failure(format!("{error:?}"))
        }
    })?;
    let destination = match destination[0] {
        Val::I32(destination) => address(destination.into()),
        Val::I64(destination) => address(destination),
        _ => return Err(failure("goose.reserve is not (address, address) -> address")),
    };
    write_bytes(caller, destination, bytes)
}

// std's byte-set searches: a set's members are its first 256 bytes.

fn find_any(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let mut arguments = Arguments::new(values, 2);
    let (pointer, length) = arguments.slice()?;
    let members = address(arguments.integer()?);
    let data = memory(caller)?.data(&*caller);
    let text = &data[span(data.len(), pointer, length)?];
    let members = &data[span(data.len(), members, 256)?];
    let found = text.iter().position(|&byte| members[usize::from(byte)] != 0);
    Ok(Out::Integer(found.map_or(-1, |index| index as i64)))
}

fn find_pair(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let mut arguments = Arguments::new(values, 4);
    let (pointer, length) = arguments.slice()?;
    let (first, distance, second) = (address(arguments.integer()?), arguments.integer()?, address(arguments.integer()?));
    let data = memory(caller)?.data(&*caller);
    let text = &data[span(data.len(), pointer, length)?];
    let first = &data[span(data.len(), first, 256)?];
    let second = &data[span(data.len(), second, 256)?];
    if let Ok(distance) = usize::try_from(distance) {
        let found = (0..text.len().saturating_sub(distance))
            .find(|&index| first[usize::from(text[index])] != 0 && second[usize::from(text[index + distance])] != 0);
        return Ok(Out::Integer(found.map_or(-1, |index| index as i64)));
    }
    // A negative distance, which std never passes: Python's indexing, where
    // an index before the start counts from the end.
    let (count, distance) = (text.len() as i128, i128::from(distance));
    let at = |index: i128| -> Result<u8> {
        let index = if index < 0 { index + count } else { index };
        if index < 0 || index >= count {
            return Err(failure("index out of range"));
        }
        Ok(text[index as usize])
    };
    for index in 0..count - distance {
        if first[usize::from(at(index)?)] != 0 && second[usize::from(at(index + distance)?)] != 0 {
            return Ok(Out::Integer(index as i64));
        }
    }
    Ok(Out::Integer(-1))
}

// The WASI subset of the C oracle's standalone profile: 64-bit pointers and
// sizes, 16-byte iovecs.

fn iovecs(caller: &mut Caller<'_, Host>, pointer: i64, count: i64) -> Result<Vec<(u64, u64)>> {
    let data = read_bytes(caller, pointer.into(), i128::from(count) * 16)?;
    let word = |bytes: &[u8]| u64::from_le_bytes(bytes.try_into().expect("eight bytes"));
    Ok(data.chunks_exact(16).map(|pair| (word(&pair[..8]), word(&pair[8..]))).collect())
}

fn fd_write(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let (fd, pointer, count, written) = (integer(values, 0)?, integer(values, 1)?, integer(values, 2)?, integer(values, 3)?);
    if fd != 1 && fd != 2 {
        return Ok(Out::Integer(8));
    }
    let mut total: i128 = 0;
    for (start, size) in iovecs(caller, pointer, count)? {
        let (data, host) = memory(caller)?.data_and_store_mut(&mut *caller);
        let text = &data[span(data.len(), start.into(), size.into())?];
        if fd == 1 { &mut host.out } else { &mut host.err }.extend_from_slice(text);
        total += i128::from(size);
    }
    write64(caller, written, total)?;
    Ok(Out::Integer(0))
}

fn fd_read(caller: &mut Caller<'_, Host>, values: &[Val]) -> Result<Out> {
    let (fd, pointer, count, read) = (integer(values, 0)?, integer(values, 1)?, integer(values, 2)?, integer(values, 3)?);
    if fd != 0 {
        return Ok(Out::Integer(8));
    }
    let mut total = 0;
    for (start, size) in iovecs(caller, pointer, count)? {
        let (data, host) = memory(caller)?.data_and_store_mut(&mut *caller);
        let rest = &host.input[host.input_position..];
        let taken = rest.len().min(usize::try_from(size).unwrap_or(usize::MAX));
        let range = span(data.len(), start.into(), taken as i128)?;
        data[range].copy_from_slice(&rest[..taken]);
        host.input_position += taken;
        total += taken;
        if (taken as u64) < size {
            break;
        }
    }
    write64(caller, read, total as i128)?;
    Ok(Out::Integer(0))
}

// Clocks, as Python's time.perf_counter_ns and time.time_ns read them.

fn monotonic_ns() -> i64 {
    let mut time = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: clock_gettime fills the timespec it is given.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut time) };
    time.tv_sec as i64 * 1_000_000_000 + time.tv_nsec as i64
}

fn wall_ns() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |since| since.as_nanos() as i64)
}
