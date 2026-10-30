// Request-independent scanner transitions. Nothing here points into an Ast.
#pragma once

namespace goose {

struct LexicalTransition {
    size_t before_line_start = 0, after_position = 0, after_line_start = 0;
    size_t token_line_start = 0, attribute = 0, attribute_size = 0;
    size_t documentation = 0, documentation_size = 0;
    int before_line = 1, before_curlies = 0, after_line = 1, after_curlies = 0;
    int token_line = 1, token = 0;
    union { int64_t integer = 0; double floating; } value;
    bool unsigned_integer = false, multiline = false, has_documentation = false;
    // Only string tokens own decoded text. Copying the lexer's stale sval for
    // every subsequent punctuation token would consume quadratic memory.
    unique_ptr<string> string_value;
    uint64_t generation = 0;
};

struct LexicalFile {
    string filename, text;
    unordered_map<size_t, LexicalTransition> transitions;
    size_t accounted_bytes = 0;
    uint64_t touched = 0;
    uint64_t scanned_generation = 0, reused_generation = 0;
};

struct LexicalCache {
    // Conservative retained-storage accounting, including allowance for hash
    // nodes/buckets. This bounds the cache, not the compiler's request memory.
    size_t byte_limit, file_limit, accounted_bytes = 0;
    uint64_t generation = 0, clock = 0;
    int64_t scanned_files = 0, reused_files = 0, scanned_tokens = 0;
    int64_t reused_tokens = 0, lookahead_hits = 0, evictions = 0, bypassed_files = 0;
    map<string, shared_ptr<LexicalFile>> files;

    explicit LexicalCache(size_t bytes = 32 * 1024 * 1024, size_t count = 256)
        : byte_limit(bytes), file_limit(count) {}

    void BeginRequest() {
        generation++;
        scanned_files = reused_files = scanned_tokens = reused_tokens = 0;
        lookahead_hits = evictions = bypassed_files = 0;
    }

    bool EvictOne(const LexicalFile *pinned = nullptr) {
        auto oldest = files.end();
        for (auto it = files.begin(); it != files.end(); ++it) {
            // Lexer copies in a tentative parse pin their file too. Evicting
            // its map entry would not free that storage, so do not count it.
            if (it->second.get() == pinned || it->second.use_count() != 1) continue;
            if (oldest == files.end() || it->second->touched < oldest->second->touched) oldest = it;
        }
        if (oldest == files.end()) return false;
        accounted_bytes -= oldest->second->accounted_bytes;
        files.erase(oldest); evictions++;
        return true;
    }

    bool Reserve(size_t bytes, const LexicalFile *pinned = nullptr) {
        if (bytes > byte_limit) return false;
        while (accounted_bytes > byte_limit - bytes)
            if (!EvictOne(pinned)) return false;
        return true;
    }

    shared_ptr<LexicalFile> Attach(string_view filename, string_view text) {
        string name(filename);
        auto it = files.find(name);
        if (it != files.end()) {
            auto &file = it->second;
            if (file->text == text) { file->touched = ++clock; return file; }
            if (file.use_count() != 1) { bypassed_files++; return {}; }
            accounted_bytes -= file->accounted_bytes;
            files.erase(it);
        }
        // Include the file-map node/control block and the initial hash bucket
        // array (which can allocate several buckets for its first token).
        auto bytes = sizeof(LexicalFile) + 2 * (name.size() + 1) + text.size() + 1 + 512;
        if (!file_limit || !Reserve(bytes)) { bypassed_files++; return {}; }
        while (files.size() >= file_limit)
            if (!EvictOne()) { bypassed_files++; return {}; }
        auto file = make_shared<LexicalFile>();
        file->filename = name; file->text = text;
        file->accounted_bytes = bytes; file->touched = ++clock;
        accounted_bytes += bytes;
        files.emplace(std::move(name), file);
        return file;
    }

    void Scanned(LexicalFile *file) {
        scanned_tokens++;
        if (file && file->scanned_generation != generation) {
            file->scanned_generation = generation; scanned_files++;
        }
    }

    void Hit(LexicalFile &file, const LexicalTransition &transition) {
        if (transition.generation == generation) lookahead_hits++;
        else {
            reused_tokens++;
            if (file.reused_generation != generation) {
                file.reused_generation = generation; reused_files++;
            }
        }
    }

    void Store(LexicalFile &file, size_t position, LexicalTransition transition) {
        if (file.transitions.count(position)) return;
        auto bytes = sizeof(pair<const size_t, LexicalTransition>) + 6 * sizeof(void *);
        if (transition.string_value)
            bytes += sizeof(string) + transition.string_value->capacity() + 1 + 32;
        if (!Reserve(bytes, &file)) return;
        transition.generation = generation;
        file.transitions.emplace(position, std::move(transition));
        file.accounted_bytes += bytes; accounted_bytes += bytes;
    }
};

// Compilation runs on the compiler-stack thread, not the JSON protocol thread.
inline thread_local LexicalCache *active_lexical_cache = nullptr;
struct LexicalCacheScope {
    LexicalCache *previous;
    explicit LexicalCacheScope(LexicalCache *cache) : previous(active_lexical_cache) {
        active_lexical_cache = cache;
    }
    ~LexicalCacheScope() { active_lexical_cache = previous; }
};

}  // namespace goose
