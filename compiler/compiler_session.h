// Persistent direct compiler process. Every request owns a fresh AST; only the
// process, compiler stack and allocator remain alive between requests.
#pragma once

namespace goose {

inline thread_local bool compiler_session_active = false;
int Main(int argc, char **argv);
int RunOnCompilerStack(const function<int()> &fn);
void SetBinaryStdio();

inline void CheckSessionJson(string_view text) {
    // The shared JSON reader is recursive. This private, bounded protocol needs
    // only an object containing strings and an argument array.
    size_t depth = 0;
    bool quoted = false, escape = false;
    for (auto ch : text) {
        if (!ch) throw CompileError { "native session request contains a NUL byte" };
        if (quoted) {
            if (escape) escape = false;
            else if (ch == '\\') escape = true;
            else if (ch == '"') quoted = false;
        } else if (ch == '"') quoted = true;
        else if (ch == '[' || ch == '{') {
            if (++depth > 16) throw CompileError { "native session JSON nesting exceeds 16" };
        } else if (ch == ']' || ch == '}') {
            if (!depth) throw CompileError { "native session JSON nesting is invalid" };
            --depth;
        }
    }
}

inline vector<string> SessionArguments(const Json &request, const string &exe) {
    if (request.kind != Json::OBJECT)
        throw CompileError { "native session request must be an object" };
    auto args = request.Get("args");
    if (!args || args->kind != Json::ARRAY || args->arr.size() > 128)
        throw CompileError { "native session requires at most 128 arguments" };
    vector<string> argv = { exe };
    for (auto &arg : args->arr) {
        if (arg.kind != Json::STRING || arg.str.empty() || arg.str.find('\0') != string::npos)
            throw CompileError { "native session arguments must be nonempty strings without NUL" };
        argv.push_back(arg.str);
    }
    bool target = false, output = false, deps = false, stats = false;
    size_t sources = 0;
    for (size_t i = 1; i < argv.size(); ++i) {
        auto &arg = argv[i];
        if (arg == "-O0" || arg == "-O1" || arg == "-O2" || arg == "--offline") continue;
        if (arg == "--target" || arg == "-o" || arg == "--wasm-deps" ||
            arg == "--wasm-stats" || arg == "--wasm-initial-pages" ||
            arg == "--wasm-max-pages" || arg == "--stdlib" || arg == "-D") {
            if (i + 1 == argv.size()) throw CompileError { "native session option needs a value" };
            auto &value = argv[++i];
            if (arg == "--target") {
                if (value != "wasm-direct") throw CompileError { "native session only supports wasm-direct" };
                target = true;
            } else if (arg == "-o") output = true;
            else if (arg == "--wasm-deps") deps = true;
            else if (arg == "--wasm-stats") stats = true;
            else if (arg == "-D" && value != "GS_DEBUG=1")
                throw CompileError { "native session only accepts the GS_DEBUG=1 define" };
            continue;
        }
        if (arg.front() == '-' || ++sources > 1)
            throw CompileError { cat("unsupported native session argument: ", arg) };
    }
    if (!target || !output || !deps || !stats || sources != 1)
        throw CompileError { "native session requires a source, direct target, output, dependencies and stats" };
    return argv;
}

inline int RunWasmServer(const string &exe) {
    SetBinaryStdio();
    return RunOnCompilerStack([&]() -> int {
        compiler_session_active = true;
        struct ResetSession { ~ResetSession() { compiler_session_active = false; } } reset;
        fputs("{\"protocol\":\"goose-native-session-v1\"}\n", stdout);
        fflush(stdout);
        uint64_t serial = 0;
        for (;;) {
            string line;
            bool oversized = false;
            int ch = 0;
            while ((ch = fgetc(stdin)) != EOF && ch != '\n') {
                if (line.size() < (1u << 20)) line += (char)ch;
                else oversized = true;
            }
            if (ch == EOF && line.empty() && !oversized) return 0;
            string id, error;
            int code = 1;
            auto started = chrono::steady_clock::now();
            try {
                if (oversized) throw CompileError { "native session request exceeds 1 MiB" };
                CheckSessionJson(line);
                auto request = ParseJson(line);
                id = request.Str("id");
                if (id.empty()) throw CompileError { "native session request needs a string id" };
                auto arguments = SessionArguments(request, exe);
                vector<char *> argv;
                for (auto &arg : arguments) argv.push_back(arg.data());
                // Reset mutable frontend options, including diagnostic dump
                // mode if a previous exception interrupted a temporary dump.
                // All source, AST, type, specialization and backend state is
                // constructed and destroyed inside Main for every request.
                package_update = false;
                package_nofetch = false;
                dumpwritten = false;
                code = Main((int)argv.size(), argv.data());
            } catch (CompileError &e) {
                error = e.msg;
            } catch (exception &e) {
                // An unexpected exception may indicate broken invariants. Send
                // one failure response and terminate instead of reusing state.
                error = cat("native session terminated after exception: ", e.what());
                code = 2;
            }
            fflush(stderr);
            string response = "{\"id\":";
            JsonQuote(response, id);
            Append(response, ",\"code\":", code, ",\"request\":", ++serial,
                   ",\"compile_ns\":", chrono::duration_cast<chrono::nanoseconds>(
                       chrono::steady_clock::now() - started).count(), ",\"error\":");
            JsonQuote(response, error);
            response += "}\n";
            fputs(response.c_str(), stdout);
            fflush(stdout);
            if (code == 2) return 1;
        }
    });
}

}  // namespace goose
