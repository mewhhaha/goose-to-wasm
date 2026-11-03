#!/usr/bin/env python3
"""Check local tee fusion and complete-function local compaction."""
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LocalTee(unittest.TestCase):
    def test_instruction_boundaries_and_local_indices(self):
        with tempfile.TemporaryDirectory(prefix="goose-local-tee-") as directory:
            source = Path(directory) / "writer.cpp"
            source.write_text(r'''
#include <bit>
#include <cassert>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>
using namespace std;
#include "compiler/wasm_binary.h"
using goose::direct_wasm::Bytes;
using namespace goose::direct_wasm;

string bytes(initializer_list<uint8_t> values) {
    return string(values.begin(), values.end());
}

int main() {
    for (auto [index, encoded] : vector<pair<uint32_t, string>> {
        { 0, bytes({0}) }, { 127, bytes({127}) }, { 128, bytes({128, 1}) },
        { 16383, bytes({255, 127}) }, { 16384, bytes({128, 128, 1}) },
        { UINT32_MAX, bytes({255, 255, 255, 255, 15}) }
    }) {
        Bytes code;
        code.I32Const(7); code.OpU(0x21, index); code.OpU(0x20, index);
        assert(code.data == bytes({0x41, 7, 0x22}) + encoded);
        code.OpU(0x20, index);
        assert(code.data == bytes({0x41, 7, 0x22}) + encoded + bytes({0x20}) + encoded);
    }

    Bytes different;
    different.OpU(0x21, 0); different.OpU(0x20, 1); different.OpU(0x20, 0);
    assert(different.data == bytes({0x21, 0, 0x20, 1, 0x20, 0}));
    Bytes latest;
    latest.OpU(0x21, 0); latest.OpU(0x21, 1); latest.OpU(0x20, 1);
    assert(latest.data == bytes({0x21, 0, 0x22, 1}));

    // Every emitter that separates instructions must invalidate the marker.
    auto barrier = [](auto emit) {
        Bytes code;
        code.OpU(0x21, 0); emit(code);
        auto before = code.data;
        code.OpU(0x20, 0);
        assert(code.data == before + bytes({0x20, 0}));
    };
    barrier([](Bytes &b) { b.Byte(0x01); });
    barrier([](Bytes &b) { b.Raw(""); });
    barrier([](Bytes &b) { b.Raw(bytes({0x21, 0})); });
    barrier([](Bytes &b) { b.Op(0x01); });
    barrier([](Bytes &b) { b.OpU(0x10, 0); });
    barrier([](Bytes &b) { b.U(0); });
    barrier([](Bytes &b) { b.S(0); });
    barrier([](Bytes &b) { b.I32Const(0); });
    barrier([](Bytes &b) { b.I64Const(0); });
    barrier([](Bytes &b) { b.F32Const(0); });
    barrier([](Bytes &b) { b.F64Const(0); });
    barrier([](Bytes &b) { b.Mem(0x28); });
    barrier([](Bytes &b) { b.Copy(); });
    barrier([](Bytes &b) { b.Fill(); });

    // Opcode-looking suffixes inside raw bytes and constant immediates are data.
    auto false_set = [](auto emit) {
        Bytes code;
        emit(code); auto before = code.data;
        assert(before.ends_with(bytes({0x21, 0})));
        code.OpU(0x20, 0);
        assert(code.data == before + bytes({0x20, 0}));
    };
    false_set([](Bytes &b) { b.Raw(bytes({0x21, 0})); });
    false_set([](Bytes &b) { b.Byte(0x21); b.U(0); });
    false_set([](Bytes &b) { b.F32Const(bit_cast<float>(UINT32_C(0x00210000))); });
    false_set([](Bytes &b) { b.F64Const(bit_cast<double>(UINT64_C(0x0021000000000000))); });

    // Function::Finish moves all annotations with the body before its prologue.
    Bytes reused;
    reused.OpU(0x21, 0);
    auto body = std::move(reused); reused = Bytes{};
    reused.OpU(0x20, 0);
    assert(body.data == bytes({0x21, 0}));
    assert(reused.data == bytes({0x20, 0}));
    reused.OpU(0x21, 1); reused.OpU(0x20, 1);
    assert(reused.data == bytes({0x20, 0, 0x22, 1}));

    // Ordinary reads anywhere in the complete function retain every matching tee.
    Bytes function;
    function.I32Const(7); function.OpU(0x22, 128);
    auto saved_body = std::move(function); function = Bytes{};
    function.OpU(0x20, 128); function.Op(0x1a);
    auto prefix = function.data;
    function.Append(saved_body); function.Op(0x0b);
    auto live_function = prefix + saved_body.data + bytes({0x0b});
    vector<uint8_t> no_locals;
    assert(function.CompactLocals(129, no_locals));
    assert(function.data == live_function);
    assert(no_locals.empty());

    Bytes result_read;
    result_read.OpU(0x20, 128);
    Bytes prologue;
    prologue.I32Const(7); prologue.OpU(0x22, 128);
    prologue.Append(result_read); prologue.Op(0x0b);
    vector<uint8_t> result_locals(129, I32);
    assert(prologue.CompactLocals(0, result_locals));
    assert(prologue.data == bytes({0x41, 7, 0x22, 0, 0x20, 0, 0x0b}));
    assert(result_locals == vector<uint8_t>({I32}));

    // Appended annotations keep their offsets; only the unread local is removed.
    Bytes mixed, tail;
    mixed.I32Const(1); mixed.OpU(0x22, 0);
    tail.I32Const(2); tail.OpU(0x22, 128); tail.OpU(0x20, 0);
    mixed.Append(tail);
    vector<uint8_t> mixed_locals(129, I32);
    assert(mixed.CompactLocals(0, mixed_locals));
    assert(mixed.data == bytes({0x41, 1, 0x22, 0, 0x41, 2, 0x20, 0}));
    assert(mixed_locals == vector<uint8_t>({I32}));
    assert(mixed.CompactLocals(0, mixed_locals));
    assert(mixed.data == bytes({0x41, 1, 0x22, 0, 0x41, 2, 0x20, 0}));
    assert(mixed_locals == vector<uint8_t>({I32}));

    // Loop writes without ordinary reads need no storage. Set producers still run.
    Bytes loop;
    loop.Op(0x03); loop.Byte(0x40);
    loop.I32Const(7); loop.OpU(0x22, 128); loop.Op(0x1a);
    loop.I32Const(8); loop.OpU(0x22, 128); loop.Op(0x1a);
    loop.I32Const(9); loop.OpU(0x21, 128); loop.OpU(0x0c, 0); loop.Op(0x0b);
    vector<uint8_t> loop_locals(129, I32);
    assert(loop.CompactLocals(0, loop_locals));
    assert(loop.data == bytes({0x03, 0x40, 0x41, 7, 0x1a, 0x41, 8, 0x1a,
                              0x41, 9, 0x1a, 0x0c, 0, 0x0b}));
    assert(loop_locals.empty());

    // Parameters keep their indices; retained local types keep declaration order.
    Bytes typed;
    typed.OpU(0x20, 1); typed.OpU(0x20, 2); typed.OpU(0x20, 4); typed.OpU(0x20, 6);
    typed.I32Const(1); typed.OpU(0x21, 0);
    typed.I32Const(2); typed.OpU(0x21, 6);
    vector<uint8_t> types { I64, F32, V128, F64, I32 };
    assert(typed.CompactLocals(2, types));
    assert(types == vector<uint8_t>({I64, V128, I32}));
    assert(typed.data == bytes({0x20, 1, 0x20, 2, 0x20, 3, 0x20, 4,
                               0x41, 1, 0x1a, 0x41, 2, 0x21, 4}));

    // Reads of default-zero locals retain storage even without a preceding write.
    Bytes zero;
    zero.OpU(0x20, 128);
    vector<uint8_t> zeros(129, F64);
    assert(zero.CompactLocals(0, zeros));
    assert(zeros == vector<uint8_t>({F64}));
    assert(zero.data == bytes({0x20, 0}));

    // Compaction rejects invalid indices before allocating from their magnitude.
    Bytes invalid;
    invalid.OpU(0x21, UINT32_MAX); invalid.OpU(0x20, UINT32_MAX);
    auto invalid_data = invalid.data;
    vector<uint8_t> one { I32 };
    assert(!invalid.CompactLocals(0, one));
    assert(invalid.data == invalid_data && one == vector<uint8_t>({I32}));
    Bytes malformed;
    malformed.OpU(0x20, 0); malformed.local_ops[0].end++;
    auto malformed_data = malformed.data;
    assert(!malformed.CompactLocals(0, one));
    assert(malformed.data == malformed_data && one == vector<uint8_t>({I32}));

    // Unknown instruction sequences disable pruning even across an Append.
    for (auto raw : {string(), bytes({0x20, 0})}) {
        Bytes opaque;
        opaque.I32Const(7); opaque.OpU(0x22, 0); opaque.Raw(raw);
        auto original = opaque.data;
        vector<uint8_t> opaque_locals { I32, I64, F32 };
        assert(opaque.CompactLocals(0, opaque_locals));
        assert(opaque.data == original);
        assert(opaque_locals == vector<uint8_t>({I32, I64, F32}));
        Bytes combined;
        combined.I32Const(8); combined.OpU(0x22, 1); combined.Append(opaque);
        original = combined.data;
        assert(combined.CompactLocals(0, opaque_locals));
        assert(combined.data == original);
        assert(opaque_locals == vector<uint8_t>({I32, I64, F32}));
    }

    // Appending tracked bytes is a fusion barrier even if they are empty.
    Bytes boundary, empty;
    boundary.OpU(0x21, 0); boundary.Append(empty); boundary.OpU(0x20, 0);
    assert(boundary.data == bytes({0x21, 0, 0x20, 0}));
}
''')
            binary = Path(directory) / "writer"
            result = subprocess.run(
                ["c++", "-std=c++20", "-O2", "-I", str(ROOT), str(source), "-o", str(binary)],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            subprocess.run([str(binary)], check=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
