// Built-in Goose language and goosew CLI guide for humans and coding agents.
// Kept version-matched with driver.goose and plain upstream Goose (v2026.4).

import os;

fn guide_header(version: const u8[:]) {
    write_stdout("# Goose & goosew Cheatsheet — ");
    write_stdout(version);
    write_stdout(" (Goose v2026.4)\n\n");
    write_stdout("Quick, version-matched reference for humans and coding agents.\n");
    write_stdout("Run `goosew guide --list` for topics, or `goosew guide <topic>` for one section.\n");
}

fn guide_usage(version: const u8[:]) {
    write_stdout("goose-to-wasm ");
    write_stdout(version);
    write_stdout(" — Goose language & CLI guide\n\n");
    write_stdout("Usage:\n");
    write_stdout("  goosew guide                Print the complete cheatsheet.\n");
    write_stdout("  goosew guide --cheatsheet   Same as `goosew guide`.\n");
    write_stdout("  goosew guide --list         List available focused topics.\n");
    write_stdout("  goosew guide <topic>        Print one topic section.\n\n");
    guide_list_topics();
}

fn guide_list_topics() {
    write_stdout("Topics:\n");
    write_stdout("  rules     Top rules to avoid common Goose mistakes\n");
    write_stdout("  types     Scalars, casts (as / as!), arrays, slices, and strings\n");
    write_stdout("  structs   Structs, resizable tails, root struct, enums, and match\n");
    write_stdout("  refs      References (&, .=), optionals (T?), lifetimes, and shrink rules\n");
    write_stdout("  control   Functions, UFCS, loops, multiple returns, generics, and modules\n");
    write_stdout("  stdlib    Standard library modules (std, os, json, regex, math, pools)\n");
    write_stdout("  cli       goosew build/check/cache/Wasm64/native C workflows & hosts\n");
}

fn guide_section_rules() {
    write_stdout("\n## 1. Top Rules (Avoid Common Mistakes)\n\n");
    write_stdout("| Don't write | Write instead | Why |\n");
    write_stdout("|---|---|---|\n");
    write_stdout("| `var r: Req = {};` | `var r = Req {};` or `Req { .. }` | Struct literals always name their type; bare `{}` is an empty block |\n");
    write_stdout("| `struct S { a: u8[>..], b: u8[>..] }` | `root struct S { a: u8[>..] = [], b: u8[>..] = [] }` | Multiple resizable fields need `root struct` (ordinary struct: at most 1 resizable tail) |\n");
    write_stdout("| `fn f(s: S)` for `root struct S` | `fn f(s: S&)` | `root struct` owners are local/global only and pass by reference |\n");
    write_stdout("| `os::read_file(p, b)` / `std::sort(a)` | `read_file(p, b)` / `sort(a)` | `os`, `std`, `math`, `vec`, `dictionary`, pools have no `namespace` — call unqualified (`json::`, `regex::`, `csv::`, `binary::`, `base64::`, `ffi::` use namespaces) |\n");
    write_stdout("| Unqualified `Req` / `parse()` from `namespace http;` | `http::Req` / `http::parse()` (or omit `namespace`) | `namespace foo;` requires explicit `foo::` for types & calls from other files (`import` never opens a namespace) |\n");
    write_stdout("| `items[i]` on `struct Item { s: u8[] }` | Fixed `start, end: i64` + flat `buf: u8[>..]` (or `u8[..N]`) | Arrays of variable-size structs cannot be indexed — only iterated (`for x in items`) |\n");
    write_stdout("| `inc(&count)` for `fn inc(n: i64&)` | `inc(count)` | Typed `T&` slots bind lvalues without `&` (`&` warns redundant) |\n");
    write_stdout("| `let r = xs[i]; r = 5;` | `let r .= xs[i]; r = 5;` | Unannotated `=` copies fixed values; `.=` binds a reference |\n");
    write_stdout("| `let s: string = \"hi\";` | `let s: const u8[:] = \"hi\";` / `var b: u8[>..] = [];` | No `string` type: literals are `const u8[:]`; builders are `u8[>..]` |\n");
    write_stdout("| `println(\"x=\", x)` | `print(\"x=\", x)` | Builtin is `print(...)` (no auto spaces); `format(buf, ...)` appends to `u8[>..]` |\n");
    write_stdout("| `let n = byte as i64;` (`byte: u8`) | `let n: i64 = byte;` | Safe widening (`u8->i64`, `i32->i64`, int->float) is implicit (`as` warns redundant) |\n");
    write_stdout("| `var r: i64& = null;` | `var r: i64? = null;` | `T&` is never null; nullable references use `T?` |\n");
    write_stdout("| `match e { V &x => ... }` on fixed `E` | `var xs: E..[>..] = [];` then `V &x =>` | Fixed enum `E` binds payload by value only; variable mode `E..` allows interior `&` |\n");
}

fn guide_section_types() {
    write_stdout("\n## 2. Scalars, Casts, Arrays, Slices & Strings\n\n");
    write_stdout("- **Scalars:** `i8 i16 i32 i64`, `u8 u16 u32 u64`, `f32 f64`, `bool`, `varint`. Unannotated integer literals default to `i64`; floats to `f64`.\n");
    write_stdout("- **Bindings:** `let` (immutable binding), `var` (mutable variable), `const` (read-only view/contents).\n");
    write_stdout("- **Conversions:** Widening (`u8->i64`, `i32->i64`, `f32->f64`, any int->float) is implicit. Narrowing, signedness flips, and float->int use `x as T` (range-checked in `--debug`) or `x as! T` (intentional truncation/wrap, unchecked).\n");
    write_stdout("- **The array family** (all inline, no heap allocator):\n");
    write_stdout("  - `T[k]` — fixed length `k` (compile-time constant; value-copied, memberwise arithmetic on numeric structs/arrays).\n");
    write_stdout("  - `T[]` / `T[varint]` — variable length, sized once at construction, frozen after.\n");
    write_stdout("  - `T[..k]` / `T[..]` — inline limited capacity (fixed `k` or runtime `[..cap]`); grows/shrinks up to `.cap`.\n");
    write_stdout("  - `T[>..]` — **grow-only resizable** (default workhorse: builders, arenas, pools; refs survive growth).\n");
    write_stdout("  - `T[>..<]` — **grow-shrink resizable** (stacks, queues; refs live only in locals).\n");
    write_stdout("- **Array members:** `.len`, `.cap`, `.push(v) -> T&`, `.append(slice_or_lit)`, `.pop() -> T`, `.pop_n(n)`, `.resize(n, v)`, `.clear()`, `.index_of(ref)`, `.range_index(slice)`, `dst.move_from(src)`.\n");
    write_stdout("- **Slices (`T[:]`, `const T[:]`):** Non-owning view `a[lo..hi]`, `a[..hi]`, `a[lo..]`, `a[..]` (full view). `==` / `!=` compare elements structurally across array kinds and slices.\n");
    write_stdout("- **Strings:** Byte arrays/slices (`u8`). Literals are `const u8[:]` (read-only). Build text in `var s: u8[>..] = []; s.append(\"hi\"); format(s, \" \", n);` or write stdout with `print(...)` / `write_stdout(s)`.\n");
}

fn guide_section_structs() {
    write_stdout("\n## 3. Structs, `root struct`, Enums & `match`\n\n");
    write_stdout("```goose\n");
    write_stdout("struct Point { x: f64 = 0.0, y: f64 = 0.0 }\n");
    write_stdout("struct Stack { name: u8[..16] = \"\", items: i64[>..<] = [] }  // 1 resizable tail OK\n\n");
    write_stdout("// Multiple resizable fields: use `root struct` (passed by reference `Store&`)\n");
    write_stdout("root struct Store {\n");
    write_stdout("    ids: i64[>..] = [],\n");
    write_stdout("    names: u8[>..] = [],\n");
    write_stdout("}\n\n");
    write_stdout("enum Shape { Circle { r: f64 }, Rect { w: f64, h: f64 }, Dot }\n\n");
    write_stdout("fn area(s: Shape) -> f64 {\n");
    write_stdout("    match s {\n");
    write_stdout("        Circle c => 3.14159265 * c.r * c.r,\n");
    write_stdout("        Rect r => r.w * r.h,\n");
    write_stdout("        Dot => 0.0,\n");
    write_stdout("    }\n");
    write_stdout("}\n");
    write_stdout("```\n\n");
    write_stdout("- Construct with `Point { x: 1.0, y: 2.0 }`, `Point {}` (when all fields have defaults), or `Point { x: 1.0, .. }`.\n");
    write_stdout("- `root struct` owners live only as locals or globals; they cannot be copied, returned by value, or nested in structs/arrays. Pass them as `Store&` or `const Store&`.\n");
    write_stdout("- **Indexable arrays need fixed-size elements:** An array of variable-size structs (holding `u8[]`, `u8[..]`, or `E..`) can only be iterated (`for x in items`), not indexed (`items[i]`). For indexable records with text, use inline `u8[..N]` or store `start, end: i64` spans beside a flat `u8[>..]` buffer in a `root struct`.\n");
    write_stdout("- Enum literals: `Shape.Circle { r: 2.0 }`, `Shape.Dot` (generic: `Opt<i64>.Some { v: 1 }`).\n");
    write_stdout("- **Fixed mode (`Shape`)** is indexable and allows replacing variants in place (`a[i] = Shape.Dot;`). **Variable mode (`Shape..`)** packs each variant to its exact size and permits mutable payload references (`Rect &r => { r.w += 1.0; }`).\n");
    write_stdout("- Integer `match` supports literals, constants, half-open ranges `1..4`, lists `7, 10..12`, and requires `_`.\n");
}

fn guide_section_refs() {
    write_stdout("\n## 4. References, Optionals, Lifetimes & Memory Model\n\n");
    write_stdout("- **No GC, no heap allocator, no lifetime annotations:** Each resizable array (`T[>..]`, `T[>..<]`) owns a contiguous data stack whose elements never relocate, so references stay valid across `.push` / `.append`.\n");
    write_stdout("- **Transparent references (`T&`, `const T&`):** Auto-dereference on read, write, and field access.\n");
    write_stdout("  - Typed parameter/field/local: pass lvalue directly without `&` (`fn inc(n: i64&)`, call `inc(x)`).\n");
    write_stdout("  - Inferred local: `let r .= xs[i];` or `let r = &xs[i];` keeps a reference; `let v = r;` copies fixed-size targets.\n");
    write_stdout("  - Reference identity: `a .== b`, `a .!= b`; rebind a `var` ref with `r .= other;` (`r = v;` assigns the target!).\n");
    write_stdout("- **Optionals (`T?`):** Nullable reference (`null` or a `T&`). Test with `if r != null { ... }` or `if let v .= opt { ... }`.\n");
    write_stdout("- **Shrink rule:** You may `.pop()`, `.clear()`, `.resize()` (smaller), or reassign an array only when no live reference/slice points into it. Grow-only `T[>..]` can still shrink at points where the compiler proves nothing borrows it.\n");
    write_stdout("- **Relative references:** `Node&<u32>` (self-relative) and `Node&<u32 in pool>` (pool-relative) store 32-bit offsets for compact trees/graphs in a single array.\n");
    write_stdout("- **Index types & `checkfree`:** `u32 in arr` / `u32 upto arr` move bounds checks to construction; `checkfree fn` asks the compiler to prove zero runtime bounds checks remain.\n");
}

fn guide_section_control() {
    write_stdout("\n## 5. Functions, Control Flow, Generics & Modules\n\n");
    write_stdout("```goose\n");
    write_stdout("namespace mathx;                     // file mathx.goose; imported with `import mathx;`\n");
    write_stdout("import os;\n\n");
    write_stdout("fn divmod(a: i64, b: i64) -> i64, i64 { return a / b, a % b; }\n\n");
    write_stdout("fn sum_to(n: i64) -> i64 {\n");
    write_stdout("    var total = 0;\n");
    write_stdout("    for i in 0..n { total += i; }    // or `for i in n`, `for v in xs`, `for v, i in xs`\n");
    write_stdout("    return total;\n");
    write_stdout("}\n");
    write_stdout("```\n\n");
    write_stdout("- **Expressions:** `if c { a } else { b }` and `match` are expressions. A block's final expression (no trailing `;`) is its value.\n");
    write_stdout("- **Multiple returns:** `fn f() -> i64, bool { return 42, true; }` and `let v, ok = f();`.\n");
    write_stdout("- **UFCS:** `a.foo(b)` resolves to `foo(a, b)` for both builtins and user/stdlib functions.\n");
    write_stdout("- **Loops & non-local returns:** `while cond { ... }`, `loop { ... break; }`, `for x in xs`, `for x, i in xs`, `for i in lo..hi`, `for i in n`. Use `return val from fn_name;` inside nested/callback functions.\n");
    write_stdout("- **Generics & `const for`:** `fn swap<T>(a: T&, b: T&)`, `struct Pair<T> { a: T, b: T }`, compile-time `const for` over fields/variants/types.\n");
    write_stdout("- **Modules & namespaces:** `import foo;` only loads `foo.goose` — it creates no namespace and never opens one. If a file declares `namespace foo;`, other files must qualify both types and functions as `foo::Name` (only UFCS `x.f()` on a `foo::T` finds `foo::f`). Files without `namespace` (like `std`, `os`, `math`, `vec`, `dictionary`) declare into the global namespace and are used unqualified (never `os::...`). Use `::name` (e.g. `fn ::main()`) for global scope. Avoid circular imports.\n");
}

fn guide_section_stdlib() {
    write_stdout("\n## 6. Standard Library (`--stdlib`)\n\n");
    write_stdout("Stdlib modules are checked lazily (only reached functions are checked).\n\n");
    write_stdout("**Unqualified modules** (no `namespace` — call directly without a `mod::` prefix):\n");
    write_stdout("- `import std;` — `min`, `max`, `clamp`, `abs`, `rem`, `div_euclid`, `swap`, `hash`, `rng`, `sort`, `find`, `position`, `contains`, `split`, `each_utf8`, `push_utf8`, `parse_i64`, `parse_f64`.\n");
    write_stdout("- `import os;` — `read_file(path, out)`, `write_file(path, data)`, `write_file_atomic`, `append_file`, `file_exists`, `delete_file`, `rename_file`, `make_dir`, `is_dir`, `list_dir`, `read_stdin(out)`, `read_line(out)`, `write_stdout(s)`, `write_stderr(s)`, `flush_stdout()`, `arg_count()`, `arg(i, out)`, `args()`, `env(name, out)`, `time_ns()`, `clock_ns()`, `sleep_ms(ms)`, `random_seed()`.\n");
    write_stdout("- `import dictionary;` — `dictionary<K, V>` hash map (`put`, `get`, `has`, `remove`, `clear`).\n");
    write_stdout("- `import slot_pool;` / `import slice_pool;` — reusable slot & byte-slice pools with O(1) free.\n");
    write_stdout("- `import math;` / `import vec;` — trig, `sqrt`, `pow`, `floor`/`ceil`, `vec2`/`vec3`/`vec4`, `dot`, `cross`, `normalize`.\n\n");
    write_stdout("**Namespaced modules** (declare `namespace <name>;` — qualify types & functions as `mod::Name`):\n");
    write_stdout("- `import json;` — `json::Node`, `json::parse(text, doc, decoded) -> Node?, u8[>..]`, `json::member(n, key)`, `json::each`, `json::as_i64` / `as_f64` / `as_bool` / `as_string`, `json::format_string(out, s)`, `json::format_int`, `json::format_bool`.\n");
    write_stdout("- `import regex;` / `import csv;` / `import binary;` / `import base64;` / `import exception;` / `import ffi;`.\n");
    write_stdout("- Browser apps (`--stdlib stdlib-web --wasm-bundled-host`): `gfx`, `audio`, `physics`, `ui`.\n");
}

fn guide_section_cli() {
    write_stdout("\n## 7. `goosew` CLI Workflows\n\n");
    write_stdout("```sh\n");
    write_stdout("# 1. Fast type & lifetime check (human or JSON diagnostics for agents)\n");
    write_stdout("goosew --check src/main.goose\n");
    write_stdout("goosew --check --error-format=json src/main.goose\n\n");
    write_stdout("# 2. Rapid dev build: Direct WebAssembly (milliseconds, no C compiler)\n");
    write_stdout("goosew src/main.goose --cache-dir build/cache -O0 -o build/app.wasm\n");
    write_stdout("goosew src/main.goose --cache-dir build/cache -O2 -o build/app.wasm\n\n");
    write_stdout("# 3. Large codebases: Direct Wasm64 + parallel workers + incremental .life cache\n");
    write_stdout("goosew src/main.goose --target wasm-direct --wasm-memory64 --wasm-max-pages 65536 \\\n");
    write_stdout("  --cache-dir build/cache --jobs auto -O0 -o build/app.wasm\n\n");
    write_stdout("# 4. Ship native C executable or C host library\n");
    write_stdout("goosew src/main.goose --target native -O2 --run\n");
    write_stdout("goosew --emit-runtime goose_runtime.c\n");
    write_stdout("goosew src/lib.goose --header app.h -O2 -o app.c\n");
    write_stdout("goosew src/lib.goose --shared -O2 -o libapp.so\n");
    write_stdout("```\n\n");
    write_stdout("- **Fast Wasm execution:** `goose-wasmtime --fast-jit build/app.wasm -- args...` (Wasmtime Winch baseline JIT), `goose-wtime build/app.wasm` (safe-Rust `wtime`), or `node scripts/run_wasm.mjs build/app.wasm`.\n");
    write_stdout("- **Useful flags:** `--stdlib DIR`, `--library`, `--reachable-program`, `--debug` (line-numbered range/overflow/tag checks), `--wasm-stats FILE`, `--color auto|always|never`, `--version`, `goosew guide <topic>`.\n");
}

fn driver_guide(version: const u8[:], arguments: u8[:][:]) -> i64 {
    if arguments.len == 2 {
        guide_header(version);
        guide_section_rules();
        guide_section_types();
        guide_section_structs();
        guide_section_refs();
        guide_section_control();
        guide_section_stdlib();
        guide_section_cli();
        return 0;
    }
    if arguments.len > 3 {
        write_stderr("goosew guide: expected at most one topic or flag (run `goosew guide --help`)\n");
        return 2;
    }
    let arg = arguments[2];
    if arg == "--help" || arg == "-h" || arg == "help" {
        guide_usage(version);
        return 0;
    }
    if arg == "--list" || arg == "list" || arg == "topics" {
        guide_list_topics();
        return 0;
    }
    if arg == "--cheatsheet" || arg == "cheatsheet" || arg == "all" {
        guide_header(version);
        guide_section_rules();
        guide_section_types();
        guide_section_structs();
        guide_section_refs();
        guide_section_control();
        guide_section_stdlib();
        guide_section_cli();
        return 0;
    }
    if arg == "rules" { guide_section_rules(); return 0; }
    if arg == "types" { guide_section_types(); return 0; }
    if arg == "structs" { guide_section_structs(); return 0; }
    if arg == "refs" { guide_section_refs(); return 0; }
    if arg == "control" { guide_section_control(); return 0; }
    if arg == "stdlib" { guide_section_stdlib(); return 0; }
    if arg == "cli" { guide_section_cli(); return 0; }
    write_stderr("goosew guide: unknown topic '");
    write_stderr(arg);
    write_stderr("' (run `goosew guide --list` for available topics)\n");
    return 2;
}
