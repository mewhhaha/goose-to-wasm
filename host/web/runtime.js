import { gooseFloat } from "./float.js";
import { utf8Encoder } from "./memory.js";

export class GooseExitError extends Error {
  constructor(code) {
    super("program exit");
    this.name = "GooseExitError";
    this.code = code;
  }
}

export class GooseAbortError extends Error {
  constructor(reason, line) {
    super(`goose runtime error: ${reason} (line ${line})`);
    this.name = "GooseAbortError";
    this.reason = reason;
    this.line = line;
    this.exitCode = 1;
  }
}

export function createGooseImports(mem, io) {
  const print = (text) => io.writeStdout(utf8Encoder.encode(text));

  function format(ptr, value, bits) {
    const text = utf8Encoder.encode(gooseFloat(value, bits));
    mem.readBytes(mem.address(ptr), text.length).set(text);
    // Both address widths use an i32 result for the byte count.
    return text.length;
  }

  return {
    write(ptr, len) {
      io.writeStdout(mem.readBytes(mem.address(ptr), Number(len)).slice());
    },
    print_i64: (value) => print(BigInt.asIntN(64, BigInt(value)).toString()),
    print_u64: (value) => print(BigInt.asUintN(64, BigInt(value)).toString()),
    print_f64: (value) => print(gooseFloat(value, 64)),
    print_f32: (value) => print(gooseFloat(value, 32)),
    format_f64: (ptr, value) => format(ptr, value, 64),
    format_f32: (ptr, value) => format(ptr, value, 32),
    print_bool: (value) => print(value ? "true" : "false"),
    newline: () => print("\n"),
    abort(ptr, len, line) {
      const length = Number(len);
      const reason = length > 0 ? mem.readUtf8(mem.address(ptr), length) : "";
      const error = new GooseAbortError(reason, Number(line));
      io.writeStderr(utf8Encoder.encode(error.message + "\n"));
      throw error;
    },
    exit(code) {
      throw new GooseExitError(Number(code));
    },
  };
}
