// The direct Goose ABI and the standalone C backend's memory64 WASI subset.
#include <wasmtime.h>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
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
struct Options { string module, timing, compiled; bool precompiled = false, no_parallel_compilation = false; };
static int run(const Options &options, State &state) {
    string data;
    if (!options.precompiled) data = read_file(options.module);
    Owned<wasm_config_t, wasm_config_delete> config(wasm_config_new());
    if (!config) fail("cannot create Wasmtime configuration");
    wasmtime_config_cranelift_opt_level_set(config.get(), WASMTIME_OPT_LEVEL_SPEED);
    wasmtime_config_wasm_memory64_set(config.get(), true);
    wasmtime_config_wasm_tail_call_set(config.get(), true);
    wasmtime_config_wasm_exceptions_set(config.get(), true);
    wasmtime_config_wasm_simd_set(config.get(), true);
    wasmtime_config_wasm_bulk_memory_set(config.get(), true);
    wasmtime_config_wasm_multi_value_set(config.get(), true);
    wasmtime_config_wasm_threads_set(config.get(), false);
    wasmtime_config_wasm_relaxed_simd_set(config.get(), false);
    if (options.no_parallel_compilation) wasmtime_config_parallel_compilation_set(config.get(), false);
    uint64_t started = 0, instantiated = 0, ended = 0;
    if (!options.timing.empty()) started = instantiated = monotonic_ns();
    Owned<wasm_engine_t, wasm_engine_delete> engine(wasm_engine_new_with_config(config.release()));
    if (!engine) fail("cannot create Wasmtime engine");
    Owned<wasmtime_store_t, wasmtime_store_delete> store(wasmtime_store_new(engine.get(), &state, nullptr));
    if (!store) fail("cannot create Wasmtime store");
    auto context = wasmtime_store_context(store.get());
    Owned<wasmtime_module_t, wasmtime_module_delete> module;
    Owned<wasmtime_linker_t, wasmtime_linker_delete> linker;
    int exit_code = 0;
    try {
        wasmtime_module_t *raw = nullptr;
        wasmtime_error_t *error = nullptr;
        if (options.precompiled) error = wasmtime_module_deserialize_file(engine.get(), options.module.c_str(), &raw);
        else error = wasmtime_module_new(engine.get(), reinterpret_cast<const uint8_t *>(data.data()), data.size(), &raw);
        module.reset(raw);
        check(error);
        if (!options.compiled.empty()) {
            Bytes serialized; check(wasmtime_module_serialize(module.get(), &serialized.value));
            std::ofstream output(options.compiled, std::ios::binary);
            output.write(serialized.value.data, serialized.value.size); output.close();
            if (!output) fail("cannot write " + options.compiled);
            return 0;
        }
        linker.reset(wasmtime_linker_new(engine.get()));
        if (!linker) fail("cannot create Wasmtime linker");
        link_imports(linker.get(), module.get());
        wasmtime_instance_t instance; wasm_trap_t *trap = nullptr;
        error = wasmtime_linker_instantiate(linker.get(), context, module.get(), &instance, &trap);
        check(error, trap);
        External limits;
        if (exported(context, instance, "__set_stack_limits", limits)) {
            call(context, instance, "emscripten_stack_init");
            StackBounds bounds;
            call(context, instance, "emscripten_stack_get_base", nullptr, 0, bounds.values, 1);
            call(context, instance, "emscripten_stack_get_end", nullptr, 0, bounds.values + 1, 1);
            call(context, instance, "__set_stack_limits", bounds.values, 2);
        }
        if (!options.timing.empty()) instantiated = monotonic_ns();
        call(context, instance, "_start");
    } catch (const std::exception &error) {
        if (state.exited) exit_code = state.exit_code;
        else {
            exit_code = 1;
            if (!state.callback_error.empty()) state.failure = state.callback_error;
            else state.failure = error_text(error);
        }
    }
    if (!options.timing.empty()) {
        ended = monotonic_ns();
        std::ofstream timing(options.timing);
        timing << "{\n  \"engine\": \"Wasmtime\",\n  \"wasmtime\": \"" WASMTIME_VERSION "\",\n"
               << "  \"host\": \"native C API\",\n  \"module_mode\": \"";
        if (options.precompiled) timing << "precompiled";
        else timing << "wasm";
        timing << "\",\n  \"parallel_compilation\": ";
        if (options.no_parallel_compilation) timing << "false";
        else timing << "true";
        timing << ",\n  \"optimization\": \"cranelift speed\",\n  \"compile_instantiate_ns\": " << instantiated - started
               << ",\n  \"start_function_ns\": " << ended - instantiated
               << ",\n  \"engine_total_ns\": " << ended - started << "\n}\n";
        timing.close();
        if (!timing) fail("cannot write " + options.timing);
    }
    return exit_code;
}
int main(int argc, char **argv) {
    State state;
    int code = 1;
    try {
        Options options;
        for (int i = 1; i < argc; ++i) {
            string arg = argv[i];
            if (arg == "--version" && argc == 2) { std::puts("Wasmtime " WASMTIME_VERSION); return 0; }
            if (arg == "--no-parallel-compilation") options.no_parallel_compilation = true;
            else if (arg == "--precompiled") options.precompiled = true;
            else if (arg == "--timing-json" && i + 1 < argc) options.timing = argv[++i];
            else if (arg == "--compile" && i + 2 < argc && options.module.empty()) {
                options.module = argv[++i]; options.compiled = argv[++i];
            } else if (!arg.empty() && arg[0] != '-' && options.module.empty()) options.module = arg;
            else fail("usage: wasmtime-host module.wasm [--timing-json FILE] [--no-parallel-compilation]\n"
                      "       wasmtime-host --compile module.wasm output.cwasm\n"
                      "       wasmtime-host --precompiled trusted.cwasm [--timing-json FILE]");
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
