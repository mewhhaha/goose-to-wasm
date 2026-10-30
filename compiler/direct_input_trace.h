// Compiler-thread observations used to qualify whole-module artifact reuse.
// Keep every observation: repeated reads can disagree during an editor save.
#pragma once

namespace goose {

struct DirectInputObservation {
    string path, text;
    bool found = false, probe = false;
};
struct DirectInputTrace {
    vector<DirectInputObservation> observations;
    bool complete = true;
};
inline thread_local DirectInputTrace *active_direct_inputs = nullptr;
struct DirectInputTraceScope {
    DirectInputTrace *previous;
    explicit DirectInputTraceScope(DirectInputTrace *trace) : previous(active_direct_inputs) {
        active_direct_inputs = trace;
    }
    ~DirectInputTraceScope() { active_direct_inputs = previous; }
};

inline void ObserveDirectBuildInput(const string &path, bool found, const string &text) {
    if (active_direct_inputs) active_direct_inputs->observations.push_back({ path, text, found, false });
}
inline void ObserveDirectProbe(const string &path, bool found) {
    if (active_direct_inputs) active_direct_inputs->observations.push_back({ path, {}, found, true });
}
inline void DirectInputsIncomplete() {
    if (active_direct_inputs) active_direct_inputs->complete = false;
}

}  // namespace goose
