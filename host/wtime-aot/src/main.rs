//! Direct Goose Wasm32/Wasm64 and Blot2 Wasm64 runner backed by `wtime-aot-host` (`StoreCdylib`).
//!
//! Compiles any Direct Goose `.wasm` module (including 84-import Blot2 and 24-import `selfhost`)
//! directly to native Linux x86-64 machine code using `wtime-aot --backend x64` with zero Clang,
//! zero LLVM, and zero Wasmtime dependencies, while bridging all Goose/OS/math/Blot2 host imports
//! in Rust.

#[allow(clippy::needless_range_loop)]
#[path = "../../wtime/src/float.rs"]
mod float;

use std::collections::{HashMap, HashSet};
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::FileExt;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use wtime_aot_host::{
    Caller, Config, Engine, Error, Extern, ExternType, Func, Linker, Memory, Module, OptLevel,
    Store, StoreLimits, StoreLimitsBuilder, Val, ValType,
};

const USAGE: &str = "\
usage: goose-wtime-aot module.wasm [--entry NAME] [--fast] [--cache PATH]
                       [--timing-json PATH] [-- program arguments...]";

struct Options {
    module: PathBuf,
    entry: Option<String>,
    fast: bool,
    cache: Option<PathBuf>,
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
    resource_dir: Option<Vec<u8>>,
    start_instant: Instant,
    next_owner: AtomicU64,
    next_fd: i32,
    files: HashMap<i32, File>,
    next_dir: i64,
    dirs: HashMap<i64, DirCursor>,
    last_errno: AtomicI32,
    exit_code: Option<i32>,
    abort_message: Option<String>,
    limits: StoreLimits,
}

impl HostState {
    fn new(args: Vec<Vec<u8>>, resource_dir: Option<Vec<u8>>) -> Self {
        Self {
            memory: None,
            reserve_fn: None,
            args,
            resource_dir,
            start_instant: Instant::now(),
            next_owner: AtomicU64::new(1),
            next_fd: 3,
            files: HashMap::new(),
            next_dir: 1,
            dirs: HashMap::new(),
            last_errno: AtomicI32::new(0),
            exit_code: None,
            abort_message: None,
            limits: StoreLimitsBuilder::new().memory_size(16usize << 30).build(),
        }
    }

    fn alloc_fd(&mut self, file: File) -> i32 {
        let fd = self.next_fd;
        self.next_fd = self.next_fd.saturating_add(1);
        self.files.insert(fd, file);
        fd
    }

    fn set_errno(&self, err: &io::Error) -> i32 {
        let code = err.raw_os_error().unwrap_or(22);
        self.last_errno.store(code, Ordering::Relaxed);
        -code
    }
}

fn host_err(msg: impl Into<String>) -> Error {
    Error::msg(msg.into())
}

fn arg_i64(vals: &[Val], idx: usize) -> Result<i64, Error> {
    match vals.get(idx) {
        Some(Val::I32(v)) => Ok(i64::from(*v)),
        Some(Val::I64(v)) => Ok(*v),
        _ => Err(host_err("expected integer argument")),
    }
}

fn arg_u64(vals: &[Val], idx: usize) -> Result<u64, Error> {
    match vals.get(idx) {
        Some(Val::I32(v)) => Ok(u64::from(*v as u32)),
        Some(Val::I64(v)) => Ok(*v as u64),
        _ => Err(host_err("expected unsigned integer argument")),
    }
}

fn arg_f64(vals: &[Val], idx: usize) -> Result<f64, Error> {
    match vals.get(idx) {
        Some(Val::F32(bits)) => Ok(f64::from(f32::from_bits(*bits))),
        Some(Val::F64(bits)) => Ok(f64::from_bits(*bits)),
        _ => Err(host_err("expected float argument")),
    }
}

fn arg_f32(vals: &[Val], idx: usize) -> Result<f32, Error> {
    match vals.get(idx) {
        Some(Val::F32(bits)) => Ok(f32::from_bits(*bits)),
        Some(Val::F64(bits)) => Ok(f64::from_bits(*bits) as f32),
        _ => Err(host_err("expected f32 argument")),
    }
}

fn read_slice_arg(vals: &[Val], idx: usize, wide: bool) -> Result<(u64, usize), Error> {
    if wide {
        let ptr = arg_u64(vals, idx)?;
        let len = arg_u64(vals, idx + 1)? as usize;
        Ok((ptr, len))
    } else {
        let packed = arg_u64(vals, idx)?;
        Ok((packed & 0xffff_ffff, (packed >> 32) as usize))
    }
}

fn get_mem(caller: &mut Caller<'_, HostState>) -> Result<Memory, Error> {
    if let Some(m) = caller.data().memory {
        return Ok(m);
    }
    match caller.get_export("memory") {
        Some(Extern::Memory(m)) => {
            caller.data_mut().memory = Some(m);
            Ok(m)
        }
        _ => Err(host_err("module does not export memory")),
    }
}

fn read_mem(caller: &mut Caller<'_, HostState>, ptr: u64, len: usize) -> Result<Vec<u8>, Error> {
    let mem = get_mem(caller)?;
    let mut buf = vec![0u8; len];
    if len > 0 {
        mem.read(&*caller, ptr as usize, &mut buf)?;
    }
    Ok(buf)
}

fn write_mem(caller: &mut Caller<'_, HostState>, ptr: u64, data: &[u8]) -> Result<(), Error> {
    if data.is_empty() {
        return Ok(());
    }
    let mem = get_mem(caller)?;
    mem.write(&mut *caller, ptr as usize, data)
}

fn read_cstr(caller: &mut Caller<'_, HostState>, ptr: u64) -> Result<Vec<u8>, Error> {
    let mem = get_mem(caller)?;
    let data = mem.data(&*caller);
    let start = usize::try_from(ptr).map_err(|_| host_err("pointer overflow"))?;
    if start >= data.len() {
        return Err(host_err("C string pointer out of bounds"));
    }
    let slice = &data[start..];
    let limit = slice.len().min(65536);
    if let Some(pos) = slice[..limit].iter().position(|&b| b == 0) {
        return Ok(slice[..pos].to_vec());
    }
    Err(host_err("C string exceeds 64 KiB or unterminated"))
}

fn path_from_bytes(bytes: &[u8]) -> PathBuf {
    PathBuf::from(OsStr::from_bytes(bytes))
}

fn pure_frexp(x: f64) -> (f64, i32) {
    if x == 0.0 || !x.is_finite() {
        return (x, 0);
    }
    let mut bits = x.to_bits();
    let mut exp = ((bits >> 52) & 0x7ff) as i32;
    let mut adjust = 0i32;
    if exp == 0 {
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
    caller: &mut Caller<'_, HostState>,
    header: u64,
    bytes: &[u8],
    wide: bool,
) -> Result<(), Error> {
    if bytes.is_empty() {
        return Ok(());
    }
    let reserve = match caller.data().reserve_fn {
        Some(f) => f,
        None => match caller.get_export("goose.reserve") {
            Some(Extern::Func(f)) => {
                caller.data_mut().reserve_fn = Some(f);
                f
            }
            _ => return Err(host_err("module does not export goose.reserve")),
        },
    };
    let args = if wide {
        [Val::I64(header as i64), Val::I64(bytes.len() as i64)]
    } else {
        [Val::I32(header as i32), Val::I32(bytes.len() as i32)]
    };
    let mut results = [Val::I64(0)];
    reserve.call(&mut *caller, &args, &mut results)?;
    let dst = arg_u64(&results, 0)?;
    write_mem(caller, dst, bytes)
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
    caller: &mut Caller<'_, HostState>,
    args: &[Val],
    params: &[ValType],
) -> Result<Out, Error> {
    let header_wide = matches!(params.last(), Some(ValType::I64));
    match (module, name) {
        // --- goose.* core host ---
        ("goose", "write") => {
            let ptr = arg_u64(args, 0)?;
            let len = arg_u64(args, 1)? as usize;
            let data = read_mem(caller, ptr, len)?;
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
            let _ = io::stdout().write_all(float::f64_text(arg_f64(args, 0)?).as_bytes());
            Ok(Out::Void)
        }
        ("goose", "print_f32") => {
            let _ = io::stdout().write_all(float::f32_text(arg_f32(args, 0)?).as_bytes());
            Ok(Out::Void)
        }
        ("goose", "print_bool") => {
            let _ = io::stdout().write_all(if arg_i64(args, 0)? != 0 { b"true" } else { b"false" });
            Ok(Out::Void)
        }
        ("goose", "newline") => {
            let _ = io::stdout().write_all(b"\n");
            Ok(Out::Void)
        }
        ("goose", "format_f64") => {
            let ptr = arg_u64(args, 0)?;
            let text = float::f64_text(arg_f64(args, 1)?);
            let bytes = text.as_bytes();
            if bytes.len() > 32 {
                return Err(host_err("formatted float exceeds host buffer"));
            }
            write_mem(caller, ptr, bytes)?;
            Ok(Out::Int(bytes.len() as i64))
        }
        ("goose", "format_f32") => {
            let ptr = arg_u64(args, 0)?;
            let text = float::f32_text(arg_f32(args, 1)?);
            let bytes = text.as_bytes();
            if bytes.len() > 32 {
                return Err(host_err("formatted float exceeds host buffer"));
            }
            write_mem(caller, ptr, bytes)?;
            Ok(Out::Int(bytes.len() as i64))
        }
        ("goose", "abort") => {
            let ptr = arg_u64(args, 0)?;
            let len = arg_u64(args, 1)? as usize;
            let line = arg_i64(args, 2)?;
            let msg = read_mem(caller, ptr, len)?;
            let text = format!("goose runtime error: {} (line {line})", String::from_utf8_lossy(&msg));
            caller.data_mut().abort_message = Some(text.clone());
            Err(host_err(text))
        }
        ("goose", "exit") => {
            let code = arg_i64(args, 0)? as i32;
            caller.data_mut().exit_code = Some(code);
            Err(host_err(format!("exit:{code}")))
        }

        // --- Math imports ---
        ("env", "frexp") => {
            let (mant, exp) = pure_frexp(arg_f64(args, 0)?);
            let ptr = arg_u64(args, 1)?;
            write_mem(caller, ptr, &exp.to_le_bytes())?;
            Ok(Out::F64(mant))
        }
        ("env", "ldexp") => Ok(Out::F64(pure_ldexp(arg_f64(args, 0)?, arg_i64(args, 1)? as i32))),
        ("env", "acosh" | "gs_acosh") => Ok(Out::F64(arg_f64(args, 0)?.acosh())),
        ("env", "asinh" | "gs_asinh") => Ok(Out::F64(arg_f64(args, 0)?.asinh())),
        ("env", "atanh" | "gs_atanh") => Ok(Out::F64(arg_f64(args, 0)?.atanh())),
        ("env", "sinh" | "gs_sinh") => Ok(Out::F64(arg_f64(args, 0)?.sinh())),
        ("env", "gs_sinhf") => Ok(Out::F32(arg_f32(args, 0)?.sinh())),
        ("env", "cosh" | "gs_cosh") => Ok(Out::F64(arg_f64(args, 0)?.cosh())),
        ("env", "gs_coshf") => Ok(Out::F32(arg_f32(args, 0)?.cosh())),
        ("env", "tanh" | "gs_tanh") => Ok(Out::F64(arg_f64(args, 0)?.tanh())),
        ("env", "gs_tanhf") => Ok(Out::F32(arg_f32(args, 0)?.tanh())),
        ("env", "exp2" | "gs_exp2") => Ok(Out::F64(arg_f64(args, 0)?.exp2())),
        ("env", "gs_exp2f") => Ok(Out::F32(arg_f32(args, 0)?.exp2())),
        ("env", "sin" | "gs_sin") => Ok(Out::F64(arg_f64(args, 0)?.sin())),
        ("env", "gs_sinf") => Ok(Out::F32(arg_f32(args, 0)?.sin())),
        ("env", "cos" | "gs_cos") => Ok(Out::F64(arg_f64(args, 0)?.cos())),
        ("env", "gs_cosf") => Ok(Out::F32(arg_f32(args, 0)?.cos())),
        ("env", "tan" | "gs_tan") => Ok(Out::F64(arg_f64(args, 0)?.tan())),
        ("env", "gs_tanf") => Ok(Out::F32(arg_f32(args, 0)?.tan())),
        ("env", "asin" | "gs_asin") => Ok(Out::F64(arg_f64(args, 0)?.asin())),
        ("env", "gs_asinf") => Ok(Out::F32(arg_f32(args, 0)?.asin())),
        ("env", "acos" | "gs_acos") => Ok(Out::F64(arg_f64(args, 0)?.acos())),
        ("env", "gs_acosf") => Ok(Out::F32(arg_f32(args, 0)?.acos())),
        ("env", "atan" | "gs_atan") => Ok(Out::F64(arg_f64(args, 0)?.atan())),
        ("env", "gs_atanf") => Ok(Out::F32(arg_f32(args, 0)?.atan())),
        ("env", "atan2" | "gs_atan2") => Ok(Out::F64(arg_f64(args, 0)?.atan2(arg_f64(args, 1)?))),
        ("env", "gs_atan2f") => Ok(Out::F32(arg_f32(args, 0)?.atan2(arg_f32(args, 1)?))),
        ("env", "exp" | "gs_exp") => Ok(Out::F64(arg_f64(args, 0)?.exp())),
        ("env", "gs_expf") => Ok(Out::F32(arg_f32(args, 0)?.exp())),
        ("env", "log" | "gs_log") => Ok(Out::F64(arg_f64(args, 0)?.ln())),
        ("env", "gs_logf") => Ok(Out::F32(arg_f32(args, 0)?.ln())),
        ("env", "log2" | "gs_log2") => Ok(Out::F64(arg_f64(args, 0)?.log2())),
        ("env", "gs_log2f") => Ok(Out::F32(arg_f32(args, 0)?.log2())),
        ("env", "log10" | "gs_log10") => Ok(Out::F64(arg_f64(args, 0)?.log10())),
        ("env", "gs_log10f") => Ok(Out::F32(arg_f32(args, 0)?.log10())),
        ("env", "pow" | "gs_pow") => Ok(Out::F64(arg_f64(args, 0)?.powf(arg_f64(args, 1)?))),
        ("env", "gs_powf") => Ok(Out::F32(arg_f32(args, 0)?.powf(arg_f32(args, 1)?))),
        ("env", "gs_mul_add") => Ok(Out::F64(arg_f64(args, 0)?.mul_add(arg_f64(args, 1)?, arg_f64(args, 2)?))),
        ("env", "gs_mul_addf") => Ok(Out::F32(arg_f32(args, 0)?.mul_add(arg_f32(args, 1)?, arg_f32(args, 2)?))),
        ("env", "round" | "gs_round") => Ok(Out::F64(arg_f64(args, 0)?.round())),
        ("env", "roundf" | "gs_roundf") => Ok(Out::F32(arg_f32(args, 0)?.round())),
        ("env", "hypot" | "gs_hypot") => Ok(Out::F64(arg_f64(args, 0)?.hypot(arg_f64(args, 1)?))),
        ("env", "gs_hypotf") => Ok(Out::F32(arg_f32(args, 0)?.hypot(arg_f32(args, 1)?))),
        ("env", "cbrt" | "gs_cbrt") => Ok(Out::F64(arg_f64(args, 0)?.cbrt())),
        ("env", "gs_cbrtf") => Ok(Out::F32(arg_f32(args, 0)?.cbrt())),
        ("env", "expm1" | "gs_expm1") => Ok(Out::F64(arg_f64(args, 0)?.exp_m1())),
        ("env", "gs_expm1f") => Ok(Out::F32(arg_f32(args, 0)?.exp_m1())),
        ("env", "log1p" | "gs_log1p") => Ok(Out::F64(arg_f64(args, 0)?.ln_1p())),
        ("env", "gs_log1pf") => Ok(Out::F32(arg_f32(args, 0)?.ln_1p())),
        ("env", "fmod" | "gs_fmod") => Ok(Out::F64(arg_f64(args, 0)? % arg_f64(args, 1)?)),
        ("env", "fmodf" | "gs_fmodf") => Ok(Out::F32(arg_f32(args, 0)? % arg_f32(args, 1)?)),
        ("env", "gs_trim_memory") => Ok(Out::Int(0)),

        // --- Standard Goose OS externs ---
        ("env", "gs_os_write_stdout") => {
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let data = read_mem(caller, ptr, len)?;
            let _ = io::stdout().write_all(&data);
            Ok(Out::Void)
        }
        ("env", "gs_os_write_stderr") => {
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let data = read_mem(caller, ptr, len)?;
            let _ = io::stderr().write_all(&data);
            Ok(Out::Void)
        }
        ("env", "gs_os_flush_stdout" | "bench_sink" | "emscripten_notify_memory_growth") => {
            let _ = io::stdout().flush();
            Ok(Out::Void)
        }
        ("env", "gs_os_arg_count") => Ok(Out::Int(caller.data().args.len() as i64)),
        ("env", "gs_os_arg") => {
            let idx = arg_i64(args, 0)? as usize;
            let header = arg_u64(args, 1)?;
            let data = caller.data().args.get(idx).cloned().unwrap_or_default();
            reserve_and_append(caller, header, &data, header_wide)?;
            Ok(Out::Void)
        }
        ("env", "getcwd") => {
            let pointer = arg_u64(args, 0)?;
            let capacity = arg_u64(args, 1)?;
            let Ok(path) = std::env::current_dir() else {
                return Ok(Out::Int(0));
            };
            let mut bytes = path.into_os_string().into_vec();
            bytes.push(0);
            if pointer == 0 || bytes.len() as u64 > capacity {
                return Ok(Out::Int(0));
            }
            write_mem(caller, pointer, &bytes)?;
            Ok(Out::Int(pointer as i64))
        }
        ("env", "gs_os_read_file") => {
            let is_wide = args.len() > 2;
            let (ptr, len) = read_slice_arg(args, 0, is_wide)?;
            let header = arg_u64(args, if is_wide { 2 } else { 1 })?;
            let path_bytes = read_mem(caller, ptr, len)?;
            match fs::read(path_from_bytes(&path_bytes)) {
                Ok(data) => {
                    reserve_and_append(caller, header, &data, header_wide)?;
                    Ok(Out::Int(1))
                }
                Err(_) => Ok(Out::Int(0)),
            }
        }
        ("env", "gs_os_write_file" | "gs_os_append_file") => {
            let is_wide = args.len() > 2;
            let (p_ptr, p_len) = read_slice_arg(args, 0, is_wide)?;
            let (d_ptr, d_len) = read_slice_arg(args, if is_wide { 2 } else { 1 }, is_wide)?;
            let path_bytes = read_mem(caller, p_ptr, p_len)?;
            let data = read_mem(caller, d_ptr, d_len)?;
            let mut opts = OpenOptions::new();
            opts.write(true).create(true);
            if name == "gs_os_append_file" {
                opts.append(true);
            } else {
                opts.truncate(true);
            }
            let ok = opts.open(path_from_bytes(&path_bytes)).and_then(|mut f| f.write_all(&data)).is_ok();
            Ok(Out::Int(i64::from(ok)))
        }
        ("env", "gs_os_write_file_atomic") => {
            let is_wide = args.len() > 2;
            let (p_ptr, p_len) = read_slice_arg(args, 0, is_wide)?;
            let (d_ptr, d_len) = read_slice_arg(args, if is_wide { 2 } else { 1 }, is_wide)?;
            let path_bytes = read_mem(caller, p_ptr, p_len)?;
            let data = read_mem(caller, d_ptr, d_len)?;
            let target = path_from_bytes(&path_bytes);
            let seq = caller.data().next_owner.fetch_add(1, Ordering::Relaxed);
            let mut tmp = target.as_os_str().to_os_string();
            tmp.push(format!(".tmp-{}-{seq}", std::process::id()));
            let tmp_path = PathBuf::from(tmp);
            let ok = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&tmp_path)
                .and_then(|mut f| {
                    f.write_all(&data)?;
                    f.sync_all()
                })
                .and_then(|()| fs::rename(&tmp_path, &target))
                .is_ok();
            if !ok {
                let _ = fs::remove_file(&tmp_path);
            }
            Ok(Out::Int(i64::from(ok)))
        }
        ("env", "gs_os_file_exists") => {
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let path = path_from_bytes(&read_mem(caller, ptr, len)?);
            Ok(Out::Int(i64::from(path.is_file())))
        }
        ("env", "gs_os_remove_file") => {
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let path = path_from_bytes(&read_mem(caller, ptr, len)?);
            Ok(Out::Int(i64::from(fs::remove_file(&path).is_ok())))
        }
        ("env", "gs_os_rename_file") => {
            let is_wide = args.len() > 2;
            let (a_ptr, a_len) = read_slice_arg(args, 0, is_wide)?;
            let (b_ptr, b_len) = read_slice_arg(args, if is_wide { 2 } else { 1 }, is_wide)?;
            let src = path_from_bytes(&read_mem(caller, a_ptr, a_len)?);
            let dst = path_from_bytes(&read_mem(caller, b_ptr, b_len)?);
            Ok(Out::Int(i64::from(fs::rename(&src, &dst).is_ok())))
        }
        ("env", "gs_os_make_dir") => {
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let path = path_from_bytes(&read_mem(caller, ptr, len)?);
            let ok = match fs::create_dir(&path) {
                Ok(()) => true,
                Err(e) if e.kind() == io::ErrorKind::AlreadyExists => path.is_dir(),
                Err(_) => false,
            };
            Ok(Out::Int(i64::from(ok)))
        }
        ("env", "gs_os_is_dir") => {
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let path = path_from_bytes(&read_mem(caller, ptr, len)?);
            Ok(Out::Int(i64::from(path.is_dir())))
        }
        ("env", "gs_os_remove_dir") => {
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            let path = path_from_bytes(&read_mem(caller, ptr, len)?);
            Ok(Out::Int(i64::from(fs::remove_dir(&path).is_ok())))
        }
        ("env", "gs_os_list_dir") => {
            let is_wide = args.len() > 2;
            let (ptr, len) = read_slice_arg(args, 0, is_wide)?;
            let header = arg_u64(args, if is_wide { 2 } else { 1 })?;
            let path = path_from_bytes(&read_mem(caller, ptr, len)?);
            match fs::read_dir(&path) {
                Ok(rd) => {
                    let mut names: Vec<Vec<u8>> = Vec::new();
                    for item in rd {
                        let Ok(entry) = item else { continue };
                        let b = entry.file_name().into_vec();
                        if !b.contains(&b'\n') {
                            names.push(b);
                        }
                    }
                    names.sort();
                    let mut out = Vec::new();
                    for name in names {
                        out.extend_from_slice(&name);
                        out.push(b'\n');
                    }
                    reserve_and_append(caller, header, &out, header_wide)?;
                    Ok(Out::Int(1))
                }
                Err(_) => Ok(Out::Int(0)),
            }
        }
        ("env", "gs_os_read_line") => {
            let header = arg_u64(args, 0)?;
            let mut stdin = io::stdin().lock();
            let mut line = Vec::new();
            let mut byte = [0u8; 1];
            let mut got_any = false;
            loop {
                match stdin.read(&mut byte) {
                    Ok(0) => break,
                    Ok(_) => {
                        got_any = true;
                        if byte[0] == b'\n' {
                            break;
                        }
                        line.push(byte[0]);
                    }
                    Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                    Err(_) => break,
                }
            }
            if !got_any {
                return Ok(Out::Int(0));
            }
            if line.last() == Some(&b'\r') {
                line.pop();
            }
            reserve_and_append(caller, header, &line, header_wide)?;
            Ok(Out::Int(1))
        }
        ("env", "gs_os_read_stdin") => {
            let header = arg_u64(args, 0)?;
            let mut data = Vec::new();
            let _ = io::stdin().lock().read_to_end(&mut data);
            reserve_and_append(caller, header, &data, header_wide)?;
            Ok(Out::Void)
        }
        ("env", "gs_os_read_stdin_max") => {
            let header = arg_u64(args, 0)?;
            let limit = arg_i64(args, 1)?;
            if limit <= 0 {
                return Ok(Out::Int(0));
            }
            let max_bytes = usize::try_from(limit).unwrap_or(usize::MAX);
            let mut data = Vec::new();
            let _ = io::stdin().lock().take(max_bytes as u64).read_to_end(&mut data);
            if data.is_empty() {
                return Ok(Out::Int(0));
            }
            let ctrl_wide = matches!(params.first(), Some(ValType::I64));
            reserve_and_append(caller, header, &data, ctrl_wide)?;
            Ok(Out::Int(1))
        }
        ("env", "gs_os_getenv") => {
            let is_wide = args.len() > 2;
            let (ptr, len) = read_slice_arg(args, 0, is_wide)?;
            let header = arg_u64(args, if is_wide { 2 } else { 1 })?;
            let key = read_mem(caller, ptr, len)?;
            match std::env::var_os(OsStr::from_bytes(&key)) {
                Some(val) => {
                    reserve_and_append(caller, header, val.as_bytes(), header_wide)?;
                    Ok(Out::Int(1))
                }
                None => Ok(Out::Int(0)),
            }
        }
        ("env", "gs_os_resource_dir") => {
            let header = arg_u64(args, 0)?;
            let dir = caller.data().resource_dir.clone();
            if let Some(bytes) = dir {
                reserve_and_append(caller, header, &bytes, header_wide)?;
                Ok(Out::Int(1))
            } else {
                Ok(Out::Int(0))
            }
        }
        ("env", "gs_find_any") => {
            let is_wide = args.len() > 2;
            let (ptr, len) = read_slice_arg(args, 0, is_wide)?;
            let set_ptr = arg_u64(args, if is_wide { 2 } else { 1 })?;
            let data = read_mem(caller, ptr, len)?;
            let table = read_mem(caller, set_ptr, 256)?;
            let found = data.iter().position(|&b| table[usize::from(b)] != 0);
            Ok(Out::Int(found.map_or(-1, |i| i as i64)))
        }
        ("env", "gs_find_pair") => {
            let is_wide = args.len() > 4;
            let (ptr, len) = read_slice_arg(args, 0, is_wide)?;
            let base = if is_wide { 2 } else { 1 };
            let first_ptr = arg_u64(args, base)?;
            let distance = arg_i64(args, base + 1)?;
            let second_ptr = arg_u64(args, base + 2)?;
            if distance < 0 || (distance as usize) >= len {
                return Ok(Out::Int(-1));
            }
            let d = distance as usize;
            let data = read_mem(caller, ptr, len)?;
            let first = read_mem(caller, first_ptr, 256)?;
            let second = read_mem(caller, second_ptr, 256)?;
            let found = (0..data.len() - d)
                .find(|&i| first[usize::from(data[i])] != 0 && second[usize::from(data[i + d])] != 0);
            Ok(Out::Int(found.map_or(-1, |i| i as i64)))
        }
        ("env", "gs_os_clock_ns" | "bench_clock" | "blot_clock_ns" | "blot_thread_cpu_ns") => {
            Ok(Out::Int(caller.data().start_instant.elapsed().as_nanos() as i64))
        }
        ("env", "gs_os_time_ns") => {
            let ns = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos() as i64;
            Ok(Out::Int(ns))
        }
        ("env", "gs_os_sleep_ms" | "blot_sleep_ms") => {
            let ms = arg_i64(args, 0)?;
            if ms > 0 {
                std::thread::sleep(Duration::from_millis(ms as u64));
            }
            Ok(Out::Void)
        }
        ("env", "gs_os_random_u64" | "blot_random_u64") => {
            let mut buf = [0u8; 8];
            if let Ok(mut f) = File::open("/dev/urandom")
                && f.read_exact(&mut buf).is_ok()
            {
                return Ok(Out::Int(u64::from_le_bytes(buf) as i64));
            }
            let mix = caller.data().start_instant.elapsed().as_nanos() as u64
                ^ (u64::from(std::process::id()) << 32)
                ^ caller.data().next_owner.fetch_add(1, Ordering::Relaxed);
            Ok(Out::Int(mix as i64))
        }
        ("env", "gs_os_random_bytes") => {
            let (ptr, len) = read_slice_arg(args, 0, args.len() > 1)?;
            if len > 0 {
                let mut buf = vec![0u8; len];
                let mut filled = false;
                if let Ok(mut f) = File::open("/dev/urandom") {
                    filled = f.read_exact(&mut buf).is_ok();
                }
                if !filled {
                    for chunk in buf.chunks_mut(8) {
                        let mix = caller.data().start_instant.elapsed().as_nanos() as u64
                            ^ (u64::from(std::process::id()) << 32)
                            ^ caller.data().next_owner.fetch_add(1, Ordering::Relaxed);
                        let raw = mix.to_le_bytes();
                        chunk.copy_from_slice(&raw[..chunk.len()]);
                    }
                }
                write_mem(caller, ptr, &buf)?;
            }
            Ok(Out::Int(1))
        }
        ("env", "gs_f64_digits") => {
            let x = arg_f64(args, 0)?;
            let is_wide = args.len() > 3;
            let (ptr, len) = read_slice_arg(args, 1, is_wide)?;
            let point_ptr = arg_u64(args, if is_wide { 3 } else { 2 })?;
            if !x.is_finite() || x == 0.0 {
                return Ok(Out::Int(0));
            }
            let (digits_num, exp) = float::f64_shortest(x.abs());
            let digits_str = digits_num.to_string();
            let trimmed = digits_str.trim_end_matches('0').as_bytes();
            let point = i64::from(exp) + 1;
            let n = trimmed.len().min(len);
            if n > 0 {
                write_mem(caller, ptr, &trimmed[..n])?;
            }
            write_mem(caller, point_ptr, &point.to_le_bytes())?;
            Ok(Out::Int(n as i64))
        }

        // --- Blot2 host imports (env.blot_*) ---
        ("env", "blot_owner_id") => Ok(Out::Int(caller.data().next_owner.fetch_add(1, Ordering::Relaxed) as i64)),
        ("env", "blot_f32_bits") => Ok(Out::Int(i64::from(arg_f32(args, 0)?.to_bits() as i32))),
        ("env", "blot_f32_from_bits") => Ok(Out::F32(f32::from_bits(arg_u64(args, 0)? as u32))),
        ("env", "blot_f64_bits") => Ok(Out::Int(arg_f64(args, 0)?.to_bits() as i64)),
        ("env", "blot_f64_from_bits") => Ok(Out::F64(f64::from_bits(arg_u64(args, 0)?))),
        ("env", "blot_i32_bits" | "blot_i32_from_bits") => Ok(Out::Int(arg_i64(args, 0)?)),
        ("env", "blot_f32_mul_add") => Ok(Out::F32(arg_f32(args, 0)?.mul_add(arg_f32(args, 1)?, arg_f32(args, 2)?))),
        ("env", "blot_copy_u32") => {
            let dst = arg_u64(args, 0)?;
            let src = arg_u64(args, 1)?;
            let count = arg_u64(args, 2)? as usize;
            if count > 0 {
                let bytes = count.checked_mul(4).ok_or_else(|| host_err("blot_copy_u32 overflow"))?;
                let data = read_mem(caller, src, bytes)?;
                write_mem(caller, dst, &data)?;
            }
            Ok(Out::Void)
        }
        ("env", "blot_copy_u8") => {
            let dst = arg_u64(args, 0)?;
            let src = arg_u64(args, 1)?;
            let count = arg_u64(args, 2)? as usize;
            if count > 0 {
                let data = read_mem(caller, src, count)?;
                write_mem(caller, dst, &data)?;
            }
            Ok(Out::Void)
        }
        ("env", "blot_platform_is_linux") => Ok(Out::Int(i64::from(cfg!(target_os = "linux")))),
        ("env", "blot_process_id" | "blot_thread_id") => Ok(Out::Int(i64::from(std::process::id()))),
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
            let ptr = arg_u64(args, 0)?;
            let count = arg_u64(args, 1)? as usize;
            let data = read_mem(caller, ptr, count)?;
            let _ = io::stderr().write_all(&data);
            Ok(Out::Void)
        }
        ("env", "blot_atomic_load") => {
            let ptr = arg_u64(args, 0)?;
            let bytes = read_mem(caller, ptr, 8)?;
            Ok(Out::Int(u64::from_le_bytes(bytes.try_into().unwrap()) as i64))
        }
        ("env", "blot_atomic_store") => {
            let ptr = arg_u64(args, 0)?;
            let next = arg_u64(args, 1)?;
            write_mem(caller, ptr, &next.to_le_bytes())?;
            Ok(Out::Void)
        }
        ("env", "blot_atomic_add") => {
            let ptr = arg_u64(args, 0)?;
            let amount = arg_u64(args, 1)?;
            let bytes = read_mem(caller, ptr, 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            write_mem(caller, ptr, &before.wrapping_add(amount).to_le_bytes())?;
            Ok(Out::Int(before as i64))
        }
        ("env", "blot_atomic_sub") => {
            let ptr = arg_u64(args, 0)?;
            let amount = arg_u64(args, 1)?;
            let bytes = read_mem(caller, ptr, 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            write_mem(caller, ptr, &before.wrapping_sub(amount).to_le_bytes())?;
            Ok(Out::Int(before as i64))
        }
        ("env", "blot_atomic_max") => {
            let ptr = arg_u64(args, 0)?;
            let candidate = arg_u64(args, 1)?;
            let bytes = read_mem(caller, ptr, 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            if candidate > before {
                write_mem(caller, ptr, &candidate.to_le_bytes())?;
            }
            Ok(Out::Int(before as i64))
        }
        ("env", "blot_argument_count") => Ok(Out::Int(caller.data().args.len() as i64)),
        ("env", "blot_argument_size") => {
            let idx = arg_i64(args, 0)?;
            if idx < 0 || (idx as usize) >= caller.data().args.len() {
                return Ok(Out::Int(-22));
            }
            Ok(Out::Int(caller.data().args[idx as usize].len() as i64))
        }
        ("env", "blot_argument_copy") => {
            let idx = arg_i64(args, 0)?;
            let out = arg_u64(args, 1)?;
            let cap = arg_u64(args, 2)? as usize;
            if idx < 0 || (idx as usize) >= caller.data().args.len() {
                return Ok(Out::Int(-22));
            }
            let bytes = caller.data().args[idx as usize].clone();
            if bytes.len() > cap {
                return Ok(Out::Int(-36));
            }
            write_mem(caller, out, &bytes)?;
            Ok(Out::Int(bytes.len() as i64))
        }
        ("env", "blot_environment_size") => {
            let key = read_cstr(caller, arg_u64(args, 0)?)?;
            match std::env::var_os(OsStr::from_bytes(&key)) {
                Some(val) => Ok(Out::Int(val.as_bytes().len() as i64)),
                None => Ok(Out::Int(-2)),
            }
        }
        ("env", "blot_environment_copy") => {
            let key = read_cstr(caller, arg_u64(args, 0)?)?;
            let out = arg_u64(args, 1)?;
            let cap = arg_u64(args, 2)? as usize;
            match std::env::var_os(OsStr::from_bytes(&key)) {
                Some(val) => {
                    let bytes = val.as_bytes();
                    if bytes.len() > cap {
                        return Ok(Out::Int(-36));
                    }
                    write_mem(caller, out, bytes)?;
                    Ok(Out::Int(bytes.len() as i64))
                }
                None => Ok(Out::Int(-2)),
            }
        }
        ("env", "blot_open_read") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            match File::open(&path) {
                Ok(f) => Ok(Out::Int(i64::from(caller.data_mut().alloc_fd(f)))),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_open_regular") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            let maximum = arg_u64(args, 1)?;
            match File::open(&path) {
                Ok(f) => match f.metadata() {
                    Ok(meta) if meta.is_file() && meta.len() <= maximum => {
                        Ok(Out::Int(i64::from(caller.data_mut().alloc_fd(f))))
                    }
                    _ => Ok(Out::Int(-22)),
                },
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_open_write") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            let exclusive = arg_i64(args, 1)? != 0;
            let mut opts = OpenOptions::new();
            opts.write(true);
            if exclusive {
                opts.create_new(true);
            } else {
                opts.create(true).truncate(true);
            }
            match opts.open(&path) {
                Ok(f) => Ok(Out::Int(i64::from(caller.data_mut().alloc_fd(f)))),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_read") => {
            let fd = arg_i64(args, 0)? as i32;
            let out = arg_u64(args, 1)?;
            let count = arg_u64(args, 2)? as usize;
            let mut buf = vec![0u8; count];
            let res = if fd == 0 {
                io::stdin().read(&mut buf)
            } else {
                match caller.data_mut().files.get_mut(&fd) {
                    Some(f) => f.read(&mut buf),
                    None => return Ok(Out::Int(-9)),
                }
            };
            match res {
                Ok(n) => {
                    write_mem(caller, out, &buf[..n])?;
                    Ok(Out::Int(n as i64))
                }
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_write") => {
            let fd = arg_i64(args, 0)? as i32;
            let ptr = arg_u64(args, 1)?;
            let count = arg_u64(args, 2)? as usize;
            let data = read_mem(caller, ptr, count)?;
            let res = if fd == 1 {
                io::stdout().write(&data)
            } else if fd == 2 {
                io::stderr().write(&data)
            } else {
                match caller.data_mut().files.get_mut(&fd) {
                    Some(f) => f.write(&data),
                    None => return Ok(Out::Int(-9)),
                }
            };
            match res {
                Ok(n) => Ok(Out::Int(n as i64)),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_pwrite") => {
            let fd = arg_i64(args, 0)? as i32;
            let ptr = arg_u64(args, 1)?;
            let count = arg_u64(args, 2)? as usize;
            let offset = arg_u64(args, 3)?;
            let data = read_mem(caller, ptr, count)?;
            let Some(f) = caller.data().files.get(&fd) else {
                return Ok(Out::Int(-9));
            };
            match f.write_at(&data, offset) {
                Ok(n) => Ok(Out::Int(n as i64)),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_close") => {
            let fd = arg_i64(args, 0)? as i32;
            if fd <= 2 {
                return Ok(Out::Int(0));
            }
            Ok(Out::Int(if caller.data_mut().files.remove(&fd).is_some() { 0 } else { -9 }))
        }
        ("env", "blot_sync") => {
            let fd = arg_i64(args, 0)? as i32;
            let Some(f) = caller.data().files.get(&fd) else {
                return Ok(Out::Int(-9));
            };
            match f.sync_all() {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_file_size") => {
            let fd = arg_i64(args, 0)? as i32;
            let res = {
                let Some(f) = caller.data_mut().files.get_mut(&fd) else {
                    return Ok(Out::Int(-9));
                };
                match f.metadata() {
                    Ok(m) => Ok(m.len() as i64),
                    Err(_) => f.seek(SeekFrom::End(0)).map(|sz| sz as i64),
                }
            };
            match res {
                Ok(sz) => Ok(Out::Int(sz)),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_truncate") => {
            let fd = arg_i64(args, 0)? as i32;
            let len = arg_u64(args, 1)?;
            let Some(f) = caller.data().files.get(&fd) else {
                return Ok(Out::Int(-9));
            };
            match f.set_len(len) {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_rename") => {
            let before = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            let after = path_from_bytes(&read_cstr(caller, arg_u64(args, 1)?)?);
            match fs::rename(&before, &after) {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_remove") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            match fs::remove_file(&path) {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_mkdir") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            match fs::create_dir(&path) {
                Ok(()) => Ok(Out::Int(0)),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_real_path") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            let out = arg_u64(args, 1)?;
            let cap = arg_u64(args, 2)? as usize;
            match fs::canonicalize(&path) {
                Ok(resolved) => {
                    let bytes = resolved.into_os_string().into_vec();
                    if bytes.len() < cap {
                        let mut nul = bytes.clone();
                        nul.push(0);
                        write_mem(caller, out, &nul)?;
                    }
                    Ok(Out::Int(bytes.len() as i64))
                }
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_path_kind") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            match fs::metadata(&path) {
                Ok(m) if m.is_file() => Ok(Out::Int(1)),
                Ok(m) if m.is_dir() => Ok(Out::Int(2)),
                Ok(_) => Ok(Out::Int(-1)),
                Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(Out::Int(0)),
                Err(e) => {
                    let _ = caller.data().set_errno(&e);
                    Ok(Out::Int(-1))
                }
            }
        }
        ("env", "blot_directory_open") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            let read_dir = match fs::read_dir(&path) {
                Ok(rd) => rd,
                Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Out::Int(0)),
                Err(e) => {
                    let _ = caller.data().set_errno(&e);
                    return Ok(Out::Int(-1));
                }
            };
            let mut entries = Vec::new();
            for item in read_dir {
                let Ok(entry) = item else { continue };
                if let Ok(meta) = fs::symlink_metadata(entry.path())
                    && meta.is_file()
                {
                    entries.push(entry.file_name().into_vec());
                }
            }
            let handle = caller.data().next_dir;
            caller.data_mut().next_dir += 1;
            caller.data_mut().dirs.insert(handle, DirCursor { entries, index: 0 });
            Ok(Out::Int(handle))
        }
        ("env", "blot_directory_next") => {
            let handle = arg_i64(args, 0)?;
            let out = arg_u64(args, 1)?;
            let cap = arg_u64(args, 2)? as usize;
            let entry = {
                let Some(cursor) = caller.data_mut().dirs.get_mut(&handle) else {
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
                write_mem(caller, out, &entry)?;
            }
            Ok(Out::Int(entry.len() as i64))
        }
        ("env", "blot_directory_close") => {
            let handle = arg_i64(args, 0)?;
            Ok(Out::Int(if caller.data_mut().dirs.remove(&handle).is_some() { 0 } else { -1 }))
        }
        ("env", "blot_last_errno") => Ok(Out::Int(i64::from(caller.data().last_errno.load(Ordering::Relaxed)))),
        ("env", "blot_lock_open") => {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(args, 0)?)?);
            match OpenOptions::new().read(true).write(true).create(true).truncate(false).open(&path) {
                Ok(f) => Ok(Out::Int(i64::from(caller.data_mut().alloc_fd(f)))),
                Err(e) => Ok(Out::Int(i64::from(caller.data().set_errno(&e)))),
            }
        }
        ("env", "blot_try_lock" | "blot_unlock") => Ok(Out::Int(0)),
        ("env", "blot_available_workers") => Ok(Out::Int(1)),
        ("env", "blot_runtime_observation") => Ok(Out::Int(0)),
        ("env", "blot_runtime_memory_mark") => Ok(Out::Void),
        ("env", "blot_fork" | "blot_worker_spawn") => Ok(Out::Int(-38)),
        ("env", "blot_persist_open" | "blot_check_reply_open") => Ok(Out::Int(0)),
        (
            "env",
            "blot_persist_node"
            | "blot_persist_edge"
            | "blot_persist_publish"
            | "blot_persist_read"
            | "blot_check_reply_append"
            | "blot_wait_success",
        ) => Ok(Out::Int(0)),
        ("env", "blot_persist_claim") => Ok(Out::Int(-95)),
        (
            "env",
            "blot_persist_size"
            | "blot_check_reply_size"
            | "blot_check_reply_copy"
            | "blot_worker_descriptor"
            | "blot_worker_stop"
            | "blot_detach_session",
        ) => Ok(Out::Int(-1)),
        (
            "env",
            "blot_persist_kill_child"
            | "blot_persist_fail"
            | "blot_persist_close"
            | "blot_check_reply_close"
            | "blot_worker_detach"
            | "blot_null_standard_io"
            | "blot_request_fail_oom"
            | "blot_request_fail",
        ) => Ok(Out::Void),
        ("env", "blot_job_exit") => {
            let code = arg_i64(args, 0)? as i32;
            caller.data_mut().exit_code = Some(code);
            Err(host_err(format!("exit:{code}")))
        }
        (
            "env",
            "blot_request_start"
            | "blot_request_begin"
            | "blot_request_input_fd"
            | "blot_request_transport_reply_open"
            | "blot_request_transport_finish"
            | "blot_request_transport_run",
        ) => Ok(Out::Int(-38)),
        ("env", "blot_request_token") => Ok(Out::Int(0)),
        ("env", "system") => Ok(Out::Int(-1)),
        _ => Err(host_err(format!("unsupported wtime-aot host import: {module}.{name}"))),
    }
}

fn stamp_of(bytes: &[u8], fast: bool) -> String {
    // Simple FNV-1a 128-bit + length stamp for local `.wtaot` cache validation.
    let mut h1: u64 = 0xcbf2_9ce4_8422_2325;
    let mut h2: u64 = 0x1000_0000_01b3_9e37;
    for &b in bytes {
        h1 ^= u64::from(b);
        h1 = h1.wrapping_mul(0x0000_0100_0000_01b3);
        h2 = h2.wrapping_mul(0x9e37_79b9_7f4a_7c15) ^ u64::from(b);
    }
    let mode = if fast { "opt0" } else { "opt2" };
    format!("wtaot-v1:{mode}:{}:{h1:016x}{h2:016x}\n", bytes.len())
}

fn parse_args() -> Result<Options, String> {
    let raw: Vec<Vec<u8>> = std::env::args_os().skip(1).map(std::ffi::OsString::into_vec).collect();
    let mut own = raw;
    let mut program_tail = Vec::new();
    if let Some(pos) = own.iter().position(|a| a == b"--") {
        program_tail = own.split_off(pos + 1);
        own.pop();
    }
    let mut module: Option<PathBuf> = None;
    let mut entry: Option<String> = None;
    let mut fast = false;
    let mut cache: Option<PathBuf> = None;
    let mut timing_json: Option<PathBuf> = None;

    let mut i = 0;
    while i < own.len() {
        let arg = String::from_utf8_lossy(&own[i]).into_owned();
        if arg == "-h" || arg == "--help" {
            println!("{USAGE}");
            std::process::exit(0);
        } else if arg == "--fast" || arg == "--fast-jit" || arg == "--opt-none" {
            fast = true;
        } else if arg == "--entry" {
            i += 1;
            let Some(v) = own.get(i) else {
                return Err("missing value for --entry".into());
            };
            entry = Some(String::from_utf8_lossy(v).into_owned());
        } else if arg == "--cache" {
            i += 1;
            let Some(v) = own.get(i) else {
                return Err("missing value for --cache".into());
            };
            cache = Some(path_from_bytes(v));
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
        fast,
        cache,
        timing_json,
        program_args,
    })
}

fn run_module(opts: &Options) -> Result<i32, String> {
    let bytes = fs::read(&opts.module)
        .map_err(|e| format!("failed to read {}: {e}", opts.module.display()))?;
    let mut cfg = Config::new();
    cfg.wasm_memory64(true)
        .wasm_simd(true)
        .wasm_relaxed_simd(true)
        .wasm_tail_call(true)
        .wasm_exceptions(true)
        .wasm_multi_memory(true)
        .wasm_reference_types(true)
        .wasm_function_references(true)
        .parallel_compilation(true);
    if opts.fast {
        cfg.cranelift_opt_level(OptLevel::None);
    } else {
        cfg.cranelift_opt_level(OptLevel::Speed);
    }
    let engine = Engine::new(&cfg).map_err(|e| format!("wtime-aot-host engine error: {e}"))?;

    let t0 = Instant::now();
    let module = if let Some(cache_path) = &opts.cache {
        let mut stamp_os = cache_path.as_os_str().to_os_string();
        stamp_os.push(".stamp");
        let stamp_path = PathBuf::from(stamp_os);
        let expected_stamp = stamp_of(&bytes, opts.fast);
        let cached = if fs::read_to_string(&stamp_path).ok().as_deref() == Some(expected_stamp.as_str()) {
            fs::read(cache_path)
                .ok()
                .and_then(|blob| unsafe { Module::deserialize(&engine, &blob) }.ok())
        } else {
            None
        };
        if let Some(m) = cached {
            m
        } else {
            let m = Module::new(&engine, &bytes)
                .map_err(|e| format!("wtime-aot compile error: {e}"))?;
            if let Ok(blob) = m.serialize() {
                if let Some(parent) = cache_path.parent()
                    && !parent.as_os_str().is_empty()
                {
                    let _ = fs::create_dir_all(parent);
                }
                if fs::write(cache_path, blob).is_ok() {
                    let _ = fs::write(&stamp_path, expected_stamp);
                }
            }
            m
        }
    } else {
        Module::new(&engine, &bytes).map_err(|e| format!("wtime-aot compile error: {e}"))?
    };
    let compile_ns = t0.elapsed().as_nanos() as u64;

    let resource_dir = fs::canonicalize(&opts.module).ok().and_then(|p| {
        p.parent().map(|d| {
            let mut b = d.as_os_str().as_bytes().to_vec();
            if !b.ends_with(b"/") {
                b.push(b'/');
            }
            b
        })
    });

    let mut store = Store::new(&engine, HostState::new(opts.program_args.clone(), resource_dir));
    store.limiter(|s| &mut s.limits);
    let mut linker = Linker::new(&engine);
    let mut defined: HashSet<(String, String)> = HashSet::new();
    for imp in module.imports() {
        let mod_str = imp.module().to_string();
        let name_str = imp.name().to_string();
        if !defined.insert((mod_str.clone(), name_str.clone())) {
            continue;
        }
        let ExternType::Func(func_ty) = imp.ty() else {
            continue;
        };
        let params: Vec<ValType> = func_ty.params().collect();
        let results: Vec<ValType> = func_ty.results().collect();
        linker
            .func_new(imp.module(), imp.name(), func_ty, move |mut caller, args, out_vals| {
                let res = dispatch_import(&mod_str, &name_str, &mut caller, args, &params)?;
                match (res, results.as_slice()) {
                    (Out::Void, []) => Ok(()),
                    (Out::Int(v), [ValType::I32]) => {
                        out_vals[0] = Val::I32(v as i32);
                        Ok(())
                    }
                    (Out::Int(v), [ValType::I64]) => {
                        out_vals[0] = Val::I64(v);
                        Ok(())
                    }
                    (Out::F32(v), [ValType::F32]) => {
                        out_vals[0] = Val::F32(v.to_bits());
                        Ok(())
                    }
                    (Out::F64(v), [ValType::F64]) => {
                        out_vals[0] = Val::F64(v.to_bits());
                        Ok(())
                    }
                    (Out::F64(v), [ValType::F32]) => {
                        out_vals[0] = Val::F32((v as f32).to_bits());
                        Ok(())
                    }
                    _ => Err(host_err(format!("result type mismatch for {mod_str}.{name_str}"))),
                }
            })
            .map_err(|e| format!("failed to define host import {imp:?}: {e}"))?;
    }

    let t1 = Instant::now();
    let instance = linker
        .instantiate(&mut store, &module)
        .map_err(|e| format!("wtime-aot instantiate error: {e}"))?;
    let instantiate_ns = t1.elapsed().as_nanos() as u64;

    if let Some(mem) = instance.get_memory(&mut store, "memory") {
        store.data_mut().memory = Some(mem);
    }
    if let Some(res_fn) = instance.get_func(&mut store, "goose.reserve") {
        store.data_mut().reserve_fn = Some(res_fn);
    }

    let t2 = Instant::now();
    let mut exit_code: i32 = 0;

    let invoke_export = |store: &mut Store<HostState>, export_name: &str| -> Result<Option<i32>, String> {
        let func = instance
            .get_func(&mut *store, export_name)
            .ok_or_else(|| format!("missing export {export_name}"))?;
        let n_res = func.ty(&*store).results().len();
        let mut results = vec![Val::I32(0); n_res];
        match func.call(&mut *store, &[], &mut results) {
            Ok(()) => match results.first() {
                Some(Val::I32(code)) => Ok(Some(*code)),
                Some(Val::I64(code)) => Ok(Some(*code as i32)),
                _ => Ok(None),
            },
            Err(err) => {
                if let Some(code) = store.data().exit_code {
                    return Ok(Some(code));
                }
                if let Some(msg) = store.data().abort_message.clone() {
                    let _ = writeln!(io::stderr(), "{msg}");
                    return Ok(Some(1));
                }
                Err(format!("wtime-aot runtime error in {export_name}: {err}"))
            }
        }
    };

    if instance.get_func(&mut store, "_start").is_some()
        && let Some(code) = invoke_export(&mut store, "_start")?
    {
        exit_code = code;
    }
    if store.data().exit_code.is_none()
        && store.data().abort_message.is_none()
        && let Some(entry_name) = &opts.entry
        && let Some(code) = invoke_export(&mut store, entry_name)?
    {
        exit_code = code;
    }
    let run_ns = t2.elapsed().as_nanos() as u64;

    let _ = io::stdout().flush();
    let _ = io::stderr().flush();

    if let Some(path) = &opts.timing_json {
        let opt_str = if opts.fast { "wtime-aot x64 O0" } else { "wtime-aot x64 O2" };
        let compile_inst = compile_ns.saturating_add(instantiate_ns);
        let total = compile_inst.saturating_add(run_ns);
        let json = format!(
            "{{\"engine\":\"wtime-aot-host\",\"optimization\":\"{opt_str}\",\"compile_ns\":{compile_ns},\"instantiate_ns\":{instantiate_ns},\"run_ns\":{run_ns},\"compile_instantiate_ns\":{compile_inst},\"start_function_ns\":{run_ns},\"engine_total_ns\":{total}}}\n"
        );
        if let Some(parent) = path.parent()
            && !parent.as_os_str().is_empty()
            && parent != Path::new("")
        {
            let _ = fs::create_dir_all(parent);
        }
        fs::write(path, json).map_err(|e| format!("failed to write {}: {e}", path.display()))?;
    }
    Ok(exit_code)
}

fn main() -> ExitCode {
    let opts = match parse_args() {
        Ok(o) => o,
        Err(msg) => {
            eprintln!("{USAGE}\ngoose-wtime-aot: error: {msg}");
            return ExitCode::from(2);
        }
    };
    let result = std::thread::Builder::new()
        .stack_size(64 * 1024 * 1024)
        .spawn(move || run_module(&opts))
        .expect("spawn wtime-aot host thread")
        .join()
        .unwrap_or_else(|_| Err("wtime-aot host thread panicked".into()));
    match result {
        Ok(code) => ExitCode::from((code & 0xff) as u8),
        Err(msg) => {
            eprintln!("goose-wtime-aot: {msg}");
            ExitCode::from(1)
        }
    }
}
