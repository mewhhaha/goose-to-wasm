#![forbid(unsafe_code)]
//! Thin safe-Rust `wtime` host wrapper for Direct Goose Wasm32/Wasm64 modules,
//! including Blot2 (`cb1e9e15`) compiled directly to Wasm64 (`env.blot_*`).
//!
//! Usage:
//!   goose-wtime module.wasm [--entry NAME] [--execution decoded|compact|register]
//!               [--max-instructions N] [--max-memory-mb N] [--timing-json PATH]
//!               [-- program arguments...]

use std::collections::HashMap;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::FileExt;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use wtime_runtime::{
    Caller, Config, Engine, ExecutionPolicy, External, Func, Linker, Memory, RunOutcome, Store,
    Value,
};
use wtime_types::{Error, ErrorKind, FeatureSet, ResourceLimits, ValType};

const USAGE: &str = "\
usage: goose-wtime module.wasm [--entry NAME] [--execution decoded|compact|register]
                   [--max-instructions N] [--max-memory-mb N] [--timing-json PATH]
                   [-- program arguments...]";

const SENTINEL_EXIT_PREFIX: &str = "__goose_wtime_exit__:";

struct Options {
    module: PathBuf,
    entry: Option<String>,
    policy: ExecutionPolicy,
    max_instructions: usize,
    max_memory_mb: u64,
    timing_json: Option<PathBuf>,
    program_args: Vec<Vec<u8>>,
}

struct DirCursor {
    entries: Vec<Vec<u8>>,
    index: usize,
}

struct HostState {
    memory: Option<Memory>,
    reserve_fn: Option<Func>,
    args: Vec<Vec<u8>>,
    start_instant: Instant,
    next_owner: AtomicU64,
    next_fd: i32,
    files: HashMap<i32, File>,
    next_dir: i64,
    dirs: HashMap<i64, DirCursor>,
    last_errno: AtomicI32,
    exit_code: Option<i32>,
    abort_message: Option<String>,
}

impl HostState {
    fn new(args: Vec<Vec<u8>>) -> Self {
        Self {
            memory: None,
            reserve_fn: None,
            args,
            start_instant: Instant::now(),
            next_owner: AtomicU64::new(1),
            next_fd: 3,
            files: HashMap::new(),
            next_dir: 1,
            dirs: HashMap::new(),
            last_errno: AtomicI32::new(0),
            exit_code: None,
            abort_message: None,
        }
    }

    fn alloc_fd(&mut self, file: File) -> i32 {
        let fd = self.next_fd;
        self.next_fd = self.next_fd.saturating_add(1);
        self.files.insert(fd, file);
        fd
    }

    fn set_errno(&self, err: &io::Error) -> i32 {
        let code = err.raw_os_error().unwrap_or(22); // EINVAL
        self.last_errno.store(code, Ordering::Relaxed);
        -code
    }
}

fn host_err(msg: impl Into<String>) -> Error {
    Error::new(ErrorKind::Host, msg)
}

fn exit_err(code: i32) -> Error {
    Error::new(ErrorKind::Host, format!("{SENTINEL_EXIT_PREFIX}{code}"))
}

fn arg_i64(vals: &[Value], idx: usize) -> Result<i64, Error> {
    match vals.get(idx) {
        Some(Value::I32(v)) => Ok(i64::from(*v)),
        Some(Value::I64(v)) => Ok(*v),
        _ => Err(host_err("expected integer argument")),
    }
}

fn arg_u64(vals: &[Value], idx: usize) -> Result<u64, Error> {
    match vals.get(idx) {
        Some(Value::I32(v)) => Ok(u64::from(*v as u32)),
        Some(Value::I64(v)) => Ok(*v as u64),
        _ => Err(host_err("expected unsigned integer argument")),
    }
}

fn arg_f64(vals: &[Value], idx: usize) -> Result<f64, Error> {
    match vals.get(idx) {
        Some(Value::F32(bits)) => Ok(f64::from(f32::from_bits(*bits))),
        Some(Value::F64(bits)) => Ok(f64::from_bits(*bits)),
        _ => Err(host_err("expected float argument")),
    }
}

fn arg_f32(vals: &[Value], idx: usize) -> Result<f32, Error> {
    match vals.get(idx) {
        Some(Value::F32(bits)) => Ok(f32::from_bits(*bits)),
        Some(Value::F64(bits)) => Ok(f64::from_bits(*bits) as f32),
        _ => Err(host_err("expected f32 argument")),
    }
}

fn read_slice_arg(vals: &[Value], idx: usize, wide: bool) -> Result<(u64, usize), Error> {
    if wide {
        let ptr = arg_u64(vals, idx)?;
        let len = arg_u64(vals, idx + 1)? as usize;
        Ok((ptr, len))
    } else {
        let packed = arg_u64(vals, idx)?;
        Ok((packed & 0xffff_ffff, (packed >> 32) as usize))
    }
}

fn mem_of(state: &Arc<Mutex<HostState>>) -> Result<Memory, Error> {
    state
        .lock()
        .unwrap()
        .memory
        .ok_or_else(|| host_err("module does not export memory"))
}

fn read_cstr(caller: &mut Caller<'_>, mem: Memory, ptr: u64) -> Result<Vec<u8>, Error> {
    let mut out = Vec::new();
    let mut off = ptr;
    loop {
        let chunk = caller.store().read_memory(mem, off, 1)?;
        let b = chunk[0];
        if b == 0 {
            return Ok(out);
        }
        out.push(b);
        off += 1;
        if out.len() > 65536 {
            return Err(host_err("C string exceeds 64 KiB"));
        }
    }
}

fn path_from_bytes(bytes: &[u8]) -> PathBuf {
    PathBuf::from(OsStr::from_bytes(bytes))
}

fn format_float_goose(val: f64) -> String {
    if val.is_nan() {
        return "nan".to_string();
    }
    if val.is_infinite() {
        return if val.is_sign_negative() {
            "-inf".to_string()
        } else {
            "inf".to_string()
        };
    }
    if val == 0.0 {
        return if val.is_sign_negative() {
            "-0".to_string()
        } else {
            "0".to_string()
        };
    }
    format!("{val}")
}

fn pure_frexp(x: f64) -> (f64, i32) {
    if x == 0.0 || !x.is_finite() {
        return (x, 0);
    }
    let mut bits = x.to_bits();
    let mut exp = ((bits >> 52) & 0x7ff) as i32;
    let mut adjust = 0i32;
    if exp == 0 {
        // Subnormal: scale by 2^54.
        let scaled = x * f64::from_bits(0x4350_0000_0000_0000);
        bits = scaled.to_bits();
        exp = ((bits >> 52) & 0x7ff) as i32;
        adjust = -54;
    }
    let e = exp - 1022 + adjust;
    let mant = f64::from_bits((bits & 0x800f_ffff_ffff_ffff) | (1022u64 << 52));
    (mant, e)
}

fn pure_ldexp(mut x: f64, mut exp: i32) -> f64 {
    if x == 0.0 || !x.is_finite() || exp == 0 {
        return x;
    }
    while exp > 1023 {
        x *= f64::from_bits(0x7fe0_0000_0000_0000);
        exp -= 1023;
        if !x.is_finite() {
            return x;
        }
    }
    while exp < -1022 {
        x *= f64::from_bits(0x0010_0000_0000_0000);
        exp += 1022;
        if x == 0.0 {
            return x;
        }
    }
    let factor = f64::from_bits(((exp + 1023) as u64) << 52);
    x * factor
}

fn reserve_and_append(
    caller: &mut Caller<'_>,
    state: &Arc<Mutex<HostState>>,
    header: u64,
    bytes: &[u8],
    wide: bool,
) -> Result<(), Error> {
    if bytes.is_empty() {
        return Ok(());
    }
    let (mem, reserve) = {
        let guard = state.lock().unwrap();
        (
            guard.memory.ok_or_else(|| host_err("missing memory"))?,
            guard
                .reserve_fn
                .ok_or_else(|| host_err("module does not export goose.reserve"))?,
        )
    };
    let args = if wide {
        vec![Value::I64(header as i64), Value::I64(bytes.len() as i64)]
    } else {
        vec![Value::I32(header as i32), Value::I32(bytes.len() as i32)]
    };
    let dst = match caller.invoke(reserve, &args)? {
        RunOutcome::Returned(vals) => arg_u64(&vals, 0)?,
        _ => return Err(host_err("goose.reserve did not return normally")),
    };
    caller.store().write_memory(mem, dst, bytes)
}

fn box_result(results: &[ValType], out: Out) -> Result<Vec<Value>, Error> {
    match (out, results) {
        (Out::Void, []) => Ok(vec![]),
        (Out::Int(v), [ValType::I32]) => Ok(vec![Value::I32(v as i32)]),
        (Out::Int(v), [ValType::I64]) => Ok(vec![Value::I64(v)]),
        (Out::F32(v), [ValType::F32]) => Ok(vec![Value::F32(v.to_bits())]),
        (Out::F64(v), [ValType::F64]) => Ok(vec![Value::F64(v.to_bits())]),
        (Out::F64(v), [ValType::F32]) => Ok(vec![Value::F32((v as f32).to_bits())]),
        _ => Err(host_err(format!("result type mismatch: expected {results:?}"))),
    }
}

enum Out {
    Void,
    Int(i64),
    F32(f32),
    F64(f64),
}

fn dispatch_import(
    module: &str,
    name: &str,
    caller: &mut Caller<'_>,
    args: &[Value],
    state: &Arc<Mutex<HostState>>,
    params: &[ValType],
) -> Result<Out, Error> {
    let wide = params.iter().any(|p| *p == ValType::I64);
    match (module, name) {
        // --- goose.* core host ---
        ("goose", "write") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let len = arg_u64(args, 1)? as usize;
            let data = caller.store().read_memory(mem, ptr, len)?;
            let _ = io::stdout().write_all(&data);
            Ok(Out::Void)
        }
        ("goose", "print_i64") => {
            let _ = write!(io::stdout(), "{}", arg_i64(args, 0)?);
            Ok(Out::Void)
        }
        ("goose", "print_u64") => {
            let _ = write!(io::stdout(), "{}", arg_u64(args, 0)?);
            Ok(Out::Void)
        }
        ("goose", "print_f64") => {
            let _ = write!(io::stdout(), "{}", format_float_goose(arg_f64(args, 0)?));
            Ok(Out::Void)
        }
        ("goose", "print_f32") => {
            let _ = write!(
                io::stdout(),
                "{}",
                format_float_goose(f64::from(arg_f32(args, 0)?))
            );
            Ok(Out::Void)
        }
        ("goose", "print_bool") => {
            let _ = io::stdout().write_all(if arg_i64(args, 0)? != 0 {
                b"true"
            } else {
                b"false"
            });
            Ok(Out::Void)
        }
        ("goose", "newline") => {
            let _ = io::stdout().write_all(b"\n");
            Ok(Out::Void)
        }
        ("goose", "format_f64") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let text = format_float_goose(arg_f64(args, 1)?);
            let bytes = text.as_bytes();
            if bytes.len() > 32 {
                return Err(host_err("formatted float exceeds host buffer"));
            }
            caller.store().write_memory(mem, ptr, bytes)?;
            Ok(Out::Int(bytes.len() as i64))
        }
        ("goose", "format_f32") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let text = format_float_goose(f64::from(arg_f32(args, 1)?));
            let bytes = text.as_bytes();
            if bytes.len() > 32 {
                return Err(host_err("formatted float exceeds host buffer"));
            }
            caller.store().write_memory(mem, ptr, bytes)?;
            Ok(Out::Int(bytes.len() as i64))
        }
        ("goose", "abort") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let len = arg_u64(args, 1)? as usize;
            let line = arg_i64(args, 2)?;
            let msg = caller.store().read_memory(mem, ptr, len)?;
            let text = format!(
                "goose runtime error: {} (line {line})",
                String::from_utf8_lossy(&msg)
            );
            state.lock().unwrap().abort_message = Some(text.clone());
            Err(host_err(text))
        }
        ("goose", "exit") => {
            let code = arg_i64(args, 0)? as i32;
            state.lock().unwrap().exit_code = Some(code);
            Err(exit_err(code))
        }

        // --- Math imports ---
        ("env", "frexp") => {
            let mem = mem_of(state)?;
            let (mant, exp) = pure_frexp(arg_f64(args, 0)?);
            let ptr = arg_u64(args, 1)?;
            caller.store().write_memory(mem, ptr, &exp.to_le_bytes())?;
            Ok(Out::F64(mant))
        }
        ("env", "ldexp") => Ok(Out::F64(pure_ldexp(
            arg_f64(args, 0)?,
            arg_i64(args, 1)? as i32,
        ))),
        ("env", "acosh" | "gs_acosh") => Ok(Out::F64(arg_f64(args, 0)?.acosh())),
        ("env", "asinh" | "gs_asinh") => Ok(Out::F64(arg_f64(args, 0)?.asinh())),
        ("env", "atanh" | "gs_atanh") => Ok(Out::F64(arg_f64(args, 0)?.atanh())),
        ("env", "sinh" | "gs_sinh") => Ok(Out::F64(arg_f64(args, 0)?.sinh())),
        ("env", "cosh" | "gs_cosh") => Ok(Out::F64(arg_f64(args, 0)?.cosh())),
        ("env", "tanh" | "gs_tanh") => Ok(Out::F64(arg_f64(args, 0)?.tanh())),
        ("env", "exp2" | "gs_exp2") => Ok(Out::F64(arg_f64(args, 0)?.exp2())),
        ("env", "gs_sin") => Ok(Out::F64(arg_f64(args, 0)?.sin())),
        ("env", "gs_cos") => Ok(Out::F64(arg_f64(args, 0)?.cos())),
        ("env", "gs_tan") => Ok(Out::F64(arg_f64(args, 0)?.tan())),
        ("env", "gs_asin") => Ok(Out::F64(arg_f64(args, 0)?.asin())),
        ("env", "gs_acos") => Ok(Out::F64(arg_f64(args, 0)?.acos())),
        ("env", "gs_atan") => Ok(Out::F64(arg_f64(args, 0)?.atan())),
        ("env", "gs_atan2") => Ok(Out::F64(arg_f64(args, 0)?.atan2(arg_f64(args, 1)?))),
        ("env", "gs_exp") => Ok(Out::F64(arg_f64(args, 0)?.exp())),
        ("env", "gs_log") => Ok(Out::F64(arg_f64(args, 0)?.ln())),
        ("env", "gs_log2") => Ok(Out::F64(arg_f64(args, 0)?.log2())),
        ("env", "gs_log10") => Ok(Out::F64(arg_f64(args, 0)?.log10())),
        ("env", "gs_pow") => Ok(Out::F64(arg_f64(args, 0)?.powf(arg_f64(args, 1)?))),
        ("env", "gs_hypot") => Ok(Out::F64(arg_f64(args, 0)?.hypot(arg_f64(args, 1)?))),
        ("env", "gs_cbrt") => Ok(Out::F64(arg_f64(args, 0)?.cbrt())),
        ("env", "gs_expm1") => Ok(Out::F64(arg_f64(args, 0)?.exp_m1())),
        ("env", "gs_log1p") => Ok(Out::F64(arg_f64(args, 0)?.ln_1p())),
        ("env", "gs_fmod") => Ok(Out::F64(arg_f64(args, 0)? % arg_f64(args, 1)?)),

        // --- Standard Goose OS externs ---
        ("env", "gs_os_write_stdout") => {
            let mem = mem_of(state)?;
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let data = caller.store().read_memory(mem, ptr, len)?;
            let _ = io::stdout().write_all(&data);
            Ok(Out::Void)
        }
        ("env", "gs_os_write_stderr") => {
            let mem = mem_of(state)?;
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let data = caller.store().read_memory(mem, ptr, len)?;
            let _ = io::stderr().write_all(&data);
            Ok(Out::Void)
        }
        ("env", "gs_os_flush_stdout" | "bench_sink" | "emscripten_notify_memory_growth") => {
            let _ = io::stdout().flush();
            Ok(Out::Void)
        }
        ("env", "gs_os_arg_count") => Ok(Out::Int(state.lock().unwrap().args.len() as i64)),
        ("env", "gs_os_arg") => {
            let idx = arg_i64(args, 0)? as usize;
            let header = arg_u64(args, 1)?;
            let data = state
                .lock()
                .unwrap()
                .args
                .get(idx)
                .cloned()
                .unwrap_or_default();
            reserve_and_append(caller, state, header, &data, wide)?;
            Ok(Out::Void)
        }
        ("env", "gs_os_read_file") => {
            let mem = mem_of(state)?;
            let is_wide = args.len() > 2;
            let (ptr, len) = read_slice_arg(args, 0, is_wide)?;
            let header = arg_u64(args, if is_wide { 2 } else { 1 })?;
            let path_bytes = caller.store().read_memory(mem, ptr, len)?;
            match fs::read(path_from_bytes(&path_bytes)) {
                Ok(data) => {
                    reserve_and_append(caller, state, header, &data, is_wide)?;
                    Ok(Out::Int(1))
                }
                Err(_) => Ok(Out::Int(0)),
            }
        }
        ("env", "gs_os_write_file" | "gs_os_append_file") => {
            let mem = mem_of(state)?;
            let is_wide = args.len() > 2;
            let (p_ptr, p_len) = read_slice_arg(args, 0, is_wide)?;
            let (d_ptr, d_len) = read_slice_arg(args, if is_wide { 2 } else { 1 }, is_wide)?;
            let path_bytes = caller.store().read_memory(mem, p_ptr, p_len)?;
            let data = caller.store().read_memory(mem, d_ptr, d_len)?;
            let mut opts = OpenOptions::new();
            opts.write(true).create(true);
            if name == "gs_os_append_file" {
                opts.append(true);
            } else {
                opts.truncate(true);
            }
            let ok = opts
                .open(path_from_bytes(&path_bytes))
                .and_then(|mut f| f.write_all(&data))
                .is_ok();
            Ok(Out::Int(if ok { 1 } else { 0 }))
        }
        ("env", "gs_os_file_exists") => {
            let mem = mem_of(state)?;
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let path = path_from_bytes(&caller.store().read_memory(mem, ptr, len)?);
            Ok(Out::Int(if path.is_file() { 1 } else { 0 }))
        }
        ("env", "gs_os_is_dir") => {
            let mem = mem_of(state)?;
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let path = path_from_bytes(&caller.store().read_memory(mem, ptr, len)?);
            Ok(Out::Int(if path.is_dir() { 1 } else { 0 }))
        }
        ("env", "gs_os_getenv") => {
            let mem = mem_of(state)?;
            let is_wide = args.len() > 2;
            let (ptr, len) = read_slice_arg(args, 0, is_wide)?;
            let header = arg_u64(args, if is_wide { 2 } else { 1 })?;
            let key = caller.store().read_memory(mem, ptr, len)?;
            match std::env::var_os(OsStr::from_bytes(&key)) {
                Some(val) => {
                    reserve_and_append(caller, state, header, val.as_bytes(), is_wide)?;
                    Ok(Out::Int(1))
                }
                None => Ok(Out::Int(0)),
            }
        }
        ("env", "gs_os_resource_dir") => Ok(Out::Int(0)),
        ("env", "gs_os_clock_ns" | "bench_clock" | "blot_clock_ns" | "blot_thread_cpu_ns") => {
            let elapsed = state.lock().unwrap().start_instant.elapsed().as_nanos() as i64;
            Ok(Out::Int(elapsed))
        }
        ("env", "gs_os_time_ns") => {
            let ns = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos() as i64;
            Ok(Out::Int(ns))
        }
        ("env", "gs_os_sleep_ms" | "blot_sleep_ms") => {
            let ms = arg_u64(args, 0)?;
            std::thread::sleep(Duration::from_millis(ms));
            Ok(Out::Void)
        }
        ("env", "gs_os_random_u64" | "blot_random_u64") => {
            let mut buf = [0u8; 8];
            if let Ok(mut f) = File::open("/dev/urandom") {
                if f.read_exact(&mut buf).is_ok() {
                    return Ok(Out::Int(u64::from_le_bytes(buf) as i64));
                }
            }
            let mix = state.lock().unwrap().start_instant.elapsed().as_nanos() as u64
                ^ (u64::from(std::process::id()) << 32)
                ^ state.lock().unwrap().next_owner.fetch_add(1, Ordering::Relaxed);
            Ok(Out::Int(mix as i64))
        }

        // --- Blot2 host imports (env.blot_*) ---
        ("env", "blot_owner_id") => {
            let id = state
                .lock()
                .unwrap()
                .next_owner
                .fetch_add(1, Ordering::Relaxed);
            Ok(Out::Int(id as i64))
        }
        ("env", "blot_f32_bits") => Ok(Out::Int(i64::from(arg_f32(args, 0)?.to_bits() as i32))),
        ("env", "blot_f32_from_bits") => {
            Ok(Out::F32(f32::from_bits(arg_u64(args, 0)? as u32)))
        }
        ("env", "blot_f64_bits") => Ok(Out::Int(arg_f64(args, 0)?.to_bits() as i64)),
        ("env", "blot_f64_from_bits") => Ok(Out::F64(f64::from_bits(arg_u64(args, 0)?))),
        ("env", "blot_i32_bits" | "blot_i32_from_bits") => Ok(Out::Int(arg_i64(args, 0)?)),
        ("env", "blot_f32_mul_add") => Ok(Out::F32(
            arg_f32(args, 0)?.mul_add(arg_f32(args, 1)?, arg_f32(args, 2)?),
        )),
        ("env", "blot_platform_is_linux") => Ok(Out::Int(if cfg!(target_os = "linux") { 1 } else { 0 })),
        ("env", "blot_process_id") => Ok(Out::Int(i64::from(std::process::id()))),
        ("env", "blot_thread_id") => Ok(Out::Int(i64::from(std::process::id()))),
        ("env", "blot_peak_rss_kib") => {
            let kib = fs::read_to_string("/proc/self/status")
                .ok()
                .and_then(|s| {
                    s.lines().find_map(|line| {
                        let rest = line.strip_prefix("VmHWM:")?;
                        rest.split_whitespace().next()?.parse::<i64>().ok()
                    })
                })
                .unwrap_or(0);
            Ok(Out::Int(kib))
        }
        ("env", "blot_debug_write") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let count = arg_u64(args, 1)? as usize;
            let data = caller.store().read_memory(mem, ptr, count)?;
            let _ = io::stderr().write_all(&data);
            Ok(Out::Void)
        }
        ("env", "blot_atomic_load") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let bytes = caller.store().read_memory(mem, ptr, 8)?;
            Ok(Out::Int(u64::from_le_bytes(bytes.try_into().unwrap()) as i64))
        }
        ("env", "blot_atomic_store") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let next = arg_u64(args, 1)?;
            caller.store().write_memory(mem, ptr, &next.to_le_bytes())?;
            Ok(Out::Void)
        }
        ("env", "blot_atomic_add") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let amount = arg_u64(args, 1)?;
            let bytes = caller.store().read_memory(mem, ptr, 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            caller
                .store()
                .write_memory(mem, ptr, &before.wrapping_add(amount).to_le_bytes())?;
            Ok(Out::Int(before as i64))
        }
        ("env", "blot_atomic_sub") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let amount = arg_u64(args, 1)?;
            let bytes = caller.store().read_memory(mem, ptr, 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            caller
                .store()
                .write_memory(mem, ptr, &before.wrapping_sub(amount).to_le_bytes())?;
            Ok(Out::Int(before as i64))
        }
        ("env", "blot_atomic_max") => {
            let mem = mem_of(state)?;
            let ptr = arg_u64(args, 0)?;
            let candidate = arg_u64(args, 1)?;
            let bytes = caller.store().read_memory(mem, ptr, 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            if candidate > before {
                caller
                    .store()
                    .write_memory(mem, ptr, &candidate.to_le_bytes())?;
            }
            Ok(Out::Int(before as i64))
        }
        ("env", "blot_argument_count") => Ok(Out::Int(state.lock().unwrap().args.len() as i64)),
        ("env", "blot_argument_size") => {
            let idx = arg_i64(args, 0)?;
            let guard = state.lock().unwrap();
            if idx < 0 || (idx as usize) >= guard.args.len() {
                return Ok(Out::Int(-22)); // -EINVAL
            }
            Ok(Out::Int(guard.args[idx as usize].len() as i64))
        }
        ("env", "blot_argument_copy") => {
            let mem = mem_of(state)?;
            let idx = arg_i64(args, 0)?;
            let out = arg_u64(args, 1)?;
            let cap = arg_u64(args, 2)? as usize;
            let bytes = {
                let guard = state.lock().unwrap();
                if idx < 0 || (idx as usize) >= guard.args.len() {
                    return Ok(Out::Int(-22)); // -EINVAL
                }
                guard.args[idx as usize].clone()
            };
            if bytes.len() > cap {
                return Ok(Out::Int(-36)); // -ENAMETOOLONG
            }
            caller.store().write_memory(mem, out, &bytes)?;
            Ok(Out::Int(bytes.len() as i64))
        }
        ("env", "blot_environment_size") => {
            let mem = mem_of(state)?;
            let key = read_cstr(caller, mem, arg_u64(args, 0)?)?;
            match std::env::var_os(OsStr::from_bytes(&key)) {
                Some(val) => Ok(Out::Int(val.as_bytes().len() as i64)),
                None => Ok(Out::Int(-2)), // -ENOENT
            }
        }
        ("env", "blot_environment_copy") => {
            let mem = mem_of(state)?;
            let key = read_cstr(caller, mem, arg_u64(args, 0)?)?;
            let out = arg_u64(args, 1)?;
            let cap = arg_u64(args, 2)? as usize;
            match std::env::var_os(OsStr::from_bytes(&key)) {
                Some(val) => {
                    let bytes = val.as_bytes();
                    if bytes.len() > cap {
                        return Ok(Out::Int(-36)); // -ENAMETOOLONG
                    }
                    caller.store().write_memory(mem, out, bytes)?;
                    Ok(Out::Int(bytes.len() as i64))
                }
                None => Ok(Out::Int(-2)), // -ENOENT
            }
        }
        ("env", "blot_open_read") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            let mut guard = state.lock().unwrap();
            match File::open(&path) {
                Ok(f) => Ok(Out::Int(i64::from(guard.alloc_fd(f)))),
                Err(e) => Ok(Out::Int(i64::from(guard.set_errno(&e)))),
            }
        }
        ("env", "blot_open_regular") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            let maximum = arg_u64(args, 1)?;
            let mut guard = state.lock().unwrap();
            match File::open(&path) {
                Ok(f) => match f.metadata() {
                    Ok(meta) if meta.is_file() && meta.len() <= maximum => {
                        Ok(Out::Int(i64::from(guard.alloc_fd(f))))
                    }
                    _ => Ok(Out::Int(-22)), // -EINVAL
                },
                Err(e) => Ok(Out::Int(i64::from(guard.set_errno(&e)))),
            }
        }
        ("env", "blot_open_write") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            let exclusive = arg_i64(args, 1)? != 0;
            let mut opts = OpenOptions::new();
            opts.write(true);
            if exclusive {
                opts.create_new(true);
            } else {
                opts.create(true).truncate(true);
            }
            let mut guard = state.lock().unwrap();
            match opts.open(&path) {
                Ok(f) => Ok(Out::Int(i64::from(guard.alloc_fd(f)))),
                Err(e) => Ok(Out::Int(i64::from(guard.set_errno(&e)))),
            }
        }
        ("env", "blot_read") => {
            let mem = mem_of(state)?;
            let fd = arg_i64(args, 0)? as i32;
            let out = arg_u64(args, 1)?;
            let count = arg_u64(args, 2)? as usize;
            let mut buf = vec![0u8; count];
            let res = if fd == 0 {
                io::stdin().read(&mut buf)
            } else {
                let mut guard = state.lock().unwrap();
                match guard.files.get_mut(&fd) {
                    Some(f) => f.read(&mut buf),
                    None => return Ok(Out::Int(-9)), // -EBADF
                }
            };
            match res {
                Ok(n) => {
                    caller.store().write_memory(mem, out, &buf[..n])?;
                    Ok(Out::Int(n as i64))
                }
                Err(e) => Ok(Out::Int(i64::from(state.lock().unwrap().set_errno(&e)))),
            }
        }
        ("env", "blot_write") => {
            let mem = mem_of(state)?;
            let fd = arg_i64(args, 0)? as i32;
            let ptr = arg_u64(args, 1)?;
            let count = arg_u64(args, 2)? as usize;
            let data = caller.store().read_memory(mem, ptr, count)?;
            let res = if fd == 1 {
                io::stdout().write(&data)
            } else if fd == 2 {
                io::stderr().write(&data)
            } else {
                let mut guard = state.lock().unwrap();
                match guard.files.get_mut(&fd) {
                    Some(f) => f.write(&data),
                    None => return Ok(Out::Int(-9)), // -EBADF
                }
            };
            match res {
                Ok(n) => Ok(Out::Int(n as i64)),
                Err(e) => Ok(Out::Int(i64::from(state.lock().unwrap().set_errno(&e)))),
            }
        }
        ("env", "blot_pwrite") => {
            let mem = mem_of(state)?;
            let fd = arg_i64(args, 0)? as i32;
            let ptr = arg_u64(args, 1)?;
            let count = arg_u64(args, 2)? as usize;
            let offset = arg_u64(args, 3)?;
            let data = caller.store().read_memory(mem, ptr, count)?;
            let guard = state.lock().unwrap();
            let Some(f) = guard.files.get(&fd) else {
                return Ok(Out::Int(-9));
            };
            match f.write_at(&data, offset) {
                Ok(n) => Ok(Out::Int(n as i64)),
                Err(e) => Ok(Out::Int(i64::from(guard.set_errno(&e)))),
            }
        }
        ("env", "blot_close") => {
            let fd = arg_i64(args, 0)? as i32;
            if fd <= 2 {
                return Ok(Out::Int(0));
            }
            let mut guard = state.lock().unwrap();
            if guard.files.remove(&fd).is_some() {
                Ok(Out::Int(0))
            } else {
                Ok(Out::Int(-9))
            }
        }
        ("env", "blot_sync") => {
            let fd = arg_i64(args, 0)? as i32;
            let guard = state.lock().unwrap();
            let Some(f) = guard.files.get(&fd) else {
                return Ok(Out::Int(-9));
            };
            match f.sync_all() {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(guard.set_errno(&e)))),
            }
        }
        ("env", "blot_file_size") => {
            let fd = arg_i64(args, 0)? as i32;
            let mut guard = state.lock().unwrap();
            let Some(f) = guard.files.get_mut(&fd) else {
                return Ok(Out::Int(-9));
            };
            match f.metadata() {
                Ok(m) => Ok(Out::Int(m.len() as i64)),
                Err(_) => match f.seek(SeekFrom::End(0)) {
                    Ok(sz) => Ok(Out::Int(sz as i64)),
                    Err(e) => Ok(Out::Int(i64::from(guard.set_errno(&e)))),
                },
            }
        }
        ("env", "blot_truncate") => {
            let fd = arg_i64(args, 0)? as i32;
            let len = arg_u64(args, 1)?;
            let guard = state.lock().unwrap();
            let Some(f) = guard.files.get(&fd) else {
                return Ok(Out::Int(-9));
            };
            match f.set_len(len) {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(guard.set_errno(&e)))),
            }
        }
        ("env", "blot_rename") => {
            let mem = mem_of(state)?;
            let before = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            let after = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 1)?)?);
            match fs::rename(&before, &after) {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(state.lock().unwrap().set_errno(&e)))),
            }
        }
        ("env", "blot_remove") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            match fs::remove_file(&path) {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(state.lock().unwrap().set_errno(&e)))),
            }
        }
        ("env", "blot_mkdir") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            match fs::create_dir(&path) {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(state.lock().unwrap().set_errno(&e)))),
            }
        }
        ("env", "blot_real_path") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            let out = arg_u64(args, 1)?;
            let cap = arg_u64(args, 2)? as usize;
            match fs::canonicalize(&path) {
                Ok(resolved) => {
                    let bytes = resolved.into_os_string().into_vec();
                    if bytes.len() < cap {
                        let mut nul_bytes = bytes.clone();
                        nul_bytes.push(0);
                        caller.store().write_memory(mem, out, &nul_bytes)?;
                    }
                    Ok(Out::Int(bytes.len() as i64))
                }
                Err(e) => Ok(Out::Int(i64::from(state.lock().unwrap().set_errno(&e)))),
            }
        }
        ("env", "blot_path_kind") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            match fs::metadata(&path) {
                Ok(m) if m.is_file() => Ok(Out::Int(1)),
                Ok(m) if m.is_dir() => Ok(Out::Int(2)),
                Ok(_) => Ok(Out::Int(-1)),
                Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(Out::Int(0)),
                Err(e) => {
                    let _ = state.lock().unwrap().set_errno(&e);
                    Ok(Out::Int(-1))
                }
            }
        }
        ("env", "blot_directory_open") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            let read_dir = match fs::read_dir(&path) {
                Ok(rd) => rd,
                Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Out::Int(0)),
                Err(e) => {
                    let _ = state.lock().unwrap().set_errno(&e);
                    return Ok(Out::Int(-1));
                }
            };
            let mut entries = Vec::new();
            for item in read_dir {
                let Ok(entry) = item else { continue };
                if let Ok(meta) = fs::symlink_metadata(entry.path()) {
                    if meta.is_file() {
                        entries.push(entry.file_name().into_vec());
                    }
                }
            }
            let mut guard = state.lock().unwrap();
            let handle = guard.next_dir;
            guard.next_dir += 1;
            guard.dirs.insert(handle, DirCursor { entries, index: 0 });
            Ok(Out::Int(handle))
        }
        ("env", "blot_directory_next") => {
            let mem = mem_of(state)?;
            let handle = arg_i64(args, 0)?;
            let out = arg_u64(args, 1)?;
            let cap = arg_u64(args, 2)? as usize;
            let entry = {
                let mut guard = state.lock().unwrap();
                let Some(cursor) = guard.dirs.get_mut(&handle) else {
                    return Ok(Out::Int(-1));
                };
                if cursor.index >= cursor.entries.len() {
                    return Ok(Out::Int(0));
                }
                let name = cursor.entries[cursor.index].clone();
                if name.len() > cap {
                    return Ok(Out::Int(name.len() as i64));
                }
                cursor.index += 1;
                name
            };
            if !entry.is_empty() {
                caller.store().write_memory(mem, out, &entry)?;
            }
            Ok(Out::Int(entry.len() as i64))
        }
        ("env", "blot_directory_close") => {
            let handle = arg_i64(args, 0)?;
            let mut guard = state.lock().unwrap();
            Ok(Out::Int(if guard.dirs.remove(&handle).is_some() { 0 } else { -1 }))
        }
        ("env", "blot_last_errno") => {
            Ok(Out::Int(i64::from(state.lock().unwrap().last_errno.load(Ordering::Relaxed))))
        }
        ("env", "blot_lock_open") => {
            let mem = mem_of(state)?;
            let path = path_from_bytes(&read_cstr(caller, mem, arg_u64(args, 0)?)?);
            let mut guard = state.lock().unwrap();
            match OpenOptions::new().read(true).write(true).create(true).open(&path) {
                Ok(f) => Ok(Out::Int(i64::from(guard.alloc_fd(f)))),
                Err(e) => Ok(Out::Int(i64::from(guard.set_errno(&e)))),
            }
        }
        ("env", "blot_try_lock" | "blot_unlock") => Ok(Out::Int(0)),
        ("env", "blot_available_workers") => Ok(Out::Int(1)),
        ("env", "blot_runtime_observation") => Ok(Out::Int(0)),
        ("env", "blot_runtime_memory_mark") => Ok(Out::Void),

        // Multi-process / daemon transport stubs (single-process Wasm execution).
        ("env", "blot_fork" | "blot_worker_spawn") => Ok(Out::Int(-38)), // -ENOSYS
        ("env", "blot_persist_open" | "blot_check_reply_open") => Ok(Out::Int(0)),
        ("env", "blot_persist_node" | "blot_persist_edge" | "blot_persist_publish" | "blot_persist_read" | "blot_check_reply_append" | "blot_wait_success") => {
            Ok(Out::Int(0))
        }
        ("env", "blot_persist_claim") => Ok(Out::Int(-95)), // -ENOTSUP
        ("env", "blot_persist_size" | "blot_check_reply_size" | "blot_check_reply_copy" | "blot_worker_descriptor" | "blot_worker_stop" | "blot_detach_session") => {
            Ok(Out::Int(-1))
        }
        ("env", "blot_persist_kill_child" | "blot_persist_fail" | "blot_persist_close" | "blot_check_reply_close" | "blot_worker_detach" | "blot_null_standard_io" | "blot_request_fail_oom" | "blot_request_fail") => {
            Ok(Out::Void)
        }
        ("env", "blot_job_exit") => {
            let code = arg_i64(args, 0)? as i32;
            state.lock().unwrap().exit_code = Some(code);
            Err(exit_err(code))
        }
        ("env", "blot_request_start" | "blot_request_begin" | "blot_request_input_fd" | "blot_request_transport_reply_open" | "blot_request_transport_finish" | "blot_request_transport_run") => {
            Ok(Out::Int(-38))
        }
        ("env", "blot_request_token") => Ok(Out::Int(0)),
        ("env", "system") => Ok(Out::Int(-1)),
        _ => Err(host_err(format!("unsupported wtime host import: {module}.{name}"))),
    }
}

fn parse_args() -> Result<Options, String> {
    let raw: Vec<Vec<u8>> = std::env::args_os()
        .skip(1)
        .map(std::ffi::OsString::into_vec)
        .collect();
    let mut own = raw;
    let mut program_tail = Vec::new();
    if let Some(pos) = own.iter().position(|a| a == b"--") {
        program_tail = own.split_off(pos + 1);
        own.pop();
    }
    let mut module: Option<PathBuf> = None;
    let mut entry: Option<String> = None;
    let mut policy = ExecutionPolicy::Decoded;
    let mut max_instructions: usize = 100_000_000;
    let mut max_memory_mb: u64 = 16_384;
    let mut timing_json: Option<PathBuf> = None;

    let mut i = 0;
    while i < own.len() {
        let arg = String::from_utf8_lossy(&own[i]).into_owned();
        if arg == "-h" || arg == "--help" {
            println!("{USAGE}");
            std::process::exit(0);
        } else if arg == "--entry" {
            i += 1;
            let Some(v) = own.get(i) else {
                return Err("missing value for --entry".into());
            };
            entry = Some(String::from_utf8_lossy(v).into_owned());
        } else if arg == "--execution" {
            i += 1;
            let Some(v) = own.get(i) else {
                return Err("missing value for --execution".into());
            };
            policy = match String::from_utf8_lossy(v).as_ref() {
                "decoded" => ExecutionPolicy::Decoded,
                "compact" => ExecutionPolicy::Compact,
                "register" => ExecutionPolicy::Register,
                other => return Err(format!("unknown --execution tier: {other}")),
            };
        } else if arg == "--max-instructions" {
            i += 1;
            let Some(v) = own.get(i) else {
                return Err("missing value for --max-instructions".into());
            };
            max_instructions = String::from_utf8_lossy(v)
                .parse()
                .map_err(|_| "invalid --max-instructions".to_string())?;
        } else if arg == "--max-memory-mb" {
            i += 1;
            let Some(v) = own.get(i) else {
                return Err("missing value for --max-memory-mb".into());
            };
            max_memory_mb = String::from_utf8_lossy(v)
                .parse()
                .map_err(|_| "invalid --max-memory-mb".to_string())?;
        } else if arg == "--timing-json" {
            i += 1;
            let Some(v) = own.get(i) else {
                return Err("missing value for --timing-json".into());
            };
            timing_json = Some(path_from_bytes(v));
        } else if arg.starts_with('-') {
            return Err(format!("unknown option: {arg}"));
        } else if module.is_none() {
            module = Some(path_from_bytes(&own[i]));
        } else {
            return Err(format!("unexpected positional argument: {arg}"));
        }
        i += 1;
    }

    let module = module.ok_or_else(|| "missing module.wasm argument".to_string())?;
    let mut program_args = Vec::with_capacity(1 + program_tail.len());
    program_args.push(module.as_os_str().as_bytes().to_vec());
    program_args.extend(program_tail);
    Ok(Options {
        module,
        entry,
        policy,
        max_instructions,
        max_memory_mb,
        timing_json,
        program_args,
    })
}

fn run_module(opts: &Options) -> Result<i32, String> {
    let bytes = fs::read(&opts.module)
        .map_err(|e| format!("failed to read {}: {e}", opts.module.display()))?;
    let max_bytes = opts.max_memory_mb.saturating_mul(1024 * 1024);
    let mut limits = ResourceLimits::default();
    limits.max_module_bytes = bytes.len().saturating_add(1024).max(256 * 1024 * 1024);
    limits.max_types = 500_000;
    limits.max_functions = 500_000;
    limits.max_globals = 500_000;
    limits.max_locals = 200_000;
    limits.max_total_locals = 10_000_000;
    limits.max_stack_height = 500_000;
    limits.max_call_depth = 50_000;
    limits.max_memory_pages = max_bytes / 65_536;
    limits.max_memory_bytes = max_bytes;
    limits.max_store_memory_bytes = max_bytes;
    limits.max_store_objects = 2_000_000;
    limits.max_elements = 500_000;
    limits.max_data_segments = 500_000;
    limits.max_instructions = opts.max_instructions;

    let config = Config {
        features: FeatureSet::all_phase3_core(),
        limits,
    };
    let engine = Engine::with_execution_policy(config, opts.policy)
        .map_err(|e| format!("wtime engine error: {e}"))?;

    let t0 = Instant::now();
    let module = engine
        .compile(&bytes)
        .map_err(|e| format!("wtime compile error: {e}"))?;
    let compile_ns = t0.elapsed().as_nanos() as u64;

    let state = Arc::new(Mutex::new(HostState::new(opts.program_args.clone())));
    let mut store = Store::new(&engine);
    let mut linker = Linker::new(&engine);

    for (imp_mod, imp_name, _ty_idx, func_ty) in module.function_imports() {
        let mod_str = imp_mod.to_string();
        let name_str = imp_name.to_string();
        let params = func_ty.params.clone();
        let results = func_ty.results.clone();
        let st = Arc::clone(&state);
        let f = store
            .create_host_func_with_caller(func_ty.clone(), move |caller, args| {
                let out = dispatch_import(&mod_str, &name_str, caller, args, &st, &params)?;
                box_result(&results, out)
            })
            .map_err(|e| format!("failed to create host import {imp_mod}.{imp_name}: {e}"))?;
        linker
            .define(imp_mod, imp_name, External::Func(f))
            .map_err(|e| format!("failed to define {imp_mod}.{imp_name}: {e}"))?;
    }

    let t1 = Instant::now();
    let instance = linker
        .instantiate(&mut store, &module)
        .map_err(|e| format!("wtime instantiate error: {e}"))?;
    let instantiate_ns = t1.elapsed().as_nanos() as u64;

    if let Ok(External::Memory(mem)) = instance.export(&store, "memory") {
        state.lock().unwrap().memory = Some(mem);
    }
    if let Ok(External::Func(res_fn)) = instance.export(&store, "goose.reserve") {
        state.lock().unwrap().reserve_fn = Some(res_fn);
    }

    let t2 = Instant::now();
    let mut exit_code: i32 = 0;

    let invoke_export = |store: &mut Store, export_name: &str| -> Result<Option<i32>, String> {
        let External::Func(func) = instance
            .export(store, export_name)
            .map_err(|e| format!("missing export {export_name}: {e}"))?
        else {
            return Err(format!("export {export_name} is not a function"));
        };
        match store.invoke(func, &[]) {
            Ok(RunOutcome::Returned(vals)) => {
                if let Some(Value::I32(code)) = vals.first() {
                    Ok(Some(*code))
                } else {
                    Ok(None)
                }
            }
            Ok(other) => Err(format!("unexpected outcome from {export_name}: {other:?}")),
            Err(err) => {
                if let Some(code) = state.lock().unwrap().exit_code {
                    return Ok(Some(code));
                }
                if let Some(msg) = state.lock().unwrap().abort_message.clone() {
                    let _ = writeln!(io::stderr(), "{msg}");
                    return Ok(Some(1));
                }
                Err(format!("wtime runtime error in {export_name}: {err}"))
            }
        }
    };

    if instance.export(&store, "_start").is_ok() {
        if let Some(code) = invoke_export(&mut store, "_start")? {
            exit_code = code;
        }
    }
    if state.lock().unwrap().exit_code.is_none()
        && state.lock().unwrap().abort_message.is_none()
        && let Some(entry_name) = &opts.entry
    {
        if let Some(code) = invoke_export(&mut store, entry_name)? {
            exit_code = code;
        }
    }
    let run_ns = t2.elapsed().as_nanos() as u64;

    let _ = io::stdout().flush();
    let _ = io::stderr().flush();

    if let Some(path) = &opts.timing_json {
        let json = format!(
            "{{\"engine\":\"wtime\",\"compile_ns\":{compile_ns},\"instantiate_ns\":{instantiate_ns},\"run_ns\":{run_ns}}}\n"
        );
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() && parent != Path::new("") {
                let _ = fs::create_dir_all(parent);
            }
        }
        fs::write(path, json).map_err(|e| format!("failed to write {}: {e}", path.display()))?;
    }
    Ok(exit_code)
}

fn main() -> ExitCode {
    let opts = match parse_args() {
        Ok(o) => o,
        Err(msg) => {
            eprintln!("{USAGE}\ngoose-wtime: error: {msg}");
            return ExitCode::from(2);
        }
    };
    let result = std::thread::Builder::new()
        .stack_size(64 * 1024 * 1024)
        .spawn(move || run_module(&opts))
        .expect("spawn wtime host thread")
        .join()
        .unwrap_or_else(|_| Err("wtime host thread panicked".into()));
    match result {
        Ok(code) => ExitCode::from((code & 0xff) as u8),
        Err(msg) => {
            eprintln!("goose-wtime: {msg}");
            ExitCode::from(1)
        }
    }
}
