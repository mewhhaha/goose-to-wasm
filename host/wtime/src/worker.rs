//! Sequential worker requests contain a working directory and a list of argv
//! byte strings. All lengths and the argument count are little-endian u32s.
//! Replies contain a normalized exit code (u32) and two length-prefixed byte
//! strings, stdout followed by stderr. EOF between requests ends the worker.

use super::{CapturedOutput, HostState, LoadedModule, Options, execute_module, path_from_bytes};
use std::io::{self, BufRead, Read, Write};
use std::sync::{Arc, Mutex};

fn read_u32(input: &mut impl Read) -> io::Result<u32> {
    let mut bytes = [0; 4];
    input.read_exact(&mut bytes)?;
    Ok(u32::from_le_bytes(bytes))
}

fn read_bytes(input: &mut impl Read) -> io::Result<Vec<u8>> {
    let len = read_u32(input)? as usize;
    if len > 1024 * 1024 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "worker field exceeds 1 MiB",
        ));
    }
    let mut bytes = vec![0; len];
    input.read_exact(&mut bytes)?;
    Ok(bytes)
}

fn write_bytes(output: &mut impl Write, bytes: &[u8]) -> io::Result<()> {
    let len = u32::try_from(bytes.len())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "worker output exceeds 4 GiB"))?;
    output.write_all(&len.to_le_bytes())?;
    output.write_all(bytes)
}

pub(super) fn serve(opts: &Options, loaded: &LoadedModule) -> io::Result<()> {
    let mut input = io::stdin().lock();
    let mut output = io::stdout().lock();
    while !input.fill_buf()?.is_empty() {
        let cwd = path_from_bytes(&read_bytes(&mut input)?);
        if !cwd.is_absolute() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "worker cwd must be absolute",
            ));
        }
        let argc = read_u32(&mut input)?;
        if argc > 4096 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "too many worker arguments",
            ));
        }
        let mut args = opts.program_args.clone();
        for _ in 0..argc {
            args.push(read_bytes(&mut input)?);
        }

        let mut host = HostState::new(args, loaded.resource_dir.clone());
        host.captured = Some(CapturedOutput::default());
        let state = Arc::new(Mutex::new(host));
        let result = std::env::set_current_dir(&cwd)
            .map_err(|err| format!("failed to enter {}: {err}", cwd.display()))
            .and_then(|()| execute_module(loaded, opts.entry.as_deref(), &state));
        let mut captured = state.lock().unwrap().captured.take().unwrap();
        let code = match result {
            Ok((code, _, _)) => (code & 0xff) as u32,
            Err(err) => {
                writeln!(captured.stderr, "goose-wtime: {err}")?;
                1
            }
        };
        output.write_all(&code.to_le_bytes())?;
        write_bytes(&mut output, &captured.stdout)?;
        write_bytes(&mut output, &captured.stderr)?;
        output.flush()?;
    }
    Ok(())
}
