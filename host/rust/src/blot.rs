//! Blot2 (`env.blot_*`) and math (`env.gs_*` / libm) host imports for
//! `goose-wasmtime`, mirroring `host/wtime` for fast Cranelift JIT execution
//! and `.cwasm` caching of Blot2 compiled directly to Wasm64.

use std::collections::HashMap;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::FileExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::time::{Duration, Instant};

use wasmtime::{Caller, Error, Result, Val};

use crate::host::{failure, float, integer, memory, read_bytes, span, write_bytes, Handler, Host, Out, ProgramExit};

struct DirCursor {
    entries: Vec<Vec<u8>>,
    index: usize,
}

pub(crate) struct BlotState {
    start_instant: Instant,
    next_owner: AtomicU64,
    next_fd: i32,
    files: HashMap<i32, File>,
    next_dir: i64,
    dirs: HashMap<i64, DirCursor>,
    last_errno: AtomicI32,
}

impl BlotState {
    pub(crate) fn new() -> Self {
        Self {
            start_instant: Instant::now(),
            next_owner: AtomicU64::new(1),
            next_fd: 3,
            files: HashMap::new(),
            next_dir: 1,
            dirs: HashMap::new(),
            last_errno: AtomicI32::new(0),
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

fn arg_u64(values: &[Val], index: usize) -> Result<u64> {
    match values.get(index) {
        Some(Val::I32(v)) => Ok(u64::from(*v as u32)),
        Some(Val::I64(v)) => Ok(*v as u64),
        _ => Err(failure("expected integer argument")),
    }
}

fn arg_f32(values: &[Val], index: usize) -> Result<f32> {
    match values.get(index) {
        Some(Val::F32(bits)) => Ok(f32::from_bits(*bits)),
        Some(Val::F64(bits)) => Ok(f64::from_bits(*bits) as f32),
        _ => Err(failure("expected f32 argument")),
    }
}

fn read_cstr(caller: &mut Caller<'_, Host>, ptr: u64) -> Result<Vec<u8>> {
    let data = memory(caller)?.data(&*caller);
    let start = usize::try_from(ptr).map_err(|_| failure("C string pointer out of range"))?;
    if start >= data.len() {
        return Err(failure("C string pointer outside exported memory"));
    }
    let limit = data.len().min(start.saturating_add(65536));
    let slice = &data[start..limit];
    let Some(end) = slice.iter().position(|&b| b == 0) else {
        return Err(failure("unterminated C string"));
    };
    Ok(slice[..end].to_vec())
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

pub(crate) fn handler_for(module: &str, name: &str) -> Option<Handler> {
    if module != "env" {
        return None;
    }
    let handler: Handler = match name {
        // --- Math imports ---
        "frexp" => |caller, values| {
            let (mant, exp) = pure_frexp(float(values, 0)?);
            let ptr = arg_u64(values, 1)?;
            write_bytes(caller, ptr.into(), &exp.to_le_bytes())?;
            Ok(Out::Float(mant))
        },
        "ldexp" => |_, values| Ok(Out::Float(pure_ldexp(float(values, 0)?, integer(values, 1)? as i32))),
        "acosh" | "gs_acosh" => |_, values| Ok(Out::Float(float(values, 0)?.acosh())),
        "asinh" | "gs_asinh" => |_, values| Ok(Out::Float(float(values, 0)?.asinh())),
        "atanh" | "gs_atanh" => |_, values| Ok(Out::Float(float(values, 0)?.atanh())),
        "sinh" | "gs_sinh" => |_, values| Ok(Out::Float(float(values, 0)?.sinh())),
        "gs_sinhf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.sinh())),
        "cosh" | "gs_cosh" => |_, values| Ok(Out::Float(float(values, 0)?.cosh())),
        "gs_coshf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.cosh())),
        "tanh" | "gs_tanh" => |_, values| Ok(Out::Float(float(values, 0)?.tanh())),
        "gs_tanhf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.tanh())),
        "exp2" | "gs_exp2" => |_, values| Ok(Out::Float(float(values, 0)?.exp2())),
        "gs_exp2f" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.exp2())),
        "sin" | "gs_sin" => |_, values| Ok(Out::Float(float(values, 0)?.sin())),
        "gs_sinf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.sin())),
        "cos" | "gs_cos" => |_, values| Ok(Out::Float(float(values, 0)?.cos())),
        "gs_cosf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.cos())),
        "tan" | "gs_tan" => |_, values| Ok(Out::Float(float(values, 0)?.tan())),
        "gs_tanf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.tan())),
        "asin" | "gs_asin" => |_, values| Ok(Out::Float(float(values, 0)?.asin())),
        "gs_asinf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.asin())),
        "acos" | "gs_acos" => |_, values| Ok(Out::Float(float(values, 0)?.acos())),
        "gs_acosf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.acos())),
        "atan" | "gs_atan" => |_, values| Ok(Out::Float(float(values, 0)?.atan())),
        "gs_atanf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.atan())),
        "atan2" | "gs_atan2" => |_, values| Ok(Out::Float(float(values, 0)?.atan2(float(values, 1)?))),
        "gs_atan2f" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.atan2(arg_f32(values, 1)?))),
        "exp" | "gs_exp" => |_, values| Ok(Out::Float(float(values, 0)?.exp())),
        "gs_expf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.exp())),
        "log" | "gs_log" => |_, values| Ok(Out::Float(float(values, 0)?.ln())),
        "gs_logf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.ln())),
        "log2" | "gs_log2" => |_, values| Ok(Out::Float(float(values, 0)?.log2())),
        "gs_log2f" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.log2())),
        "log10" | "gs_log10" => |_, values| Ok(Out::Float(float(values, 0)?.log10())),
        "gs_log10f" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.log10())),
        "pow" | "gs_pow" => |_, values| Ok(Out::Float(float(values, 0)?.powf(float(values, 1)?))),
        "gs_powf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.powf(arg_f32(values, 1)?))),
        "gs_mul_add" => |_, values| Ok(Out::Float(float(values, 0)?.mul_add(float(values, 1)?, float(values, 2)?))),
        "gs_mul_addf" => |_, values| {
            Ok(Out::Float32(arg_f32(values, 0)?.mul_add(arg_f32(values, 1)?, arg_f32(values, 2)?)))
        },
        "round" | "gs_round" => |_, values| Ok(Out::Float(float(values, 0)?.round())),
        "roundf" | "gs_roundf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.round())),
        "hypot" | "gs_hypot" => |_, values| Ok(Out::Float(float(values, 0)?.hypot(float(values, 1)?))),
        "gs_hypotf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.hypot(arg_f32(values, 1)?))),
        "cbrt" | "gs_cbrt" => |_, values| Ok(Out::Float(float(values, 0)?.cbrt())),
        "gs_cbrtf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.cbrt())),
        "expm1" | "gs_expm1" => |_, values| Ok(Out::Float(float(values, 0)?.exp_m1())),
        "gs_expm1f" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.exp_m1())),
        "log1p" | "gs_log1p" => |_, values| Ok(Out::Float(float(values, 0)?.ln_1p())),
        "gs_log1pf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)?.ln_1p())),
        "fmod" | "gs_fmod" => |_, values| Ok(Out::Float(float(values, 0)? % float(values, 1)?)),
        "fmodf" | "gs_fmodf" => |_, values| Ok(Out::Float32(arg_f32(values, 0)? % arg_f32(values, 1)?)),

        // --- OS helpers shared with Blot2 ---
        "gs_os_sleep_ms" | "blot_sleep_ms" => |_, values| {
            let ms = integer(values, 0)?;
            if ms > 0 {
                std::thread::sleep(Duration::from_millis(ms as u64));
            }
            Ok(Out::Nothing)
        },
        "gs_os_random_u64" | "blot_random_u64" => blot_random_u64,
        "blot_clock_ns" | "blot_thread_cpu_ns" => |caller, _| {
            let ns = caller.data().blot.start_instant.elapsed().as_nanos() as i64;
            Ok(Out::Integer(ns))
        },

        // --- Blot2 host imports (env.blot_*) ---
        "blot_owner_id" => |caller, _| {
            let id = caller.data().blot.next_owner.fetch_add(1, Ordering::Relaxed);
            Ok(Out::Integer(id as i64))
        },
        "blot_f32_bits" => |_, values| match values.first() {
            Some(Val::F32(bits)) => Ok(Out::Integer(i64::from(*bits as i32))),
            _ => Ok(Out::Integer(i64::from(arg_f32(values, 0)?.to_bits() as i32))),
        },
        "blot_f32_from_bits" => |_, values| Ok(Out::Float32(f32::from_bits(arg_u64(values, 0)? as u32))),
        "blot_f64_bits" => |_, values| match values.first() {
            Some(Val::F64(bits)) => Ok(Out::Integer(*bits as i64)),
            _ => Ok(Out::Integer(float(values, 0)?.to_bits() as i64)),
        },
        "blot_f64_from_bits" => |_, values| Ok(Out::Float(f64::from_bits(arg_u64(values, 0)?))),
        "blot_i32_bits" | "blot_i32_from_bits" => |_, values| Ok(Out::Integer(integer(values, 0)?)),
        "blot_f32_mul_add" => |_, values| {
            Ok(Out::Float32(arg_f32(values, 0)?.mul_add(arg_f32(values, 1)?, arg_f32(values, 2)?)))
        },
        "blot_copy_u32" => |caller, values| blot_copy(caller, values, 4),
        "blot_copy_u8" => |caller, values| blot_copy(caller, values, 1),
        "blot_platform_is_linux" => |_, _| Ok(Out::Integer(if cfg!(target_os = "linux") { 1 } else { 0 })),
        "blot_process_id" | "blot_thread_id" => |_, _| Ok(Out::Integer(i64::from(std::process::id()))),
        "blot_peak_rss_kib" => |_, _| {
            let kib = fs::read_to_string("/proc/self/status")
                .ok()
                .and_then(|s| {
                    s.lines().find_map(|line| {
                        let rest = line.strip_prefix("VmHWM:")?;
                        rest.split_whitespace().next()?.parse::<i64>().ok()
                    })
                })
                .unwrap_or(0);
            Ok(Out::Integer(kib))
        },
        "blot_debug_write" => |caller, values| {
            let ptr = arg_u64(values, 0)?;
            let count = arg_u64(values, 1)?;
            let data = read_bytes(caller, ptr.into(), count.into())?;
            let _ = io::stderr().write_all(&data);
            Ok(Out::Nothing)
        },
        "blot_atomic_load" => |caller, values| {
            let ptr = arg_u64(values, 0)?;
            let bytes = read_bytes(caller, ptr.into(), 8)?;
            Ok(Out::Integer(u64::from_le_bytes(bytes.try_into().unwrap()) as i64))
        },
        "blot_atomic_store" => |caller, values| {
            let ptr = arg_u64(values, 0)?;
            let next = arg_u64(values, 1)?;
            write_bytes(caller, ptr.into(), &next.to_le_bytes())?;
            Ok(Out::Nothing)
        },
        "blot_atomic_add" => |caller, values| {
            let ptr = arg_u64(values, 0)?;
            let amount = arg_u64(values, 1)?;
            let bytes = read_bytes(caller, ptr.into(), 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            write_bytes(caller, ptr.into(), &before.wrapping_add(amount).to_le_bytes())?;
            Ok(Out::Integer(before as i64))
        },
        "blot_atomic_sub" => |caller, values| {
            let ptr = arg_u64(values, 0)?;
            let amount = arg_u64(values, 1)?;
            let bytes = read_bytes(caller, ptr.into(), 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            write_bytes(caller, ptr.into(), &before.wrapping_sub(amount).to_le_bytes())?;
            Ok(Out::Integer(before as i64))
        },
        "blot_atomic_max" => |caller, values| {
            let ptr = arg_u64(values, 0)?;
            let candidate = arg_u64(values, 1)?;
            let bytes = read_bytes(caller, ptr.into(), 8)?;
            let before = u64::from_le_bytes(bytes.try_into().unwrap());
            if candidate > before {
                write_bytes(caller, ptr.into(), &candidate.to_le_bytes())?;
            }
            Ok(Out::Integer(before as i64))
        },
        "blot_argument_count" => |caller, _| Ok(Out::Integer(caller.data().arguments.len() as i64)),
        "blot_argument_size" => |caller, values| {
            let idx = integer(values, 0)?;
            let args = &caller.data().arguments;
            if idx < 0 || (idx as usize) >= args.len() {
                return Ok(Out::Integer(-22));
            }
            Ok(Out::Integer(args[idx as usize].len() as i64))
        },
        "blot_argument_copy" => |caller, values| {
            let idx = integer(values, 0)?;
            let out = arg_u64(values, 1)?;
            let cap = arg_u64(values, 2)? as usize;
            let bytes = {
                let args = &caller.data().arguments;
                if idx < 0 || (idx as usize) >= args.len() {
                    return Ok(Out::Integer(-22));
                }
                args[idx as usize].clone()
            };
            if bytes.len() > cap {
                return Ok(Out::Integer(-36));
            }
            write_bytes(caller, out.into(), &bytes)?;
            Ok(Out::Integer(bytes.len() as i64))
        },
        "blot_environment_size" => |caller, values| {
            let key = read_cstr(caller, arg_u64(values, 0)?)?;
            match std::env::var_os(OsStr::from_bytes(&key)) {
                Some(val) => Ok(Out::Integer(val.as_bytes().len() as i64)),
                None => Ok(Out::Integer(-2)),
            }
        },
        "blot_environment_copy" => |caller, values| {
            let key = read_cstr(caller, arg_u64(values, 0)?)?;
            let out = arg_u64(values, 1)?;
            let cap = arg_u64(values, 2)? as usize;
            match std::env::var_os(OsStr::from_bytes(&key)) {
                Some(val) => {
                    let bytes = val.as_bytes();
                    if bytes.len() > cap {
                        return Ok(Out::Integer(-36));
                    }
                    write_bytes(caller, out.into(), bytes)?;
                    Ok(Out::Integer(bytes.len() as i64))
                }
                None => Ok(Out::Integer(-2)),
            }
        },
        "blot_open_read" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            let blot = &mut caller.data_mut().blot;
            match File::open(&path) {
                Ok(f) => Ok(Out::Integer(i64::from(blot.alloc_fd(f)))),
                Err(e) => Ok(Out::Integer(i64::from(blot.set_errno(&e)))),
            }
        },
        "blot_open_regular" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            let maximum = arg_u64(values, 1)?;
            let blot = &mut caller.data_mut().blot;
            match File::open(&path) {
                Ok(f) => match f.metadata() {
                    Ok(meta) if meta.is_file() && meta.len() <= maximum => {
                        Ok(Out::Integer(i64::from(blot.alloc_fd(f))))
                    }
                    _ => Ok(Out::Integer(-22)),
                },
                Err(e) => Ok(Out::Integer(i64::from(blot.set_errno(&e)))),
            }
        },
        "blot_open_write" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            let exclusive = integer(values, 1)? != 0;
            let mut opts = OpenOptions::new();
            opts.write(true);
            if exclusive {
                opts.create_new(true);
            } else {
                opts.create(true).truncate(true);
            }
            let blot = &mut caller.data_mut().blot;
            match opts.open(&path) {
                Ok(f) => Ok(Out::Integer(i64::from(blot.alloc_fd(f)))),
                Err(e) => Ok(Out::Integer(i64::from(blot.set_errno(&e)))),
            }
        },
        "blot_read" => |caller, values| {
            let fd = integer(values, 0)? as i32;
            let out = arg_u64(values, 1)?;
            let count = arg_u64(values, 2)? as usize;
            let mut buf = vec![0u8; count];
            let res = if fd == 0 {
                io::stdin().read(&mut buf)
            } else {
                match caller.data_mut().blot.files.get_mut(&fd) {
                    Some(f) => f.read(&mut buf),
                    None => return Ok(Out::Integer(-9)),
                }
            };
            match res {
                Ok(n) => {
                    write_bytes(caller, out.into(), &buf[..n])?;
                    Ok(Out::Integer(n as i64))
                }
                Err(e) => Ok(Out::Integer(i64::from(caller.data().blot.set_errno(&e)))),
            }
        },
        "blot_write" => |caller, values| {
            let fd = integer(values, 0)? as i32;
            let ptr = arg_u64(values, 1)?;
            let count = arg_u64(values, 2)?;
            let data = read_bytes(caller, ptr.into(), count.into())?;
            if fd == 1 {
                caller.data_mut().out.extend_from_slice(&data);
                return Ok(Out::Integer(data.len() as i64));
            }
            if fd == 2 {
                let res = io::stderr().write(&data);
                return match res {
                    Ok(n) => Ok(Out::Integer(n as i64)),
                    Err(e) => Ok(Out::Integer(i64::from(caller.data().blot.set_errno(&e)))),
                };
            }
            let res = match caller.data_mut().blot.files.get_mut(&fd) {
                Some(f) => f.write(&data),
                None => return Ok(Out::Integer(-9)),
            };
            match res {
                Ok(n) => Ok(Out::Integer(n as i64)),
                Err(e) => Ok(Out::Integer(i64::from(caller.data().blot.set_errno(&e)))),
            }
        },
        "blot_pwrite" => |caller, values| {
            let fd = integer(values, 0)? as i32;
            let ptr = arg_u64(values, 1)?;
            let count = arg_u64(values, 2)?;
            let offset = arg_u64(values, 3)?;
            let data = read_bytes(caller, ptr.into(), count.into())?;
            let blot = &caller.data().blot;
            let Some(f) = blot.files.get(&fd) else {
                return Ok(Out::Integer(-9));
            };
            match f.write_at(&data, offset) {
                Ok(n) => Ok(Out::Integer(n as i64)),
                Err(e) => Ok(Out::Integer(i64::from(blot.set_errno(&e)))),
            }
        },
        "blot_close" => |caller, values| {
            let fd = integer(values, 0)? as i32;
            if fd <= 2 {
                return Ok(Out::Integer(0));
            }
            Ok(Out::Integer(if caller.data_mut().blot.files.remove(&fd).is_some() { 0 } else { -9 }))
        },
        "blot_sync" => |caller, values| {
            let fd = integer(values, 0)? as i32;
            let blot = &caller.data().blot;
            let Some(f) = blot.files.get(&fd) else {
                return Ok(Out::Integer(-9));
            };
            match f.sync_all() {
                Ok(()) => Ok(Out::Integer(0)),
                Err(e) => Ok(Out::Integer(i64::from(blot.set_errno(&e)))),
            }
        },
        "blot_file_size" => |caller, values| {
            let fd = integer(values, 0)? as i32;
            let blot = &mut caller.data_mut().blot;
            let Some(f) = blot.files.get_mut(&fd) else {
                return Ok(Out::Integer(-9));
            };
            match f.metadata() {
                Ok(m) => Ok(Out::Integer(m.len() as i64)),
                Err(_) => match f.seek(SeekFrom::End(0)) {
                    Ok(sz) => Ok(Out::Integer(sz as i64)),
                    Err(e) => Ok(Out::Integer(i64::from(blot.set_errno(&e)))),
                },
            }
        },
        "blot_truncate" => |caller, values| {
            let fd = integer(values, 0)? as i32;
            let len = arg_u64(values, 1)?;
            let blot = &caller.data().blot;
            let Some(f) = blot.files.get(&fd) else {
                return Ok(Out::Integer(-9));
            };
            match f.set_len(len) {
                Ok(()) => Ok(Out::Integer(0)),
                Err(e) => Ok(Out::Integer(i64::from(blot.set_errno(&e)))),
            }
        },
        "blot_rename" => |caller, values| {
            let before = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            let after = path_from_bytes(&read_cstr(caller, arg_u64(values, 1)?)?);
            match fs::rename(&before, &after) {
                Ok(()) => Ok(Out::Integer(0)),
                Err(e) => Ok(Out::Integer(i64::from(caller.data().blot.set_errno(&e)))),
            }
        },
        "blot_remove" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            match fs::remove_file(&path) {
                Ok(()) => Ok(Out::Integer(0)),
                Err(e) => Ok(Out::Integer(i64::from(caller.data().blot.set_errno(&e)))),
            }
        },
        "blot_mkdir" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            match fs::create_dir(&path) {
                Ok(()) => Ok(Out::Integer(0)),
                Err(e) => Ok(Out::Integer(i64::from(caller.data().blot.set_errno(&e)))),
            }
        },
        "blot_real_path" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            let out = arg_u64(values, 1)?;
            let cap = arg_u64(values, 2)? as usize;
            match fs::canonicalize(&path) {
                Ok(resolved) => {
                    let bytes = resolved.into_os_string().into_vec();
                    if bytes.len() < cap {
                        let mut nul_bytes = bytes.clone();
                        nul_bytes.push(0);
                        write_bytes(caller, out.into(), &nul_bytes)?;
                    }
                    Ok(Out::Integer(bytes.len() as i64))
                }
                Err(e) => Ok(Out::Integer(i64::from(caller.data().blot.set_errno(&e)))),
            }
        },
        "blot_path_kind" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            match fs::metadata(&path) {
                Ok(m) if m.is_file() => Ok(Out::Integer(1)),
                Ok(m) if m.is_dir() => Ok(Out::Integer(2)),
                Ok(_) => Ok(Out::Integer(-1)),
                Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(Out::Integer(0)),
                Err(e) => {
                    let _ = caller.data().blot.set_errno(&e);
                    Ok(Out::Integer(-1))
                }
            }
        },
        "blot_directory_open" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            let read_dir = match fs::read_dir(&path) {
                Ok(rd) => rd,
                Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Out::Integer(0)),
                Err(e) => {
                    let _ = caller.data().blot.set_errno(&e);
                    return Ok(Out::Integer(-1));
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
            let blot = &mut caller.data_mut().blot;
            let handle = blot.next_dir;
            blot.next_dir += 1;
            blot.dirs.insert(handle, DirCursor { entries, index: 0 });
            Ok(Out::Integer(handle))
        },
        "blot_directory_next" => |caller, values| {
            let handle = integer(values, 0)?;
            let out = arg_u64(values, 1)?;
            let cap = arg_u64(values, 2)? as usize;
            let entry = {
                let Some(cursor) = caller.data_mut().blot.dirs.get_mut(&handle) else {
                    return Ok(Out::Integer(-1));
                };
                if cursor.index >= cursor.entries.len() {
                    return Ok(Out::Integer(0));
                }
                let name = cursor.entries[cursor.index].clone();
                if name.len() > cap {
                    return Ok(Out::Integer(name.len() as i64));
                }
                cursor.index += 1;
                name
            };
            if !entry.is_empty() {
                write_bytes(caller, out.into(), &entry)?;
            }
            Ok(Out::Integer(entry.len() as i64))
        },
        "blot_directory_close" => |caller, values| {
            let handle = integer(values, 0)?;
            Ok(Out::Integer(if caller.data_mut().blot.dirs.remove(&handle).is_some() { 0 } else { -1 }))
        },
        "blot_last_errno" => |caller, _| Ok(Out::Integer(i64::from(caller.data().blot.last_errno.load(Ordering::Relaxed)))),
        "blot_lock_open" => |caller, values| {
            let path = path_from_bytes(&read_cstr(caller, arg_u64(values, 0)?)?);
            let blot = &mut caller.data_mut().blot;
            match OpenOptions::new().read(true).write(true).create(true).open(&path) {
                Ok(f) => Ok(Out::Integer(i64::from(blot.alloc_fd(f)))),
                Err(e) => Ok(Out::Integer(i64::from(blot.set_errno(&e)))),
            }
        },
        "blot_try_lock" | "blot_unlock" => |_, _| Ok(Out::Integer(0)),
        "blot_available_workers" => |_, _| Ok(Out::Integer(1)),
        "blot_runtime_observation" => |_, _| Ok(Out::Integer(0)),
        "blot_runtime_memory_mark" => |_, _| Ok(Out::Nothing),

        // Multi-process / daemon stubs (single-process Wasm execution).
        "blot_fork" | "blot_worker_spawn" => |_, _| Ok(Out::Integer(-38)),
        "blot_persist_open"
        | "blot_check_reply_open"
        | "blot_persist_node"
        | "blot_persist_edge"
        | "blot_persist_publish"
        | "blot_persist_read"
        | "blot_check_reply_append"
        | "blot_wait_success"
        | "blot_request_token" => |_, _| Ok(Out::Integer(0)),
        "blot_persist_claim" => |_, _| Ok(Out::Integer(-95)),
        "blot_persist_size"
        | "blot_check_reply_size"
        | "blot_check_reply_copy"
        | "blot_worker_descriptor"
        | "blot_worker_stop"
        | "blot_detach_session" => |_, _| Ok(Out::Integer(-1)),
        "blot_persist_kill_child"
        | "blot_persist_fail"
        | "blot_persist_close"
        | "blot_check_reply_close"
        | "blot_worker_detach"
        | "blot_null_standard_io"
        | "blot_request_fail_oom"
        | "blot_request_fail" => |_, _| Ok(Out::Nothing),
        "blot_job_exit" => |_, values| Err(Error::new(ProgramExit(integer(values, 0)?))),
        "blot_request_start"
        | "blot_request_begin"
        | "blot_request_input_fd"
        | "blot_request_transport_reply_open"
        | "blot_request_transport_finish"
        | "blot_request_transport_run" => |_, _| Ok(Out::Integer(-38)),
        _ => return None,
    };
    Some(handler)
}

fn blot_copy(caller: &mut Caller<'_, Host>, values: &[Val], elem_bytes: u64) -> Result<Out> {
    let dst = arg_u64(values, 0)?;
    let src = arg_u64(values, 1)?;
    let count = arg_u64(values, 2)?;
    if count == 0 {
        return Ok(Out::Nothing);
    }
    let bytes = count.checked_mul(elem_bytes).ok_or_else(|| failure("blot_copy size overflow"))?;
    let data = memory(caller)?.data_mut(&mut *caller);
    let src_range = span(data.len(), src.into(), bytes.into())?;
    let dst_range = span(data.len(), dst.into(), bytes.into())?;
    data.copy_within(src_range, dst_range.start);
    Ok(Out::Nothing)
}

fn blot_random_u64(caller: &mut Caller<'_, Host>, _: &[Val]) -> Result<Out> {
    let mut buf = [0u8; 8];
    if let Ok(mut f) = File::open("/dev/urandom") {
        if f.read_exact(&mut buf).is_ok() {
            return Ok(Out::Integer(u64::from_le_bytes(buf) as i64));
        }
    }
    let blot = &caller.data().blot;
    let mix = blot.start_instant.elapsed().as_nanos() as u64
        ^ (u64::from(std::process::id()) << 32)
        ^ blot.next_owner.fetch_add(1, Ordering::Relaxed);
    Ok(Out::Integer(mix as i64))
}
