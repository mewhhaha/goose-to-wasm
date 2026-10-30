// Included after Ast and JsonOut. Build reads and import-resolution probes
// accompany the exact Goose source text, including negative observations.
#pragma once

namespace goose {

inline string DirectDependenciesJson(const Ast &ast, const DirectInputTrace &trace) {
    JsonOut json; json.BeginArray();
    for (auto &[path, text] : ast.sources) {
        json.BeginObject(); json.Member("path", path); json.Member("text", *text); json.EndObject();
    }
    // embed_file/shader and package-wide extern scans read inputs outside the
    // source transcript. Do not publish a reusable artifact until tracked.
    auto complete = trace.complete && ast.shaders.empty();
    for (auto &input : trace.observations) {
        json.BeginObject(); json.Member("path", input.path);
        json.Member("kind", input.probe ? "probe" : "build");
        json.Member("exists", input.found);
        if (!input.probe) {
            json.Member("complete", complete);
            if (input.found) json.Member("text", input.text);
        }
        json.EndObject();
    }
    json.EndArray();
    return std::move(json.s);
}

}  // namespace goose
