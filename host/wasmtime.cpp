// The direct Goose ABI and the standalone C backend's memory64 WASI subset.
#include <wasmtime.h>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <limits>
#include <memory>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

using std::string;
using std::string_view;
template <auto Delete> struct Deleter {
    template <class T> void operator()(T *value) const { Delete(value); }
};
template <class T, auto Delete> using Owned = std::unique_ptr<T, Deleter<Delete>>;
struct Bytes {
    wasm_byte_vec_t value{};
    ~Bytes() { wasm_byte_vec_delete(&value); }
};
struct Imports {
    wasm_importtype_vec_t value{};
    ~Imports() { wasm_importtype_vec_delete(&value); }
};
struct External {
    wasmtime_extern_t value{};
    bool found = false;
    ~External() { if (found) wasmtime_extern_delete(&value); }
};
struct StackBounds {
    wasmtime_val_t values[2]{};
    ~StackBounds() { for (auto &value : values) wasmtime_val_unroot(&value); }
};
struct HostError : std::exception {
    string message;
    explicit HostError(string text) : message(std::move(text)) {}
    const char *what() const noexcept override { return message.c_str(); }
};
static string error_text(const std::exception &error) {
    if (auto host = dynamic_cast<const HostError *>(&error)) return host->message;
    return error.what();
}
[[noreturn]] static void fail(const string &message) { throw HostError(message); }
static void check(wasmtime_error_t *raw, wasm_trap_t *trap = nullptr) {
    Owned<wasmtime_error_t, wasmtime_error_delete> error(raw);
    Owned<wasm_trap_t, wasm_trap_delete> trapped(trap);
    if (!error && !trapped) return;
    Bytes text;
    if (error) wasmtime_error_message(error.get(), &text.value);
    else wasm_trap_message(trapped.get(), &text.value);
    string message(text.value.data, text.value.size);
    if (!message.empty() && message.back() == '\0') message.pop_back();
    fail(message);
}
static uint64_t monotonic_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
static string read_all(FILE *file) {
    string text;
    char buffer[65536];
    while (size_t count = std::fread(buffer, 1, sizeof buffer, file)) text.append(buffer, count);
    if (std::ferror(file)) fail("cannot read input");
    return text;
}
static string read_file(const string &path) {
    Owned<FILE, std::fclose> file(std::fopen(path.c_str(), "rb"));
    if (!file) fail("cannot open " + path);
    return read_all(file.get());
}
static void write_file(const string &path, string_view bytes) {
    Owned<FILE, std::fclose> file(std::fopen(path.c_str(), "wb"));
    if (!file) fail("cannot write " + path);
    if (std::fwrite(bytes.data(), 1, bytes.size(), file.get()) != bytes.size()) fail("cannot write " + path);
    if (std::fclose(file.release())) fail("cannot write " + path);
}
template <class T> static string goose_float(T value) {
    if (std::isnan(value)) return "nan";
    if (std::isinf(value)) {
        if (std::signbit(value)) return "-inf";
        return "inf";
    }
    if (value == 0) {
        if (std::signbit(value)) return "-0.0";
        return "0.0";
    }
    char buffer[64];
    auto converted = std::to_chars(buffer, buffer + sizeof buffer, value, std::chars_format::scientific);
    if (converted.ec != std::errc{}) fail("cannot format floating point value");
    string scientific(buffer, converted.ptr), digits;
    auto marker = scientific.find('e');
    int exponent = std::stoi(scientific.substr(marker + 1));
    for (size_t i = 0; i < marker; ++i)
        if (scientific[i] != '-' && scientific[i] != '.') digits += scientific[i];
    if (exponent < -4 || exponent >= std::max(15, int(digits.size()))) return scientific;
    string text;
    if (std::signbit(value)) text += '-';
    if (exponent < 0) {
        text += "0.";
        text.append(-exponent - 1, '0');
        return text + digits;
    }
    size_t point = size_t(exponent) + 1;
    text += digits.substr(0, point);
    if (point > digits.size()) text.append(point - digits.size(), '0');
    text += '.';
    if (point < digits.size()) text += digits.substr(point);
    else text += '0';
    return text;
}
// Match Python's replacement decoding for diagnostic strings, including a
// truncated sequence consuming its valid prefix as one replacement character.
static string utf8_replacement(string_view bytes) {
    string text;
    for (size_t i = 0; i < bytes.size();) {
        auto c = static_cast<unsigned char>(bytes[i]);
        size_t width = 0;
        if (c < 0x80) width = 1;
        else if (c >= 0xc2 && c <= 0xdf) width = 2;
        else if (c >= 0xe0 && c <= 0xef) width = 3;
        else if (c >= 0xf0 && c <= 0xf4) width = 4;
        size_t valid = 1;
        while (valid < width && i + valid < bytes.size()) {
            auto next = static_cast<unsigned char>(bytes[i + valid]);
            if (next < 0x80 || next > 0xbf) break;
            if (valid == 1 && ((c == 0xe0 && next < 0xa0) || (c == 0xed && next > 0x9f) ||
                              (c == 0xf0 && next < 0x90) || (c == 0xf4 && next > 0x8f))) break;
            ++valid;
        }
        if (width && valid == width) text.append(bytes.substr(i, width));
        else text += "\xef\xbf\xbd";
        i += valid;
    }
    return text;
}
struct State {
    string input, output, errors, failure, callback_error;
    size_t input_position = 0, token_position = 0;
    int64_t sink = 0;
    bool exited = false;
    int32_t exit_code = 0;
    string token() {
        auto space = [](char c) { return string_view(" \t\n\r\f\v").find(c) != string_view::npos; };
        while (token_position < input.size() && space(input[token_position])) ++token_position;
        size_t start = token_position;
        while (token_position < input.size() && !space(input[token_position])) ++token_position;
        if (start == token_position) fail("host input is exhausted");
        return input.substr(start, token_position - start);
    }
};
struct Memory {
    wasmtime_context_t *context;
    External item;
    explicit Memory(wasmtime_caller_t *caller) : context(wasmtime_caller_context(caller)) {
        item.found = wasmtime_caller_export_get(caller, "memory", 6, &item.value);
        if (!item.found || item.value.kind != WASMTIME_EXTERN_MEMORY) fail("module does not export memory");
    }
    uint8_t *range(uint64_t pointer, uint64_t length) {
        size_t size = wasmtime_memory_data_size(context, &item.value.of.memory);
        if (pointer > size || length > size - pointer) fail("host write is outside exported memory");
        auto data = wasmtime_memory_data(context, &item.value.of.memory);
        if (!pointer) return data;
        return data + size_t(pointer);
    }
    string bytes(uint64_t pointer, uint64_t length) {
        auto data = range(pointer, length);
        if (!length) return {};
        return string(reinterpret_cast<char *>(data), size_t(length));
    }
    void write(uint64_t pointer, string_view bytes) {
        auto data = range(pointer, bytes.size());
        if (!bytes.empty()) std::memcpy(data, bytes.data(), bytes.size());
    }
    void write64(uint64_t pointer, uint64_t value) {
        auto data = range(pointer, 8);
        for (unsigned i = 0; i < 8; ++i) data[i] = uint8_t(value >> (8 * i));
    }
    std::vector<std::pair<uint64_t, uint64_t>> iovecs(uint64_t pointer, uint64_t count) {
        if (count > UINT64_MAX / 16) fail("host write is outside exported memory");
        auto data = range(pointer, count * 16);
        std::vector<std::pair<uint64_t, uint64_t>> result;
        for (uint64_t i = 0; i < count; ++i) {
            uint64_t start = 0, size = 0;
            for (unsigned j = 0; j < 8; ++j) {
                start |= uint64_t(data[i * 16 + j]) << (8 * j);
                size |= uint64_t(data[i * 16 + 8 + j]) << (8 * j);
            }
            result.emplace_back(start, size);
        }
        return result;
    }
};
enum class Op { Write, I64, U64, F64, F32, Bool, Newline, Abort, Exit, Input, InputF64,
                Clock, Barrier, Sink, Growth, ArgsSizes, Args, EnvSizes, Env, Time, FdWrite, FdRead, Close, Seek };
struct Spec { const char *module, *name, *params, *results; Op op; };
static constexpr Spec imports[] = {
    {"goose", "write", "ii", "", Op::Write}, {"goose", "print_i64", "I", "", Op::I64},
    {"goose", "print_u64", "I", "", Op::U64}, {"goose", "print_f64", "F", "", Op::F64},
    {"goose", "print_f32", "f", "", Op::F32}, {"goose", "print_bool", "i", "", Op::Bool},
    {"goose", "newline", "", "", Op::Newline}, {"goose", "abort", "iii", "", Op::Abort},
    {"goose", "exit", "i", "", Op::Exit}, {"env", "bench_input", "", "I", Op::Input},
    {"env", "bench_input_f64", "", "F", Op::InputF64}, {"env", "bench_clock", "", "I", Op::Clock},
    {"env", "bench_barrier", "I", "I", Op::Barrier}, {"env", "bench_sink", "I", "", Op::Sink},
    {"env", "emscripten_notify_memory_growth", "i", "", Op::Growth},
    {"env", "emscripten_notify_memory_growth", "I", "", Op::Growth},
    {"wasi_snapshot_preview1", "args_sizes_get", "II", "i", Op::ArgsSizes},
    {"wasi_snapshot_preview1", "args_get", "II", "i", Op::Args},
    {"wasi_snapshot_preview1", "environ_sizes_get", "II", "i", Op::EnvSizes},
    {"wasi_snapshot_preview1", "environ_get", "II", "i", Op::Env},
    {"wasi_snapshot_preview1", "clock_time_get", "iII", "i", Op::Time},
    {"wasi_snapshot_preview1", "proc_exit", "i", "", Op::Exit},
    {"wasi_snapshot_preview1", "fd_write", "iIII", "i", Op::FdWrite},
    {"wasi_snapshot_preview1", "fd_read", "iIII", "i", Op::FdRead},
    {"wasi_snapshot_preview1", "fd_close", "i", "i", Op::Close},
    {"wasi_snapshot_preview1", "fd_seek", "iIiI", "i", Op::Seek},
};
static uint64_t address(int64_t value) {
    if (value < 0) fail("negative host address");
    return uint64_t(value);
}
static string numeric_token(string token) {
    auto digit = [](char c) { return c >= '0' && c <= '9'; };
    for (size_t i = 0; i < token.size(); ++i) {
        if (token[i] != '_') continue;
        if (!i || i + 1 == token.size() || !digit(token[i - 1]) || !digit(token[i + 1]))
            fail("invalid numeric host input");
    }
    token.erase(std::remove(token.begin(), token.end(), '_'), token.end());
    return token;
}
static wasm_trap_t *callback(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a,
                            size_t, wasmtime_val_t *r, size_t nresults) noexcept {
    auto state_pointer = static_cast<State *>(wasmtime_context_get_data(wasmtime_caller_context(caller)));
    try {
        auto &state = *state_pointer;
        const auto &spec = *static_cast<const Spec *>(env);
        if (nresults) { r[0].kind = WASMTIME_I32; r[0].of.i32 = 0; }
        switch (spec.op) {
        case Op::Write: state.output += Memory(caller).bytes(address(a[0].of.i32), address(a[1].of.i32)); break;
        case Op::I64: state.output += std::to_string(a[0].of.i64); break;
        case Op::U64: state.output += std::to_string(uint64_t(a[0].of.i64)); break;
        case Op::F64: state.output += goose_float(a[0].of.f64); break;
        case Op::F32: state.output += goose_float(a[0].of.f32); break;
        case Op::Bool:
            if (a[0].of.i32) state.output += "true";
            else state.output += "false";
            break;
        case Op::Newline: state.output += '\n'; break;
        case Op::Abort:
            fail("goose runtime error: " + utf8_replacement(Memory(caller).bytes(
                address(a[0].of.i32), address(a[1].of.i32))) + " (line " + std::to_string(a[2].of.i32) + ")");
        case Op::Exit:
            state.exited = true; state.exit_code = a[0].of.i32;
            return wasmtime_trap_new("program exit", 12);
        case Op::Input: {
            auto token = numeric_token(state.token());
            const char *begin = token.data();
            if (*begin == '+') {
                ++begin;
                if (begin != token.data() + token.size() && *begin == '-') fail("invalid integer host input");
            }
            int64_t value = 0;
            auto parsed = std::from_chars(begin, token.data() + token.size(), value);
            if (parsed.ec == std::errc::result_out_of_range) fail("host input exceeds i64");
            if (parsed.ec != std::errc{} || parsed.ptr != token.data() + token.size()) fail("invalid integer host input");
            r[0].kind = WASMTIME_I64; r[0].of.i64 = value; break;
        }
        case Op::InputF64: {
            auto token = numeric_token(state.token()); char *end = nullptr;
            double value = std::strtod(token.c_str(), &end);
            if (end == token.c_str() || end != token.c_str() + token.size() ||
                token.find_first_of("xXpP()") != string::npos) fail("invalid floating point host input");
            r[0].kind = WASMTIME_F64; r[0].of.f64 = value; break;
        }
        case Op::Clock: r[0].kind = WASMTIME_I64; r[0].of.i64 = int64_t(monotonic_ns()); break;
        case Op::Barrier:
            state.sink = a[0].of.i64; r[0].kind = WASMTIME_I64; r[0].of.i64 = state.sink; break;
        case Op::Sink: state.sink = a[0].of.i64; break;
        case Op::Growth: case Op::Env: break;
        case Op::ArgsSizes: case Op::EnvSizes: {
            Memory memory(caller);
            uint64_t count = 0, size = 0;
            if (spec.op == Op::ArgsSizes) { count = 1; size = 8; }
            memory.write64(address(a[0].of.i64), count);
            memory.write64(address(a[1].of.i64), size); break;
        }
        case Op::Args: {
            Memory memory(caller);
            memory.write64(address(a[0].of.i64), uint64_t(a[1].of.i64));
            memory.write(address(a[1].of.i64), string_view("program\0", 8)); break;
        }
        case Op::Time: {
            uint64_t value = 0;
            if (a[0].of.i32 == 0) value = std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
            else if (a[0].of.i32 == 1) value = monotonic_ns();
            else { r[0].of.i32 = 28; break; }
            Memory(caller).write64(address(a[2].of.i64), value); break;
        }
        case Op::FdWrite: case Op::FdRead: {
            int32_t fd = a[0].of.i32;
            bool reading = spec.op == Op::FdRead;
            if ((reading && fd != 0) || (!reading && fd != 1 && fd != 2)) { r[0].of.i32 = 8; break; }
            Memory memory(caller);
            auto vectors = memory.iovecs(address(a[1].of.i64), address(a[2].of.i64));
            uint64_t total = 0;
            for (auto [start, size] : vectors) {
                if (reading) {
                    auto count = std::min<uint64_t>(size, state.input.size() - state.input_position);
                    memory.write(start, string_view(state.input).substr(state.input_position, size_t(count)));
                    state.input_position += size_t(count); total += count;
                    if (count < size) break;
                } else {
                    auto bytes = memory.bytes(start, size);
                    if (fd == 1) state.output += bytes;
                    else state.errors += bytes;
                    if (size > UINT64_MAX - total) fail("host write byte count overflow");
                    total += size;
                }
            }
            memory.write64(address(a[3].of.i64), total); break;
        }
        case Op::Close: case Op::Seek:
            if (a[0].of.i32 < 0 || a[0].of.i32 > 2) r[0].of.i32 = 8;
            else if (spec.op == Op::Seek) r[0].of.i32 = 70;
            break;
        }
        return nullptr;
    } catch (HostError &error) {
        state_pointer->callback_error = std::move(error.message);
        return wasmtime_trap_new("host callback failed", 20);
    } catch (const std::exception &error) {
        try { state_pointer->callback_error = error.what(); } catch (...) {}
        return wasmtime_trap_new("host callback failed", 20);
    } catch (...) {
        return wasmtime_trap_new("host callback failed", 20);
    }
}
static bool signature(const wasm_valtype_vec_t *types, string_view expected) {
    if (types->size != expected.size()) return false;
    for (size_t i = 0; i < expected.size(); ++i) {
        wasm_valkind_t kind = WASM_I32;
        if (expected[i] == 'I') kind = WASM_I64;
        else if (expected[i] == 'f') kind = WASM_F32;
        else if (expected[i] == 'F') kind = WASM_F64;
        if (wasm_valtype_kind(types->data[i]) != kind) return false;
    }
    return true;
}
static void link_imports(wasmtime_linker_t *linker, const wasmtime_module_t *module) {
    Imports list; wasmtime_module_imports(module, &list.value);
    std::map<std::pair<string, string>, const Spec *> defined;
    for (size_t i = 0; i < list.value.size; ++i) {
        auto imported = list.value.data[i];
        auto mod = wasm_importtype_module(imported), name = wasm_importtype_name(imported);
        string m(mod->data, mod->size), n(name->data, name->size);
        auto type = wasm_externtype_as_functype_const(wasm_importtype_type(imported));
        const Spec *found = nullptr;
        bool supported = false;
        for (const auto &spec : imports) {
            if (m != spec.module || n != spec.name) continue;
            supported = true;
            if (type && signature(wasm_functype_params(type), spec.params) && signature(wasm_functype_results(type), spec.results)) {
                found = &spec;
                break;
            }
        }
        if (!supported || !type) fail("unsupported direct host import: " + m + "." + n);
        if (!found) fail("invalid direct host import signature: " + m + "." + n);
        auto [previous, inserted] = defined.emplace(std::make_pair(m, n), found);
        if (!inserted) {
            if (previous->second != found) fail("invalid direct host import signature: " + m + "." + n);
            continue;
        }
        check(wasmtime_linker_define_func(linker, m.data(), m.size(), n.data(), n.size(), type,
                                         callback, const_cast<Spec *>(found), nullptr));
    }
}
static bool exported(wasmtime_context_t *context, const wasmtime_instance_t &instance, const char *name, External &item) {
    item.found = wasmtime_instance_export_get(context, &instance, name, std::strlen(name), &item.value);
    return item.found;
}
static void call(wasmtime_context_t *context, const wasmtime_instance_t &instance, const char *name,
                 const wasmtime_val_t *args = nullptr, size_t nargs = 0, wasmtime_val_t *results = nullptr, size_t nresults = 0) {
    External item;
    if (!exported(context, instance, name, item) || item.value.kind != WASMTIME_EXTERN_FUNC) fail(string("missing function export: ") + name);
    wasm_trap_t *trap = nullptr;
    auto error = wasmtime_func_call(context, &item.value.of.func, args, nargs, results, nresults, &trap);
    check(error, trap);
}
struct Options {
    string module, timing, compiled, cache_config;
    bool precompiled = false, no_parallel_compilation = false, cache = true, serve = false;
#ifdef RUNTIME_ONLY
    bool minimal_profile = true;
#else
    bool minimal_profile = false;
#endif
};
static Owned<wasm_engine_t, wasm_engine_delete> make_engine(const Options &options, bool &cache_enabled) {
    Owned<wasm_config_t, wasm_config_delete> config(wasm_config_new());
    if (!config) fail("cannot create Wasmtime configuration");
#ifndef RUNTIME_ONLY
    wasmtime_config_cranelift_opt_level_set(config.get(), WASMTIME_OPT_LEVEL_SPEED);
#else
    (void)cache_enabled;
#endif
    wasmtime_config_wasm_memory64_set(config.get(), true);
    wasmtime_config_wasm_tail_call_set(config.get(), true);
    if (options.minimal_profile) {
#ifdef WASMTIME_FEATURE_COMPONENT_MODEL
        wasmtime_config_wasm_component_model_set(config.get(), false);
        wasmtime_config_concurrency_support_set(config.get(), false);
#endif
        wasmtime_config_gc_support_set(config.get(), false);
#ifdef WASMTIME_FEATURE_GC
        wasmtime_config_wasm_gc_set(config.get(), false);
        wasmtime_config_wasm_function_references_set(config.get(), false);
        wasmtime_config_wasm_reference_types_set(config.get(), false);
        wasmtime_config_wasm_exceptions_set(config.get(), false);
#endif
    }
#ifdef WASMTIME_FEATURE_GC
    else wasmtime_config_wasm_exceptions_set(config.get(), true);
#endif
    wasmtime_config_wasm_simd_set(config.get(), true);
    wasmtime_config_wasm_bulk_memory_set(config.get(), true);
    wasmtime_config_wasm_multi_value_set(config.get(), true);
#ifdef WASMTIME_FEATURE_THREADS
    wasmtime_config_wasm_threads_set(config.get(), false);
#endif
    wasmtime_config_wasm_relaxed_simd_set(config.get(), false);
#ifndef RUNTIME_ONLY
    if (options.no_parallel_compilation) wasmtime_config_parallel_compilation_set(config.get(), false);
    if (options.cache && !options.precompiled) {
        const char *path = nullptr;
        if (!options.cache_config.empty()) path = options.cache_config.c_str();
        auto error = wasmtime_config_cache_config_load(config.get(), path);
        if (error) {
            if (path) check(error);
            wasmtime_error_delete(error);
        } else cache_enabled = true;
    }
#endif
    Owned<wasm_engine_t, wasm_engine_delete> engine(wasm_engine_new_with_config(config.release()));
    if (!engine) fail("cannot create Wasmtime engine");
    return engine;
}
struct Module {
    string source;
    Owned<wasmtime_module_t, wasmtime_module_delete> module;
    Owned<wasmtime_linker_t, wasmtime_linker_delete> linker;
    uint64_t used = 0;
};
struct Runtime {
    bool cache_enabled = false;
    Owned<wasm_engine_t, wasm_engine_delete> engine;
    std::vector<std::unique_ptr<Module>> modules;
    size_t source_bytes = 0;
    uint64_t serial = 0;
    static constexpr size_t max_modules = 8, max_source_bytes = 64 * 1024 * 1024;
    explicit Runtime(const Options &options) : engine(make_engine(options, cache_enabled)) {}
    Module *find(string_view source) {
        for (auto &entry : modules) if (entry->source == source) {
            entry->used = ++serial; return entry.get();
        }
        return nullptr;
    }
    Module *retain(std::unique_ptr<Module> entry) {
        while (modules.size() >= max_modules || source_bytes + entry->source.size() > max_source_bytes) {
            auto oldest = std::min_element(modules.begin(), modules.end(),
                [](const auto &a, const auto &b) { return a->used < b->used; });
            source_bytes -= (*oldest)->source.size(); modules.erase(oldest);
        }
        source_bytes += entry->source.size(); entry->used = ++serial;
        modules.push_back(std::move(entry)); return modules.back().get();
    }
};
struct Timing { uint64_t prepare = 0, start = 0; bool module_hit = false; };
static int run(const Options &options, State &state, Runtime *shared = nullptr, Timing *observed = nullptr) {
    string data;
    if (!options.precompiled) data = read_file(options.module);
    uint64_t started = 0, instantiated = 0, ended = 0;
    bool timed = !options.timing.empty() || observed;
    if (timed) started = instantiated = monotonic_ns();
    std::unique_ptr<Runtime> local;
    if (!shared) { local = std::make_unique<Runtime>(options); shared = local.get(); }
    auto engine = shared->engine.get();
    Owned<wasmtime_store_t, wasmtime_store_delete> store(wasmtime_store_new(engine, &state, nullptr));
    if (!store) fail("cannot create Wasmtime store");
    auto context = wasmtime_store_context(store.get());
    std::unique_ptr<Module> owned;
    Module *module = nullptr;
    bool memoize = options.serve && !options.precompiled;
    if (memoize) module = shared->find(data);
    if (observed) observed->module_hit = bool(module);
    int exit_code = 0;
    bool entered = false;
    try {
        if (!module) {
            owned = std::make_unique<Module>();
            wasmtime_module_t *raw = nullptr;
            wasmtime_error_t *error = nullptr;
            if (options.precompiled) error = wasmtime_module_deserialize_file(engine, options.module.c_str(), &raw);
#ifndef RUNTIME_ONLY
            else error = wasmtime_module_new(engine, reinterpret_cast<const uint8_t *>(data.data()), data.size(), &raw);
#else
            else fail("AOT-only Wasmtime host requires --precompiled");
#endif
            owned->module.reset(raw); check(error); module = owned.get();
            if (memoize && data.size() <= Runtime::max_source_bytes) {
                owned->source = std::move(data); module = shared->retain(std::move(owned));
            }
        }
#ifndef RUNTIME_ONLY
        if (!options.compiled.empty()) {
            Bytes serialized; check(wasmtime_module_serialize(module->module.get(), &serialized.value));
            write_file(options.compiled, string_view(serialized.value.data, serialized.value.size));
            return 0;
        }
#endif
        if (!module->linker) {
            Owned<wasmtime_linker_t, wasmtime_linker_delete> linker(wasmtime_linker_new(engine));
            if (!linker) fail("cannot create Wasmtime linker");
            link_imports(linker.get(), module->module.get()); module->linker = std::move(linker);
        }
        wasmtime_instance_t instance; wasm_trap_t *trap = nullptr;
        auto error = wasmtime_linker_instantiate(module->linker.get(), context, module->module.get(), &instance, &trap);
        check(error, trap);
        External limits;
        if (exported(context, instance, "__set_stack_limits", limits)) {
            call(context, instance, "emscripten_stack_init");
            StackBounds bounds;
            call(context, instance, "emscripten_stack_get_base", nullptr, 0, bounds.values, 1);
            call(context, instance, "emscripten_stack_get_end", nullptr, 0, bounds.values + 1, 1);
            call(context, instance, "__set_stack_limits", bounds.values, 2);
        }
        if (timed) instantiated = monotonic_ns();
        entered = true;
        call(context, instance, "_start");
    } catch (const std::exception &error) {
        if (state.exited) exit_code = state.exit_code;
        else {
            exit_code = 1;
            if (!state.callback_error.empty()) state.failure = state.callback_error;
            else state.failure = error_text(error);
        }
    }
    if (timed) ended = monotonic_ns();
    if (!entered) instantiated = ended;
    if (observed) { observed->prepare = instantiated - started; observed->start = ended - instantiated; }
    if (!options.timing.empty()) {
        const char *mode = "wasm", *parallel = "true", *cached = "false";
        if (options.precompiled) mode = "precompiled";
        if (options.no_parallel_compilation) parallel = "false";
        if (shared->cache_enabled) cached = "true";
        const char *profile = "full", *optimization = "cranelift speed";
        if (options.minimal_profile) profile = "minimal";
#ifdef RUNTIME_ONLY
        parallel = "false";
        optimization = "precompiled artifact";
#endif
        char timing[1024];
        int length = std::snprintf(timing, sizeof timing,
            "{\n  \"engine\": \"Wasmtime\",\n  \"wasmtime\": \"%s\",\n"
            "  \"host\": \"native C API\",\n  \"aot_profile\": \"%s\",\n  \"module_mode\": \"%s\",\n"
            "  \"parallel_compilation\": %s,\n  \"compilation_cache_enabled\": %s,\n"
            "  \"optimization\": \"%s\",\n  \"compile_instantiate_ns\": %llu,\n"
            "  \"start_function_ns\": %llu,\n  \"engine_total_ns\": %llu\n}\n",
            WASMTIME_VERSION, profile, mode, parallel, cached, optimization,
            static_cast<unsigned long long>(instantiated - started),
            static_cast<unsigned long long>(ended - instantiated),
            static_cast<unsigned long long>(ended - started));
        if (length < 0 || size_t(length) >= sizeof timing) fail("cannot format timing");
        write_file(options.timing, string_view(timing, size_t(length)));
    }
    return exit_code;
}
static bool read_word(uint32_t &value, bool eof = false) {
    unsigned char bytes[4]; auto count = std::fread(bytes, 1, sizeof bytes, stdin);
    if (!count && eof && std::feof(stdin)) return false;
    if (count != sizeof bytes) fail("truncated runtime request header");
    value = 0;
    for (unsigned i = 0; i < sizeof bytes; i++) value |= uint32_t(bytes[i]) << (8 * i);
    return true;
}
static string read_payload(uint32_t size) {
    string value(size, '\0');
    if (std::fread(value.data(), 1, size, stdin) != size) fail("truncated runtime request payload");
    return value;
}
static void write_payload(string_view value) {
    if (std::fwrite(value.data(), 1, value.size(), stdout) != value.size()) fail("cannot write runtime response");
}
static void write_word(uint64_t value, unsigned size) {
    char bytes[8];
    for (unsigned i = 0; i < size; i++) bytes[i] = char(value >> (8 * i));
    write_payload(string_view(bytes, size));
}
static int serve(const Options &settings) {
    Runtime runtime(settings);
    write_payload(string_view("GWRT\1\0\0\0", 8)); std::fflush(stdout);
    uint32_t path_size, input_size;
    while (read_word(path_size, true)) {
        read_word(input_size);
        if (path_size > 65535) fail("runtime module path exceeds 65535 bytes");
        Options options = settings; options.module = read_payload(path_size);
        State state; state.input = read_payload(input_size); Timing timing; int code = 1;
        try {
            if (options.module.find('\0') != string::npos) fail("runtime module path contains NUL");
            code = run(options, state, &runtime, &timing);
        } catch (const std::exception &error) {
            state.failure += string("direct Wasmtime host: ") + error_text(error);
        }
        string errors = utf8_replacement(state.errors) + state.failure;
        if (!errors.empty()) errors += '\n';
        write_word(timing.module_hit, 4); write_word(uint32_t(code) & 255, 4);
        write_word(state.output.size(), 8); write_word(errors.size(), 8);
        write_word(timing.prepare, 8); write_word(timing.start, 8);
        write_payload(state.output); write_payload(errors);
        if (std::fflush(stdout)) fail("cannot flush runtime response");
    }
    return 0;
}
int main(int argc, char **argv) {
    State state;
    int code = 1;
    try {
        Options options;
        for (int i = 1; i < argc; ++i) {
            string arg = argv[i];
            if (arg == "--version" && argc == 2) { std::puts("Wasmtime " WASMTIME_VERSION); return 0; }
#ifdef RUNTIME_ONLY
            if (arg == "--no-parallel-compilation" || arg == "--cache" || arg == "--no-cache" ||
                arg == "--cache-config" || arg == "--serve" || arg == "--compile")
                fail("AOT-only Wasmtime host accepts --precompiled and --timing-json only");
#endif
            if (arg == "--no-parallel-compilation") options.no_parallel_compilation = true;
            else if (arg == "--cache") options.cache = true;
            else if (arg == "--cache-config" && i + 1 < argc) { options.cache_config = argv[++i]; options.cache = true; }
            else if (arg == "--no-cache") { options.cache = false; options.cache_config.clear(); }
            else if (arg == "--serve") options.serve = true;
            else if (arg == "--precompiled") options.precompiled = true;
            else if (arg == "--aot-profile" && i + 1 < argc) {
                if (string_view(argv[++i]) != "minimal") fail("unknown AOT profile; expected minimal");
                options.minimal_profile = true;
            } else if (arg == "--timing-json" && i + 1 < argc) options.timing = argv[++i];
            else if (arg == "--compile" && i + 2 < argc && options.module.empty()) {
                options.module = argv[++i]; options.compiled = argv[++i];
            } else if (!arg.empty() && arg[0] != '-' && options.module.empty()) options.module = arg;
            else fail("usage: wasmtime-host module.wasm [--timing-json FILE] [--no-parallel-compilation]\n"
                      "       wasmtime-host --cache module.wasm [--cache-config FILE]\n"
                      "       wasmtime-host --serve [--cache] [--cache-config FILE]\n"
                      "       wasmtime-host --compile module.wasm output.cwasm\n"
                      "       wasmtime-host --precompiled trusted.cwasm [--timing-json FILE]\n"
                      "       wasmtime-host --aot-profile minimal --compile module.wasm output.cwasm");
        }
#ifdef RUNTIME_ONLY
        if (!options.precompiled || options.module.empty() || options.serve || !options.compiled.empty())
            fail("AOT-only Wasmtime host requires --precompiled trusted.cwasm");
#endif
        if (options.minimal_profile && !options.precompiled && options.compiled.empty())
            fail("--aot-profile minimal requires --compile or --precompiled");
        if (options.serve) {
            if (!options.module.empty() || options.precompiled || !options.compiled.empty() || !options.timing.empty())
                fail("--serve takes Wasm requests on stdin, without a module or preparation/timing output");
            return serve(options);
        }
        if (options.module.empty() || (options.precompiled && !options.compiled.empty())) fail("expected one module and one execution mode");
        if (!options.compiled.empty() && !options.timing.empty()) fail("--compile cannot be combined with --timing-json");
        if (options.compiled.empty()) state.input = read_all(stdin);
        code = run(options, state);
    } catch (const std::exception &error) { state.failure += string("direct Wasmtime host: ") + error_text(error); }
    if (!state.output.empty() && std::fwrite(state.output.data(), 1, state.output.size(), stdout) != state.output.size()) code = 1;
    string errors = utf8_replacement(state.errors) + state.failure;
    if (!errors.empty()) {
        if (std::fwrite(errors.data(), 1, errors.size(), stderr) != errors.size()) code = 1;
        if (std::fputc('\n', stderr) == EOF) code = 1;
    }
    if (std::fflush(stdout)) code = 1;
    if (std::fflush(stderr)) code = 1;
    return code;
}
