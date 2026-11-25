//! goose-wasmtime module.wasm [--timing-json path] [--cache path | --no-cache] [-- program arguments]
//!
//! Runs a direct Goose WebAssembly module with Wasmtime, as
//! scripts/run_wasmtime.py does: stdin is the program's input, stdout its
//! output, stderr its error text, and the exit code its own (1 after a trap,
//! an abort or a host error).

use std::ffi::OsString;
use std::io::{Read, Write};
use std::os::unix::ffi::OsStringExt;
use std::path::PathBuf;
use std::process::exit;

use goose_wasmtime::pytext::normalized_path;
use goose_wasmtime::run::{bytes_of, create_config, os_error_text, path_of, read_file, run_module_entry_with_resource_dir, Outcome, HOSTED_STACK_BYTES};

const USAGE: &str = "usage: goose-wasmtime module.wasm [--entry name] [--timing-json path] [--cache path | --no-cache] [-- program arguments]";

struct Options {
    module: PathBuf,
    entry: Option<String>,
    timing_json: Option<PathBuf>,
    cache: Option<PathBuf>,
    /// What follows `--`: the program's arguments after its own name.
    arguments: Option<Vec<Vec<u8>>>,
}

fn usage_error(message: &str) -> ! {
    eprintln!("{USAGE}\ngoose-wasmtime: error: {message}");
    exit(2)
}

/// The command line, read as the Python runner's argparse reads it: options
/// anywhere before `--`, `--name value` or `--name=value`, and a path spelled
/// as pathlib spells it.
fn options() -> Options {
    let mut own: Vec<Vec<u8>> = std::env::args_os().skip(1).map(OsString::into_vec).collect();
    let arguments = own.iter().position(|argument| argument == b"--").map(|at| {
        let rest = own.split_off(at + 1);
        own.pop();
        rest
    });
    let (mut module, mut entry, mut timing_json, mut cache) = (None, None, None, None);
    let mut no_cache = false;
    let mut unrecognized: Vec<String> = Vec::new();
    let mut own = own.into_iter();
    while let Some(argument) = own.next() {
        if argument.len() < 2 || argument[0] != b'-' {
            if module.is_none() {
                module = Some(argument);
            } else {
                unrecognized.push(String::from_utf8_lossy(&argument).into_owned());
            }
            continue;
        }
        let (name, mut value) = match argument.iter().position(|&byte| byte == b'=') {
            Some(at) if argument.starts_with(b"--") => (&argument[..at], Some(argument[at + 1..].to_vec())),
            _ => (&argument[..], None),
        };
        // A long option may be shortened to any prefix only it has.
        let named = |option: &[u8]| name.len() > 2 && option.starts_with(name);
        if (name == b"-h" || named(b"--help")) && value.is_none() {
            println!("{USAGE}\n\nRun direct Goose WebAssembly with Wasmtime. Stdin is the program's input.\n\n  --entry name        invoke this exported function after _start\n  --timing-json path  write engine timings to this file\n  --cache path        keep the compiled module in this file and reuse it for the same module bytes");
            exit(0);
        }
        if name == b"--no-cache" && value.is_none() {
            no_cache = true;
            continue;
        }
        let slot = if named(b"--entry") {
            &mut entry
        } else if named(b"--timing-json") {
            &mut timing_json
        } else if named(b"--cache") {
            &mut cache
        } else {
            unrecognized.push(String::from_utf8_lossy(&argument).into_owned());
            continue;
        };
        if value.is_none() {
            value = own.next();
        }
        match value {
            Some(value) => *slot = Some(value),
            None => usage_error(&format!("argument {}: expected one argument", String::from_utf8_lossy(name))),
        }
    }
    if no_cache && cache.is_some() {
        usage_error("--cache and --no-cache cannot be used together");
    }
    let Some(module) = module else { usage_error("the following arguments are required: module") };
    if !unrecognized.is_empty() {
        usage_error(&format!("unrecognized arguments: {}", unrecognized.join(" ")));
    }
    let path = |spelling: Vec<u8>| path_of(normalized_path(&spelling));
    let entry = entry.map(|bytes| String::from_utf8_lossy(&bytes).into_owned());
    Options { module: path(module), entry, timing_json: timing_json.map(path), cache: cache.map(path), arguments }
}

fn read_stdin() -> Result<Vec<u8>, String> {
    let mut input = Vec::new();
    std::io::stdin().lock().read_to_end(&mut input).map_err(|error| error.to_string())?;
    Ok(input)
}

fn module_resource_dir(module: &PathBuf) -> Option<Vec<u8>> {
    let resolved = std::fs::canonicalize(module).ok()?;
    let parent = resolved.parent()?;
    let mut bytes = bytes_of(parent);
    if !bytes.ends_with(b"/") {
        bytes.push(b'/');
    }
    Some(bytes)
}

fn run(options: &Options) -> Result<i64, String> {
    let resource_dir = module_resource_dir(&options.module);
    let outcome = if options.arguments.is_none() && options.entry.is_none() {
        let data = read_file(&options.module)?;
        run_module_entry_with_resource_dir(
            &data,
            read_stdin()?,
            vec![b"program".to_vec()],
            &create_config(false),
            options.cache.as_deref(),
            None,
            resource_dir,
        )?
    } else {
        // On a thread whose stack holds the Wasm stack the config allows.
        let hosted = || -> Result<Outcome, String> {
            let data = read_file(&options.module)?;
            let mut program = vec![bytes_of(&options.module)];
            if let Some(arguments) = &options.arguments {
                program.extend(arguments.iter().cloned());
            }
            run_module_entry_with_resource_dir(
                &data,
                read_stdin()?,
                program,
                &create_config(true),
                options.cache.as_deref(),
                options.entry.as_deref(),
                resource_dir.clone(),
            )
        };
        std::thread::scope(|scope| {
            std::thread::Builder::new()
                .stack_size(HOSTED_STACK_BYTES + (64 << 20))
                .spawn_scoped(scope, hosted)
                .map_err(|_| "can't start new thread".to_string())?
                .join()
                .unwrap_or_else(|_| Err("the host thread panicked".to_string()))
        })?
    };
    // A reader that has gone away is not this program's failure.
    let mut stdout = std::io::stdout().lock();
    let _ = stdout.write_all(&outcome.stdout).and_then(|()| stdout.flush());
    if !outcome.stderr.is_empty() {
        let _ = std::io::stderr().lock().write_all((outcome.stderr + "\n").as_bytes());
    }
    if let Some(path) = &options.timing_json {
        std::fs::write(path, outcome.timing.json()).map_err(|error| os_error_text(&error, path))?;
    }
    Ok(outcome.exit_code)
}

fn main() {
    let code = run(&options()).unwrap_or_else(|error| {
        eprintln!("direct Wasmtime host: {error}");
        1
    });
    exit(code as i32)
}
