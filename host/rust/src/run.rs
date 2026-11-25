//! Running one module: the engine configuration, the compiled-module cache,
//! instantiation, `_start`, and what the run left behind. Follows `run_module`
//! in scripts/run_wasmtime.py step for step, so that the timing covers the
//! same work and a failure at any step reads the same.

use std::ffi::OsString;
use std::fs;
use std::io;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::time::Instant;

use sha2::{Digest, Sha256};
use wasmtime::{Config, Engine, Error, Extern, Func, Instance, Linker, Module, OptLevel, Result, Store, Val};

use crate::host::{define_imports, failure, Host, HostFailure, ProgramExit};
use crate::pytext::{normalized_path, repr_str};

/// A program given arguments (the compiler compiled to Wasm among them) may
/// recurse deeply and may hold a 64-bit memory far larger than what it
/// touches: it gets this much stack, and this much address space reserved up
/// front so that growing the memory never moves it.
pub const HOSTED_STACK_BYTES: usize = 512 << 20;
pub const HOSTED_RESERVATION_BYTES: u64 = 1 << 40;

/// The Wasmtime this host is built with, read from Cargo.lock by build.rs.
pub const WASMTIME_VERSION: &str = env!("GOOSE_WASMTIME_VERSION");

pub fn create_config(hosted: bool) -> Config {
    let mut config = Config::new();
    config.cranelift_opt_level(OptLevel::Speed);
    config.wasm_memory64(true);
    config.wasm_tail_call(true);
    config.wasm_exceptions(true);
    config.wasm_simd(true);
    config.wasm_bulk_memory(true);
    config.wasm_multi_value(true);
    // Threads are off, as the Python runner sets them: this build of the
    // crate leaves the `threads` feature out, which removes the proposal.
    config.wasm_relaxed_simd(false);
    if hosted {
        // Wasmtime refuses a Wasm stack larger than its fiber stack size.
        config.async_stack_size(HOSTED_STACK_BYTES + (1 << 20));
        config.max_wasm_stack(HOSTED_STACK_BYTES);
        config.memory_reservation(HOSTED_RESERVATION_BYTES);
    }
    config
}

pub struct Timing {
    pub compile_instantiate_ns: u128,
    pub start_function_ns: u128,
    pub engine_total_ns: u128,
}

impl Timing {
    /// The JSON the Python runner writes, key for key.
    pub fn json(&self) -> String {
        format!(
            "{{\n  \"engine\": \"Wasmtime\",\n  \"wasmtime\": \"{WASMTIME_VERSION}\",\n  \"optimization\": \"cranelift speed\",\n  \
             \"compile_instantiate_ns\": {},\n  \"start_function_ns\": {},\n  \"engine_total_ns\": {}\n}}\n",
            self.compile_instantiate_ns, self.start_function_ns, self.engine_total_ns
        )
    }
}

pub struct Outcome {
    pub stdout: Vec<u8>,
    /// What the program wrote to stderr, then the error if the run failed.
    pub stderr: String,
    pub exit_code: i64,
    pub timing: Timing,
}

/// Runs a module on `stdin`. `arguments` are what the program's os.arg sees,
/// the program first. `cache` is a file this host keeps the compiled module
/// in, beside the SHA-256 of the module it was compiled from.
///
/// An `Err` is a failure of the host itself after the run, which the Python
/// runner does not survive either: the region profile could not be written.
pub fn run_module(
    data: &[u8],
    stdin: Vec<u8>,
    arguments: Vec<Vec<u8>>,
    config: &Config,
    cache: Option<&Path>,
) -> std::result::Result<Outcome, String> {
    run_module_entry(data, stdin, arguments, config, cache, None)
}

pub fn run_module_entry(
    data: &[u8],
    stdin: Vec<u8>,
    arguments: Vec<Vec<u8>>,
    config: &Config,
    cache: Option<&Path>,
    entry: Option<&str>,
) -> std::result::Result<Outcome, String> {
    run_module_entry_with_resource_dir(data, stdin, arguments, config, cache, entry, None)
}

pub fn run_module_entry_with_resource_dir(
    data: &[u8],
    stdin: Vec<u8>,
    arguments: Vec<Vec<u8>>,
    config: &Config,
    cache: Option<&Path>,
    entry: Option<&str>,
    resource_dir: Option<Vec<u8>>,
) -> std::result::Result<Outcome, String> {
    let mut initial = Host::new(stdin, arguments);
    initial.resource_dir = resource_dir;
    let mut host = Some(initial);
    let mut store: Option<Store<Host>> = None;
    let mut instance: Option<Instance> = None;
    let started = Instant::now();
    let mut instantiated = started;
    let mut return_code: i64 = 0;
    let result = (|| -> Result<()> {
        let engine = Engine::new(config)?;
        let store = store.insert(Store::new(&engine, host.take().expect("the host state is unused")));
        let module = load_module(&engine, data, cache)?;
        let mut linker = Linker::new(&engine);
        define_imports(&mut linker, &module)?;
        let instance = *instance.insert(linker.instantiate(&mut *store, &module)?);
        let export = |store: &mut Store<Host>, name: &str| match instance.get_export(&mut *store, name) {
            Some(Extern::Func(function)) => Ok(function),
            // What Python makes of calling another kind of export, and of a
            // missing one.
            Some(Extern::Global(_)) => Err(failure("'Global' object is not callable")),
            Some(Extern::Memory(_)) => Err(failure("'Memory' object is not callable")),
            Some(Extern::Table(_)) => Err(failure("'Table' object is not callable")),
            _ => Err(failure(format!("'{name}'"))),
        };
        if instance.get_export(&mut *store, "__set_stack_limits").is_some() {
            let initialize = export(store, "emscripten_stack_init")?;
            call(store, initialize, &[])?;
            let (set, base, end) = (
                export(store, "__set_stack_limits")?,
                export(store, "emscripten_stack_get_base")?,
                export(store, "emscripten_stack_get_end")?,
            );
            let limits = [call(store, base, &[])?, call(store, end, &[])?].concat();
            call(store, set, &limits)?;
        }
        instantiated = Instant::now();
        if let Some(entry_name) = entry {
            if let Some(Extern::Func(start)) = instance.get_export(&mut *store, "_start") {
                call(store, start, &[])?;
            }
            let func = export(store, entry_name)?;
            let values = call(store, func, &[])?;
            return_code = match values.first() {
                Some(Val::I32(code)) => i64::from(*code),
                Some(Val::I64(code)) => *code,
                _ => 0,
            };
        } else {
            let start = export(store, "_start")?;
            call(store, start, &[])?;
        }
        Ok(())
    })();
    let ended = Instant::now();
    let (exit_code, error) = match result {
        Ok(()) => (return_code, String::new()),
        Err(error) => describe(&error),
    };
    let (mut stdout, mut errors) = (Vec::new(), Vec::new());
    if let Some(store) = &mut store {
        if let Some(instance) = instance {
            if let Some(line) = region_stats(store, instance)? {
                store.data_mut().err.extend_from_slice(line.as_bytes());
            }
        }
        stdout = std::mem::take(&mut store.data_mut().out);
        errors = std::mem::take(&mut store.data_mut().err);
    }
    Ok(Outcome {
        stdout,
        stderr: String::from_utf8_lossy(&errors).into_owned() + &error,
        exit_code,
        timing: Timing {
            compile_instantiate_ns: (instantiated - started).as_nanos(),
            start_function_ns: (ended - instantiated).as_nanos(),
            engine_total_ns: (ended - started).as_nanos(),
        },
    })
}

/// The exit code and error text of a failed run: the program's own exit, a
/// host failure by its words, anything else as Wasmtime describes it (the
/// text its C interface gives the Python runner).
fn describe(error: &Error) -> (i64, String) {
    if let Some(ProgramExit(code)) = error.downcast_ref() {
        (*code, String::new())
    } else if let Some(HostFailure(text)) = error.downcast_ref() {
        (1, text.clone())
    } else {
        (1, format!("{error:?}"))
    }
}

fn call(store: &mut Store<Host>, function: Func, arguments: &[Val]) -> Result<Vec<Val>> {
    let mut results: Vec<Val> = function.ty(&*store).results().map(|_| Val::I32(0)).collect();
    function.call(&mut *store, arguments, &mut results)?;
    Ok(results)
}

fn load_module(engine: &Engine, data: &[u8], cache: Option<&Path>) -> Result<Module> {
    let Some(cache) = cache else {
        return Module::from_binary(engine, data);
    };
    let digest: String = Sha256::digest(data).iter().map(|byte| format!("{byte:02x}")).collect();
    let mut stamp = cache.as_os_str().to_owned();
    stamp.push(".sha256");
    let stamp = PathBuf::from(stamp);
    if cache.is_file() && stamp.is_file() && fs::read_to_string(&stamp).is_ok_and(|text| text.trim() == digest) {
        // SAFETY: the file is this host's own output for these module bytes,
        // as the stamp beside it says; Wasmtime refuses one that another
        // build or configuration wrote, and it is then compiled again.
        if let Ok(module) = unsafe { Module::deserialize_file(engine, cache) } {
            return Ok(module);
        }
    }
    let module = Module::from_binary(engine, data)?;
    replace_file(cache, &module.serialize()?)?;
    replace_file(&stamp, format!("{digest}\n").as_bytes())?;
    Ok(module)
}

/// Writes a file whole or not at all: beside it, then renamed over it, so a
/// host that is reading the old one keeps it and none sees half of the new.
fn replace_file(path: &Path, contents: &[u8]) -> Result<()> {
    let mut beside = path.as_os_str().to_owned();
    beside.push(format!(".{}.tmp", std::process::id()));
    let beside = PathBuf::from(beside);
    fs::write(&beside, contents).and_then(|()| fs::rename(&beside, path)).map_err(|error| {
        let _ = fs::remove_file(&beside);
        failure(os_error_text(&error, path))
    })
}

/// An operating system error on a path as Python words it.
pub fn os_error_text(error: &io::Error, path: &Path) -> String {
    let path = repr_str(&path.to_string_lossy());
    match error.raw_os_error() {
        Some(code) => {
            let text = error.to_string();
            let reason = text.strip_suffix(&format!(" (os error {code})")).unwrap_or(&text);
            format!("[Errno {code}] {reason}: {path}")
        }
        None => format!("{error}: {path}"),
    }
}

/// A module built with --wasm-region-stats exports its region table and
/// keeps each region's high-water mark. GOOSE_REGION_STATS=1 gives a line
/// about the largest; GOOSE_REGION_PROFILE=path writes them all as
/// "index bytes" lines, what --wasm-region-profile reads. Nothing for a
/// module without the exports.
fn region_stats(store: &mut Store<Host>, instance: Instance) -> std::result::Result<Option<String>, String> {
    let set = |name: &str| std::env::var_os(name).filter(|value| !value.is_empty());
    let (stats, profile) = (set("GOOSE_REGION_STATS").is_some(), set("GOOSE_REGION_PROFILE"));
    if !stats && profile.is_none() {
        return Ok(None);
    }
    let mut global = |name: &str| instance.get_global(&mut *store, name).map(|global| global.get(&mut *store));
    // The table is count + 1 words, each as wide as an address: where each
    // region starts, and after the last where memory ends.
    let (table, size): (i128, i128) = match global("goose.region_table") {
        Some(Val::I64(table)) => ((table as u64).into(), 8),
        Some(Val::I32(table)) => ((table as u32).into(), 4),
        _ => return Ok(None),
    };
    let count: i64 = match global("goose.region_count") {
        Some(Val::I32(count)) => count.into(),
        Some(Val::I64(count)) => count,
        _ => return Ok(None),
    };
    let Some(memory) = instance.get_memory(&mut *store, "memory") else {
        return Ok(None);
    };
    let data = memory.data(&*store);
    let length = data.len() as i128;
    let read = |at: i128| -> Option<i128> {
        if at + size > length {
            return Some(0);
        }
        let at = usize::try_from(at).ok()?;
        let mut word = [0u8; 8];
        word[..size as usize].copy_from_slice(&data[at..at + size as usize]);
        Some(u64::from_le_bytes(word).into())
    };
    let used = || -> Option<Vec<(i128, i64, i128)>> {
        let mut used = Vec::new();
        for region in 0..count {
            // A region ends in its cursor, its start and its high-water mark.
            let end = read(table + (i128::from(region) + 1) * size)?;
            let (base, peak) = (read(end - 2 * size)?, read(end - size)?);
            if peak > base {
                used.push((peak - base, region, end - read(table + i128::from(region) * size)?));
            }
        }
        Some(used)
    };
    let Some(mut used) = used() else {
        return Ok(None);
    };
    if let Some(profile) = profile {
        let lines: String = used.iter().map(|(held, region, _)| format!("{region} {held}\n")).collect();
        let path = path_of(normalized_path(profile.as_bytes()));
        fs::write(&path, lines).map_err(|error| os_error_text(&error, &path))?;
    }
    used.sort_by(|a, b| b.cmp(a));
    let most: Vec<String> = used.iter().take(12).map(|(held, region, room)| format!("#{region}:{held}/{room}")).collect();
    Ok(stats.then(|| format!("regions: {count}, memory {length}; most used {}\n", most.join(" "))))
}

/// Reads a whole file, or says why not as Python words it.
pub fn read_file(path: &Path) -> std::result::Result<Vec<u8>, String> {
    fs::read(path).map_err(|error| os_error_text(&error, path))
}

pub fn path_of(bytes: Vec<u8>) -> PathBuf {
    PathBuf::from(OsString::from_vec(bytes))
}

pub fn bytes_of(path: &Path) -> Vec<u8> {
    path.as_os_str().as_bytes().to_vec()
}
