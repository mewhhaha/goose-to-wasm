#!/usr/bin/env python3
"""Compare the direct backend with the pinned C oracle on V8 and Wasmtime.

This suite qualifies an explicit supported fragment. Unsupported constructs
must be refused at compile time; they are never counted as passing executions.
Native C is the independent semantic oracle. Selected cases also have small
hand-derived answers; floating output is compared byte-for-byte with Goose.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, replace
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import struct
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"


@dataclass(frozen=True)
class Case:
    name: str
    fixture: str
    stdin: str = ""
    stdout: str | None = None
    exit_code: int = 0
    diagnostic: str = ""
    debug: bool = False
    group: str = "scalar"
    maximum_pages: int | None = None
    levels: tuple[int, ...] = (0, 1, 2)


def wrap(value, bits, signed=True):
    value &= (1 << bits) - 1
    if signed and value >= 1 << (bits - 1):
        value -= 1 << bits
    return value


def bit_fold(value, bits, count, polynomial, *, shift=1, mask=1, binder=False, signed=False):
    """Scalar recurrence oracle; every step follows the source width and shift."""
    value = wrap(value, bits, signed)
    for index in range(count):
        low = value & mask
        value >>= shift
        if low:
            value ^= polynomial
            if binder:
                value ^= index
        value = wrap(value, bits, signed)
    return value


def cases():
    result = [Case("checked-leaves/scalars", "checked_leaves", stdout="65 70 true\n25 63 4.25\n7 6 7 9\n-inf 1.25 -2.0\n")]
    strip_inputs = [(count, -1) for count in (0,1,2,3,4,5,7,8,9,15,17)] + [(17,0x12345678)]
    for count, seed in strip_inputs:
        values = [wrap(seed+37*i,32,False) for i in range(count)]
        lines = []
        for width in (3,8):
            lanes = [wrap(seed,32,False)] * width
            total = wrap(seed,32,False)
            for index, value in enumerate(values):
                mixed = wrap(value+index,32,False)
                lanes[index%width] ^= mixed
                total = wrap(total+lanes[index%width],32,False)
            lines.append(f"{lanes} {total}")
        signed_lanes = [-11,7,31]
        signed_total = 0
        wide_lanes = [0xFFFFFFFFFFFFFFF0] * 8
        for index, value in enumerate(values):
            lane = index%3
            before = signed_lanes[lane]
            updated = wrap(before+(value&31),32)
            updated = wrap(updated^before,32)
            signed_lanes[lane] = wrap(updated+1-index,32)
            signed_total += signed_lanes[lane]
            lane = index%8
            before = wide_lanes[lane]
            updated = wrap(before+value,64,False)^before
            wide_lanes[lane] = wrap(updated+1+index,64,False)
        lines.extend([f"{signed_lanes} {signed_total}",str(wide_lanes)])
        called = wrap(sum(value+index%3 for index,value in enumerate(values)),32,False)
        exited = wrap(sum(value+index%3 for index,value in enumerate(values) if index!=1 and index<5),32,False)
        lines.append(f"{called} {count} {exited} {called} {called}")
        lines.append("20")  # Rebinding the source shrinks the next iteration's view.
        for debug in (False,True):
            result.append(Case(f"codegen/strip/{count}/{seed}/{debug}", "codegen_strip",
                               f"{count} {seed}\n", "\n".join(lines)+"\n", debug=debug, group="control"))
    for seed, polynomial in ((0, 0), (-1, -1), (1 << 31, 1), (-(1 << 63), 0x80000000),
                             (0x123456789ABCDEF, 0xEDB88320), (-0x123456789ABCDEF, 0x13579BDF)):
        crc32 = 0xEDB88320
        crc64 = 0xC96C5795D7870F42
        rows = []
        for bits, crc in ((32, crc32), (64, crc64)):
            combinations = ((1, 0), (3, 1), (8, 1 << (bits - 1)),
                            (8, (1 << bits) - 1), (8, crc), (0, crc), (9, crc))
            if bits == 32:
                combinations += ((8, crc),)  # ==0 with the two branches swapped.
            else:
                combinations += ((8, crc), (5, 0xA24BAED4963EE407))
            rows.append([bit_fold(seed, bits, count, poly) for count, poly in combinations])
        first32 = bit_fold(seed, 32, 8, crc32)
        first64 = bit_fold(seed, 64, 8, crc64)
        rows.append([bit_fold(first32, 32, 8, crc32), bit_fold(first64, 64, 8, crc64),
                     bit_fold(seed, 32, 8, 1 << 31), bit_fold(seed, 64, 3, 1)])
        rows.append([bit_fold(seed, 64, 8, 0x123456789, signed=True), first32, first32, first32,
                     bit_fold(seed, 32, 8, crc32, binder=True)])
        x = wrap(seed, 32, False)
        y = x ^ 0xA5A5A5A5
        for _ in range(8):
            if x & 1:
                x = (x >> 1) ^ crc32
            else:
                y >>= 1
        rows.append([bit_fold(seed, 32, 8, wrap(polynomial, 32, False)),
                     bit_fold(seed, 32, 8, crc32, shift=2), bit_fold(seed, 32, 8, crc32, mask=2),
                     first32, 8, x ^ y])
        answer = "".join(" ".join(map(str, row)) + "\n" for row in rows)
        for debug in (False, True):
            result.append(Case(f"codegen/bit-fold/{seed}/{polynomial}/{debug}", "codegen_bit_fold",
                               f"{seed} {polynomial}\n", answer, debug=debug, group="control"))
    for count, seed in ((0, -1), (1, 255), (6, -1), (6, 128), (3, 17)):
        uniform = [125] + [wrap(seed, 8, False)] * count + [125] * (7 - count)
        negative = [-7] + [wrap(seed, 8)] * count + [-7] * (7 - count)
        effect = [125] + [85] * count + [125] * (7 - count)
        different = [125] + [wrap(seed + i, 8, False) for i in range(count)] + [125] * (7 - count)
        first = [91] * 8
        second = [92] * 8
        if count:
            first[1] = 17
            second[2:count + 1] = [17] * (count - 1)
        unsigned_image = int.from_bytes(bytes(uniform), "little")
        effect_image = int.from_bytes(bytes(effect), "little")
        varying_image = int.from_bytes(bytes(different), "little")
        first_image = int.from_bytes(bytes(first), "little")
        second_image = int.from_bytes(bytes(second), "little")
        answer = f"{unsigned_image}\n{negative}\n{effect_image} {count}\n{unsigned_image}\n{varying_image}\n{first_image} {second_image}\n"
        for debug in (False, True):
            result.append(Case(f"codegen/fill/{count}/{seed}/{debug}", "codegen_fill", f"{count} {seed}\n",
                               answer, debug=debug, group="control"))
    for seed, mode in [(x, 0) for x in (0, 1, 0x12345678, -1, 0xFFFFFFFF, -(1 << 63))] + [(0, 1), ((1 << 63) - 3, 1)]:
        crc = 0xFFFFFFFF ^ wrap(seed, 32, False)
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xEDB88320
            else:
                crc >>= 1
        answer = f"{crc ^ 0xFFFFFFFF}\n{wrap(seed + 248, 8, False)}\n55\n0 36\n21 7\n{seed}\n"
        for debug in (False, True):
            stdout = answer
            exit_code = 0
            diagnostic = ""
            if mode:
                if debug and seed > (1 << 63) - 9:
                    exit_code = 1
                    diagnostic = "overflow"
                else:
                    stdout += f"{wrap(seed + 8, 64)}\n"
            result.append(Case(f"codegen/unroll/{seed}/{mode}/{debug}", "codegen_unroll",
                               f"{seed} {mode}\n", stdout, exit_code=exit_code, diagnostic=diagnostic, debug=debug))
    for count in (0, 1, 5, 17):
        exits = sum(i for i in range(2, min(count + 2, 7)) if i != 4)
        total = count * (count - 1) // 2
        answer = f"8 145 {3 * total}\n32640 256\n{total} {exits}\n"
        for debug in (False, True):
            result.append(Case(f"codegen/loop-indices/{count}/{debug}", "codegen_loop_indices",
                               f"{count}\n", answer, debug=debug, group="control"))
    for debug in (False, True):
        result.append(Case(f"codegen/aliases/{debug}", "codegen_aliases",
                           stdout="8 1\n8 100 100 1\n[8, 100] 1 1\n", debug=debug, group="storage"))
    for count, index in ((0, -1), (1, -1), (5, -1), (3, 0), (2, 3), (1, 4)):
        values = [10 + i * 10 + count * i for i in range(4)]
        total = 100 * count + 3 * count * (count + 1)
        answer = f"{values} {total} {count}\n{total + 21}\n"
        exit_code = 0
        diagnostic = ""
        if 0 <= index < 4:
            answer += f"{values[index] + index} {count + 1}\n"
        elif index >= 4:
            exit_code = 1
            diagnostic = "bounds"
        for debug in (False, True):
            result.append(Case(f"codegen/loops/{count}/{index}/{debug}", "codegen_loops", f"{count} {index}\n",
                               answer, exit_code=exit_code, diagnostic=diagnostic, debug=debug, group="control"))
    for count, index in ((0, -1), (1, -1), (5, -1), (3, 0), (2, 3), (1, 4)):
        values = [(10 + 3 * count) * (i + 1) for i in range(4)]
        total = 246 * count + 30 * count * (count - 1) + 6 * (count // 2)
        state = 0
        for call in range(count):
            for offset, repetition in ((1, 0), (3, 1)):
                for i in range(4):
                    state += (10 + 3 * call + offset) * (i + 1) + i
                    state ^= i + repetition
            state += 246 + 60 * call + 6 * (call & 1)
        answer = f"{values} {state} {count}\n{total + 795}\n"
        exit_code = 0
        diagnostic = ""
        if 0 <= index < 4:
            seen = 2 * values[index] + 4 * (index + 1)
            if (values[index] + index + 1) & 1:
                seen -= 1
            else:
                seen += 2 * index
            answer += f"{seen} {count + 1}\n"
        elif index >= 4:
            exit_code = 1
            diagnostic = "bounds"
        for debug in (False, True):
            result.append(Case(f"codegen/kernel-calls/{count}/{index}/{debug}", "codegen_kernel_calls", f"{count} {index}\n",
                               answer, exit_code=exit_code, diagnostic=diagnostic, debug=debug, group="control"))
    for choice in (False, True):
        for x in (-1, 0, 127, 4294967295):
            crc = wrap(x, 32, False) >> 1
            narrow = wrap(x, 8, False) ^ 165
            flag = x == 0
            value = x ^ 170
            if choice:
                crc ^= 0xEDB88320
                narrow = wrap(x + 3, 8, False)
                flag = x > 0
                value = x ^ 85
            answer = f"{crc} 1\n{narrow}\n{str(flag).lower()}\n{value}\n"
            for debug in (False, True):
                result.append(Case(f"codegen/select/{choice}/{x}/{debug}", "codegen_select",
                                   f"{int(choice)} {x}\n", answer, debug=debug))
    for debug in (False, True):
        for mode, x, other in ((0, 91, 0), (1, 91, 0), (2, 91, 99), (3, (1 << 63) - 1, 0), (4, 128, 0)):
            result.append(Case(f"codegen/select-lazy/{mode}/{debug}", "codegen_select_lazy",
                               f"{mode} 0 {x} {other}\n", "37 0\n", debug=debug))
        result.append(Case(f"codegen/select-call/{debug}", "codegen_select_lazy", "0 1 91 0\n", "91 1\n", debug=debug))
        result.append(Case(f"codegen/select-zero/{debug}", "codegen_select_lazy", "1 1 91 0\n",
                           exit_code=1, diagnostic="division by zero", debug=debug))
        result.append(Case(f"codegen/select-bounds/{debug}", "codegen_select_lazy", "2 1 91 99\n",
                           exit_code=1, diagnostic="bounds", debug=debug))
    result.append(Case("codegen/select-overflow", "codegen_select_lazy", f"3 1 {(1 << 63) - 1} 0\n",
                       exit_code=1, diagnostic="overflow", debug=True))
    result.append(Case("codegen/select-cast", "codegen_select_lazy", "4 1 128 0\n",
                       exit_code=1, diagnostic="out of range", debug=True))
    for x, divisor in [(x, 8) for x in (-(1 << 63), -(1 << 63) + 1, -257, -129, -9, -1,
                                       0, 1, 7, 8, 127, 128, 255, 256, (1 << 63) - 1)] + [(-(1 << 63), -1), (-9, -8),
                                       (13, 3), (-13, 3), ((1 << 63) - 1, 3), (0, 3), (-(1 << 63), 3), (13, 0), (-13, 0)]:
        lines = [" ".join(str(wrap(x, bits) % (1 << (bits - 2))) for bits in (8, 16, 32, 64)),
                 " ".join(str(wrap(x, bits, False) % (1 << (bits - 1))) for bits in (8, 16, 32, 64)),
                 f"0 {x % 2} {x % 8} {x % 8}", f"{wrap(x, 8) % 8} {x % 8}", "0 1"]
        if x >= 0 and divisor > 0:
            lines.extend([f"{x // divisor} {x % divisor} {x >> 7}", str(divisor - 1)])
        elif divisor:
            lines.append(str(x % abs(divisor)))
        exit_code = 0
        diagnostic = ""
        if divisor == 0:
            exit_code = 1
            diagnostic = "division by zero"
        for debug in (False, True):
            result.append(Case(f"codegen/arithmetic/{x}/{divisor}/{debug}", "codegen_arithmetic",
                               f"{x} {divisor}\n", "\n".join(lines) + "\n", exit_code=exit_code,
                               diagnostic=diagnostic, debug=debug))
    aggregate_print_oracles=json.loads((FIXTURES/'aggregate_print_oracles.json').read_text())
    for debug in (False,True):
        for name,oracle in aggregate_print_oracles.items():
            result.append(Case("aggregate-print/"+name+("-debug" if debug else ""),"aggregate_print_"+name,
                               stdout=oracle['stdout'],exit_code=oracle['exit_code'],diagnostic=oracle['diagnostic'],debug=debug,group="storage"))
    record_tail_oracles=json.loads((FIXTURES/'encoded_record_tail_oracles.json').read_text())
    for debug in (False,True):
        for name,oracle in record_tail_oracles.items():
            result.append(Case("encoded-record-tail/"+name+("-debug" if debug else ""),"encoded_record_tail_"+name,
                               stdout=oracle['stdout'],exit_code=oracle['exit_code'],diagnostic=oracle['diagnostic'],debug=debug,group="storage"))
    combined_oracles=json.loads((FIXTURES/'combined_varint_oracles.json').read_text())
    for debug in (False,True):
        for name,oracle in combined_oracles.items():
            result.append(Case("combined-varint/"+name+("-debug" if debug else ""),"combined_varint_"+name,
                               stdout=oracle['stdout'],exit_code=oracle['exit_code'],diagnostic=oracle['diagnostic'],debug=debug,group="storage"))
    length_oracles=json.loads((FIXTURES/'uleb_length_oracles.json').read_text())
    for debug in (False,True):
        for name,oracle in length_oracles.items():
            result.append(Case("uleb-length/"+name+("-debug" if debug else ""),"uleb_length_"+name,
                               stdout=oracle['stdout'],exit_code=oracle['exit_code'],diagnostic=oracle['diagnostic'],debug=debug,group="storage"))
    grow_oracles=json.loads((FIXTURES/'varint_grow_oracles.json').read_text())
    for debug in (False,True):
        for name,oracle in grow_oracles.items():
            result.append(Case("varint-grow/"+name+("-debug" if debug else ""),"varint_grow_"+name,
                               stdout=oracle['stdout'],exit_code=oracle['exit_code'],diagnostic=oracle['diagnostic'],debug=debug,group="storage"))
    array_oracles=json.loads((FIXTURES/'varint_array_oracles.json').read_text())
    for debug in (False,True):
        for name,oracle in array_oracles.items():
            result.append(Case("varint-array/"+name+("-debug" if debug else ""),"varint_array_"+name,
                               stdout=oracle['stdout'],exit_code=oracle['exit_code'],diagnostic=oracle['diagnostic'],debug=debug,group="storage"))
    varint_answers={
        "replacement":"65 7 17 23\n",
        "values":"0 0 0 0 0\n3 -65 300 9223372036854775807 500\n7 -8193 -8193 -9223372036854775808 501 -7892\n",
        "callbacks":"11\n99\n11\n-65\n-47\n17\n64\n23\n17 64 8 23\n",
        "boundaries":"".join(f"{n} 8755\n" for n in (-9223372036854775808,-8193,-8192,-65,-64,-1,0,1,63,64,8191,8192,9223372036854775807)),
    }
    for debug in (False,True):
        for name,answer in varint_answers.items():
            result.append(Case("varint-record/"+name+("-debug" if debug else ""),"varint_record_"+name,stdout=answer,debug=debug,group="storage"))
    for debug in (False,True):
        for name,answer in {"fixed":"17 573785173 300 310 7\n17 true 300 1.5 17 2 5\n",
                            "callbacks":"1\n2\n3\n3\n1\n7\n1\n2\n3\n6\n1\n7\n",
                            "enums":"1\n2\n3\n4\n3\n17\n"}.items():
            result.append(Case("padding/"+name+("-debug" if debug else ""),"padding_"+name,stdout=answer,debug=debug,group="storage"))
    for debug in (False,True):
        for name,answer in {"wide":"65535 65536 2 3\n3\n2 1 1\n65536 7 1\n65535 7\n2 9 8\n", "zero":"0 0 0 0 0 1\n", "boundaries":"255 255 1 2\n2\n2 1\n255 7\n0\n256 256 4 5\n14 14 256 6 7\n256 14 4 9\n0\n",
                            "values":"[7, 8] [17, 8] [7, 8] [7, 8]\n17 2 13125 30600 85\nabc! 4 256\n0 0 0 0\n"}.items():
            result.append(Case("compact-limited/"+name+("-debug" if debug else ""),"compact_limited_"+name,
                               stdout=answer,debug=debug,group="storage"))
    enum_nonlocal = {"limited_sparse":"9\n17 70000 70000 1 0\n", "inner_forwarding":"9\n7\nA 17\nA 1\n", "nested_replacement":"9\nB 7\n", "canceled_prefix":"9\nA 17 1\n", "named_anchor":"9\n68\nA 17 1\n", "sparse":"9\n17 70000 1 0\n", "all_starts":"9\n7\nA 17\nA 1\n", "replacement":"B 7\n", "forwarding":"5\nA 3\nB 7\n"}
    for debug in (False,True):
        for name,answer in enum_nonlocal.items():
            result.append(Case("enum-nonlocal/"+name+("-debug" if debug else ""),"nonlocal_enum_"+name,
                               stdout=answer,debug=debug,group="control"))
    for debug in (False, True):
        for name, answer in {"fixed_enum_tuple":"3\nB 7\n", "borrowed_tuple":"3\nB 7\n", "borrowed_ordinary":"arg\nborrowed 7\nA 17\n", "views":"68 51 1\n13124 1 85\n", "fixed_tuple":"7\n300 17\n", "forwarding":"7 2 300 400\n8 1 500 17\n"}.items():
            result.append(Case("enum-image/" + name + ("-debug" if debug else ""), "enum_image_" + name,
                               stdout=answer, debug=debug, group="storage"))
        for name, answer in {"borrowed":"9\nA 1\n", "copy_borrowed":"9\nB 68\n", "copy_borrowed_variable":"9\nB 68 1 85\n", "canceled_fixed":"9\nB 68\n", "canceled_variable":"9\nB 68 1 85\n", "conditional":"9\nA 1\n", "successful":"A\n"}.items():
            result.append(Case("enum-image/" + name + ("-debug" if debug else ""), "enum_image_" + name,
                               stdout=answer, debug=debug, group="control", levels=(2,)))
        for name, answers in {"inline_fixed":("B 34\n","A 1\n"), "inline_variable":("B 34 1 51\n","A 1 34 1\n")}.items():
            for level, answer in zip((0,2),answers):
                result.append(Case(f"enum-image/{name}/O{level}" + ("-debug" if debug else ""), "enum_image_" + name,
                                   stdout=answer, debug=debug, group="control", levels=(level,)))
        result.append(Case("compact-enum/tags" + ("-debug" if debug else ""), "compact_enum_tags",
                           stdout="17 307 34 51 5 68\n408 6\n1 2\n", debug=debug, group="storage"))
    record_nonlocal = {
        "canceled_field":"9\n17 21811 68 1\n",
        "nested":"9\n17 21811 68 1\n",
        "variant":"9\n17 21811 68 1\n",
        "tails":"9\n17 8755 3 68 102 85\n9\n17 8755 3 3 68 102 85\n",
        "interleaved":"17 13226 34 1\n",
        "multiple":"7 300 2 8 9\n10 400 2 2 11 12\n[13] 17\n12\n14\n",
        "sparse":"9\n1 300000 2 0\n9\n1 300000 300000 2 0\n",
        "forwarded":"9\n17 21811 68 1 7\n",
        "forwarding_open":"51 17493 1 102 7\n",
        "forwarding_arguments":"17 21811 68 1 7\n",
        "forwarding_abandoned":"9\n17 21811 68 1 7\n",
        "forwarding_pair":"9\n17 8755 1 68 3 2 7 7\n",
        "forwarding_limited":"9\n17 8755 3 3 51 85 7\n",
    }
    for debug in (False,True):
        suffix="-debug" if debug else ""
        for name,answer in record_nonlocal.items():
            result.append(Case(f"record-nonlocal/{name}{suffix}","nonlocal_record_"+name,
                               stdout=answer,debug=debug,group="control"))
    record_images = {
        "aliases":"1 99 88 99 99\n",
        "callbacks":"1\n2\n3\n3\n1\n7\n1\n2\n3\n6\n1\n7\n",
        "sparse":"9\n1 300000 0\n9\n7 300000 0\n",
    }
    for debug in (False,True):
        suffix="-debug" if debug else ""
        for name,answer in record_images.items():
            result.append(Case(f"record-image/{name}{suffix}","record_image_"+name,
                               stdout=answer,debug=debug,group="storage"))
    packed_nonlocal = {
        "sparse-extent": "9\n300000 0\n9\n300000 300000 0\n9\n100000 0 0\n",
        "images": "2 7 300 8 400\n1 1 2 300 3 400 500\n2 1 2 3 4\n1 9 13124\n",
        "canceled": "9\n2 17 8755 1 26180\n9\n2 17 8755 1 17408\n9\n2 4386 13124 26113 34901\n",
        "multiple": "2 7 300 8 400\n2 2 9 500 10 600\n17\n10 600\n11 700\n4 1 7 300 99\n8 400\n",
    }
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for name, answer in packed_nonlocal.items():
            fixture = "nonlocal_image_sparse_extent" if name == "sparse-extent" else "nonlocal_packed_" + name
            result.append(Case(f"packed-image-nonlocal/{name}{suffix}", fixture,
                               stdout=answer, debug=debug, group="control"))
        for level, answer in [(0,"3\n85 324\n7 4386\n"),(2,"1\n7 4386\n")]:
            result.append(Case(f"packed-image-nonlocal/arguments/O{level}{suffix}", "nonlocal_packed_arguments",
                               stdout=answer, debug=debug, group="control", levels=(level,)))
    image_nonlocal = {
        "forwarded": "9\n3 2 7 7\n",
        "forwarding_limited": "9\n3 3 2 0 7\n",
        "scalars": "2 true false\n2 1.5 -2.25\n2 2 3.5 -4.25\n-4.25\n5.5\n2 -7 8\n",
        "all_starts": "9 259 262\n",
        "arrays": "2 7 8\n" * 5 + "2 2 9 10\n10\n11\n",
        "canceled": "9\n2 11 1\n" * 2 + "9\n2 2 11 1\n",
        "named_anchors": "9\n3\n" * 2 + "9\n3 3\n9\n3\n",
        "multiple": "2 7 8\n2 2 9 10\n[11] 17\n10\n12\n",
    }
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for name, answer in image_nonlocal.items():
            result.append(Case(f"image-nonlocal/{name}{suffix}", "nonlocal_image_" + name,
                               stdout=answer, debug=debug, group="control"))
        for level, answer in [(0,"3\n2\n7\n8\n"),(2,"2\n7\n8\n")]:
            result.append(Case(f"image-nonlocal/argument-order/O{level}{suffix}", "nonlocal_image_argument_order",
                               stdout=answer, debug=debug, group="control", levels=(level,)))
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for named in (0, 1):
            first = "2 1 2\n" if named else "2 7 8\n"
            last = "2 2 1 0\n" if named else "2 2 7 7\n"
            result.append(Case(f"array-image/construction/{named}{suffix}", "array_image_construction", f"{named}\n",
                               first + "2 9\n256\n2 7 8 9\n" + last, debug=debug, group="storage"))
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for fixture, answer in (
            ("upstream_return_from_cycle", "42\n42\n"),
            ("upstream_return_from_cached_call", "42\ng normal exit\n1\n-1\n0\n"),
            ("upstream_return_from_block_target", "10\n"),
            ("upstream_generic_return_from_fixed_subset", "11\n2.5\n11\n2.5\n1111\n2.52.5\n11\n2.5\n11\n2.5\n77\n"),
            ("nonlocal_retained_arguments", "2\n7\n"),
        ):
            result.append(Case(f"nonlocal/{fixture}{suffix}", fixture, stdout=answer, debug=debug, group="control"))
        for n in (0, 3):
            answer = "".join(f"{i + 10}\n" for i in range(n + 1)) + f"[{n}, {n + 1}] 9\n{40 if n == 0 else -1}\n{n + 60}\n{n + 70}\n"
            result.append(Case(f"nonlocal/paths/{n}{suffix}", "nonlocal_fixed_paths", f"{n}\n", answer, debug=debug, group="control"))
    owned_nonlocal = {
        "frame_array_channel": "9\n7 7 16 11\n",
        "nested_break": "[99]\n7\n1\n",
        "inline_outer": "[99]\n7\n",
        "publish_nested": "[99]\n7 2 1 16 7\n",
        "canceled_copy": "9\n[11]\n[11, 7]\n",
        "canceled_forward": "9\n[11]\n[11, 7]\n",
        "canceled_named": "9\n[1, 2]\n[1, 2, 11] 7\n",
        "canceled_normal": "9\n[11]\n[11, 7]\n" * 3,
        "publish_grow": "[99]\n7 16 9\n",
        "publish_er": "[99]\n7 16 9\n",
        "publish_er_u8": "[99]\n7 16 9\n",
        "publish_prefix": "[99]\n7 1 8 6 1 7\n",
        "publish_frame_tail": "[99]\n7 1 2 16 7\n",
        "publish_frame_base": "[99]\n7 1 2 16 9\n",
        "frame_forward": "[99]\n45\n",
        "var_record_forward": "[99]\n44\n",
        "ordinary": "[9]\n[7]\n[7, 8]\n",
        "inline": "[9]\n7\n",
        "enum": "[9]\n[4, 5]\n",
    }
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for fixture, answer in owned_nonlocal.items():
            result.append(Case(f"owned-nonlocal/{fixture}{suffix}", "nonlocal_owned_" + fixture,
                               stdout=answer, debug=debug, group="control"))
        for level, first, second in ((0, 3, 7), (2, 7, 8)):
            result.append(Case(f"owned-nonlocal/forward-order/O{level}{suffix}", "nonlocal_owned_forward_order",
                               stdout=f"[{first}]\n[{first}, {second}] 8\n",
                               debug=debug, group="control", levels=(level,)))
        for mode, answer in ((0, "7 7 16\n9\n"), (1, "7 7 0\n1 10\n")):
            result.append(Case(f"owned-nonlocal/frame-tail-call/{mode}{suffix}", "nonlocal_owned_frame_tail_initialization",
                               f"{mode}\n", answer, debug=debug, group="control"))
        for mode in (0, 1):
            result.append(Case(f"owned-nonlocal/early-block/{mode}{suffix}", "nonlocal_owned_early_block", f"{mode}\n",
                               "9\n[11]\n[11, 7]\n", debug=debug, group="control"))
        for n in (0, 3):
            answer = f"[{n}, {n + 1}]\n[{n}, {n + 1}, {n + 2}] {n + 2}\n[{n + 10}, {n + 11}]\n"
            result.append(Case(f"owned-nonlocal/recursive/{n}{suffix}", "nonlocal_owned_paths", f"{n}\n",
                               answer, debug=debug, group="control"))
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for mode in (0, 1, 2):
            answer = "1 [1, 2]\n1 [1, 2, 10]\n" if mode == 0 else "7 [9]\n7 [9, 10]\n"
            result.append(Case(f"frame-nonlocal/values/{mode}{suffix}", "nonlocal_frame_values", f"{mode}\n",
                               answer, debug=debug, group="control"))
        result.append(Case(f"frame-nonlocal/canceled{suffix}", "nonlocal_frame_canceled",
                           stdout="9\n1 [1, 2]\n1 [1, 2, 11] 7\n", debug=debug, group="control"))
        result.append(Case(f"frame-nonlocal/shrink{suffix}", "nonlocal_frame_shrink",
                           stdout="7 [9, 10]\n10\n[9, 11, 11]\n[12]\n", debug=debug, group="control"))
        for n in (0, 3):
            answer = "4 [5]\n" if n == 0 else "3 [4]\n"
            result.append(Case(f"frame-nonlocal/dispatch/{n}{suffix}", "nonlocal_frame_dispatch", f"{n}\n",
                               answer, debug=debug, group="control"))
        for depth in (0, 3):
            result.append(Case(f"frame-nonlocal/nested/{depth}{suffix}", "nonlocal_frame_nested", f"{depth}\n",
                               "7 1 [2, 3] 3\n[2, 3, 4]\n", debug=debug, group="control"))
    mixed_answers = {
        "order_grow": "3 [3] 4\n[3, 7] 8\n",
        "order_frame": "3 7 [9] 4\n[9, 8] 8\n",
        "forward": "3 [3] 4\n[3, 7] 8\n",
        "snapshot": "[1, 2] [7] 3\n",
        "replace": "[7] 2 3\n[7, 8] 8\n",
        "borrows": "8 [7] [8, 9] 8\n8 [10, 9] 10\n",
        "positions": "[1, 2] 3 4 4\n1 [2, 3] 4 4\n1 2 [3, 4] 4\n",
        "var_producer": "[3]\n[3, 7] 8\n",
    }
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for fixture, answer in mixed_answers.items():
            result.append(Case(f"mixed-nonlocal/{fixture}{suffix}", "nonlocal_mixed_" + fixture,
                               stdout=answer, debug=debug, group="control"))
        for level, answer in ((0, "9\n5 [1, 2] 6\n[1, 2, 11] 7\n"), (2, "9\n5 [11, 2] 6\n[11, 7, 11] 7\n")):
            result.append(Case(f"mixed-nonlocal/canceled/O{level}{suffix}", "nonlocal_mixed_canceled",
                               stdout=answer, debug=debug, group="control", levels=(level,)))
    multiple_answers = {
        "generic": "7 7\n[1, 2] [9, 2] [1, 2]\n3 [4, 5] 9 [8, 5] 3 [4, 5]\n",
        "order": "33 [3] [30]\n[3, 7] 8 [30, 40] 50\n",
        "forward": "33 [3] [30]\n[3, 7] 8 [30, 40] 50\n",
        "frame": "33 [3] 9 [40]\n[3, 7] 8 [40, 50] 50\n",
        "copies": "[1, 2] 3 [9, 2]\n[77, 2] [9, 2]\n",
        "canceled": "9\n[1, 2] [10, 20] 5\n[1, 2, 11] 7 [10, 20, 22] 70\n",
        "replace": "[7] [8] 9\n[7, 70] [8, 80]\n",
        "recursive": "[0] [1] 0\n[0, 7] [1, 8]\n",
        "heterogeneous": "A 4 [5] [6.5]\nAB [5, 6] [6.5, 7.5]\n",
    }
    for debug in (False, True):
        for fixture, answer in multiple_answers.items():
            result.append(Case("multiple-nonlocal/" + fixture + ("-debug" if debug else ""),
                               "nonlocal_multiple_" + fixture, stdout=answer, debug=debug, group="control"))
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for n in (-1, 0, 1):
            value = 0 if n > 0 else 4294967295 if n < 0 else 33752069
            answer = f"{value} {value} {0 if n > 0 else 65536}\n"
            result.append(Case(f"packed-record/overlap/{n}{suffix}", "packed_record_overlap", f"{n}\n",
                               answer, debug=debug, group="aggregate"))
        for n in (0, 1):
            result.append(Case(f"packed-record/arrays/{n}{suffix}", "packed_record_arrays", f"{n}\n",
                               "0 0 0 0\n" if n else "515 1286 3138462378 13124\n", debug=debug, group="aggregate"))
        for n in (0, 3):
            answer = f"1 {n + 10} {n + 11} {n + 12}\n{2 * n + 120}\n3 {n + 12}\n16 [{n}, {n + 1}]\n"
            result.append(Case(f"packed-record/storage/{n}{suffix}", "packed_record_storage", f"{n}\n",
                               answer, debug=debug, group="aggregate"))
    dispatch_upstream = {
        "dispatch_evaluation_order": "first\nchoice\nlast\n3 A 7\nfirst\nchoice\nlast\n3 B 7\n1 A 9\n3 A 4\n3 A 4\n1\n2\ncopied\n",
        "dispatch_copied_reference": "copied A\n0\n7\n7\nvalue arm\n",
        "dispatch_resizable": "31199\n438\n110372\n15161712\n1051\n23\n42199\n581\n2204135\n25262721\n1052\n66\n",
        "nested_overloads": "186 6\n[1, 4, 20, 7, 0]\n1 2\n3 2\n6 2.5\n42\n",
        "dispatch_result_no_reference": "5\n6\n5\nno radius\n",
    }
    for debug in (False, True):
        for fixture, expected in dispatch_upstream.items():
            result.append(Case(f"dispatch/upstream/{fixture}" + ("-debug" if debug else ""),
                               "upstream_" + fixture, stdout=expected, debug=debug, group="aggregate"))
        suffix = "-debug" if debug else ""
        result.append(Case(f"dispatch/recursive-reference{suffix}", "dispatch_recursive_reference", stdout="8 11\n", debug=debug, group="aggregate"))
        for n, value in ((0, 303), (3, 1569)):
            result.append(Case(f"dispatch/captured/{n}{suffix}", "dispatch_captured_cases", f"{n}\n",
                               f"{value}\n[7, 8]\n", debug=debug, group="aggregate"))
        for mode in (0, 1):
            for n in (255, 256):
                result.append(Case(f"dispatch/narrow/{mode}/{n}{suffix}", "dispatch_narrow_results", f"{mode} {n}\n",
                                   ("one\n" if mode == 0 else "two\n") + ("255\n" if n == 255 else ""),
                                   exit_code=0 if n == 255 else 1, diagnostic="" if n == 255 else "storage range",
                                   debug=debug, group="aggregate"))
    for debug in (False, True):
        suffix = "-debug" if debug else ""
        for n in (0, 3):
            answer = (f"[{n}, {n + 1}] [{n + 100}, {n + 1}, 7] 1\n[{n + 2}, {n + 3}] 1\n702 1\n"
                      f"{n} [{n + 1}, {n + 2}] {n + 10} [{n + 21}, {n + 2}]\n"
                      f"{n + 3} [{n + 4}] {n + 33} [{n + 4}, 40]\n{n + 5} [{n + 6}]\n"
                      f"{n + 5} [{n + 56}]\n{101 * n + 10} {n + 10}\n{n + 208}\n1 99\n[1] [2]\n1 99\n"
                      f"{n + 70} [{n + 71}, {n + 72}]\n")
            result.append(Case(f"owned-fv/values/{n}{suffix}", "owned_function_values", f"{n}\n", answer, debug=debug, group="aggregate"))
        result.append(Case(f"owned-fv/recursive-forward{suffix}", "owned_function_value_recursion", "20\n", "[7, 8]\n[7, 8]\n", debug=debug, group="aggregate"))
        for mode in range(3):
            for n in (255, 256):
                success = n == 255 or mode == 1
                result.append(Case(f"owned-fv/narrow/{mode}/{n}{suffix}", "owned_function_value_narrow", f"{mode} {n}\n",
                                   "make\n" + (f"{n}\n" if success else ""), exit_code=0 if success else 1,
                                   diagnostic="" if success else "storage range", debug=debug, group="aggregate"))
    result.append(Case("scope/while-condition-exits", "while_condition_exits", stdout="3 15 81 100\n", group="aggregate"))
    result.append(Case("temporary/multiple-discard", "anonymous_multiple", stdout="2\n4 17\n", group="aggregate"))
    for mode in range(21):
        for n in (255, 256):
            prefix = "mixed" if mode == 7 else "local" if mode == 9 else "inline-local" if mode == 16 else "inline" if mode in (10, 11, 12, 13, 14, 15, 17, 20) else "body"
            choices = (0, 2) if n == 256 and mode in (12, 13) else (None,)
            for level in choices:
                success = n <= 255 or mode in (1, 2, 3, 8, 10, 11, 17, 18, 19, 20) or (mode in (12, 13) and level == 2)
                suffix = "done" if mode == 14 else f"{n} 3" if mode == 7 else f"{n} {n}" if mode == 12 else str(n)
                answer = prefix + "\n" + (suffix + "\n" if success else "")
                result.append(Case(f"variable-length/u8/{mode}/{n}" + (f"/O{level}" if level is not None else ""),
                                   "narrow_variable_arrays", f"{mode} {n}\n", answer,
                                   exit_code=0 if success else 1, diagnostic="" if success else "storage range",
                                   group="aggregate", levels=(level,) if level is not None else (0, 1, 2)))
    for mode, inputs in ((0, (65535, 65536)), (1, (65535, 65536)), (2, (65535, 65536)),
                         (3, (65535, 65536)), (4, (255, 256)), (5, (0, 65536)),
                         (6, (65535, 65536)), (7, (65536,)), (8, (255, 256))):
        for n in inputs:
            success = not ((mode in (0, 3, 6) and n > 65535) or (mode in (4, 8) and n > 255))
            prefix = "mixed16\nlater" if mode == 8 else "64" if mode in (5, 6, 7) else "16"
            answer = prefix + "\n" + ((f"{n} 42\n" if mode == 8 else f"{n}\n") if success else "")
            result.append(Case(f"variable-length/wide/{mode}/{n}", "wide_variable_arrays", f"{mode} {n}\n", answer,
                               exit_code=0 if success else 1, diagnostic="" if success else "storage range", group="aggregate"))
    for mode in (9, 10, 11, 12, 13):
        for n in (255, 256):
            success = n <= 255 or mode == 12
            prefix = "pairs\n" if mode in (12, 13) else "16\n"
            if success:
                prefix += {9: "take\n", 10: "echo\n", 11: "echo-inline\n"}.get(mode, "")
            answer = prefix + ((f"{n} 7\n" if mode in (12, 13) else f"{n}\n") if success else "")
            result.append(Case(f"variable-length/owned-parameters/{mode}/{n}", "wide_variable_arrays", f"{mode} {n}\n", answer,
                               exit_code=0 if success else 1, diagnostic="" if success else "storage range", group="aggregate"))
    for mode in (14, 15):
        for n in (255, 256):
            success = n <= 255
            prefix = "grow\n" if mode == 14 else "grow-mixed\nlater\n"
            answer = prefix + ((f"{n} 42\n" if mode == 15 else f"{n}\n") if success else "")
            result.append(Case(f"variable-length/grow-to-narrow/{mode}/{n}", "wide_variable_arrays", f"{mode} {n}\n", answer,
                               exit_code=0 if success else 1, diagnostic="" if success else "storage range", group="aggregate"))
    for n in (255, 256):
        success = n <= 255
        result.append(Case(f"variable-length/second-result/{n}", "wide_variable_arrays", f"16 {n}\n",
                           "second\nlater\n" + (f"42 {n}\n" if success else ""),
                           exit_code=0 if success else 1, diagnostic="" if success else "storage range", group="aggregate"))
    for n in (0, 3):
        selected = 30 if n > 0 else 40
        answer = (f"0 0 0\n{n} [{n + 1}, {n + 2}] {n + 100} [{n + 201}, {n + 2}]\n"
                  f"{n + 10} [{n + 21}, {n + 2}] {n + 10} {n + 10} [{n + 21}, {n + 2}]\n"
                  f"{selected} [{selected + 1}, {selected + 2}] 50 [51, 52]\n8\n")
        result.append(Case(f"owned-struct/variable-tail/{n}", "variable_structs", f"{n}\n", answer, group="aggregate"))
    for n in (0, 3):
        chosen = 6 if n > 0 else 5
        ending = "99 [100, 101] 88 [89, 90]" if n > 0 else "2 [3, 4] 2 [3, 4]"
        answer = (f"7 9 0\n{n} {n + 1} {n + 11} {n + 2}\n{n} {2 * n + 32} {n + 21}\n"
                  f"{2 * n + 3}\n{4 * n + 66} {n}\n1\n2\n3\n1 2 3\n{ending}\n"
                  f"{chosen} [{chosen + 1}, {chosen + 2}]\n{n + 1000}\n")
        result.append(Case(f"owned-struct/paths/{n}", "variable_struct_paths", f"{n}\n", answer, group="aggregate"))
    for n in (255, 256):
        result.append(Case(f"owned-struct/narrow-tail/{n}", "variable_struct_narrow", f"{n}\n",
                           "prefix\ntail\n" + ("42 255 7\n" if n == 255 else ""),
                           exit_code=0 if n == 255 else 1, diagnostic="" if n == 255 else "storage range", group="aggregate"))
    for n in (0, 3):
        answer = (f"{n} [{n}] {n + 4} [{n}, 7] {n + 4}\n"
                  f"[{n}, 8, 8] {n + 4}\n[{n}, 8, 8] {n + 4}\n"
                  f"{n + 10} [{n}, 99] {n + 4} 2 {n + 10} 0 {n + 4}\n"
                  f"{n} 3 {n + 100} [{n}, 8, 8, 88] {n + 4}\n")
        result.append(Case(f"owned-struct/limited-tail/{n}", "limited_structs", f"{n}\n", answer, group="aggregate"))
    for n in (-1, 4294967296):
        result.append(Case(f"owned-struct/capacity-error/{n}", "limited_struct_errors", f"{n}\n", "prefix\n",
                           exit_code=1, diagnostic="capacity", group="aggregate"))
    for n in (0, 3):
        answer = (f"0 0 {n} [{n + 1}, {n + 2}] {n + 100} [{n + 1}, {n + 2}, 88]\n"
                  f"{n} [{n + 21}, {n + 2}] {n + 10} {n + 10} [{n + 21}, {n + 2}, 99]\n"
                  f"2 {n + 50} [{n + 50}, 62]\n"
                  f"{n + 70} [{n + 71}, {n + 72}, 77] {n + 82} 7\n2 {n + 1} [3]\n")
        result.append(Case(f"frame-struct/owned-values/{n}", "frame_structs", f"{n}\n", answer, group="aggregate"))
    for n in (0, 1, 2):
        first = 10 if n == 1 else 1
        second = 20 if n in (1, 2) else 2
        tail = 30 if n in (1, 2) else 3
        marker = 7 if n == 1 else 8 if n == 2 else 0
        answer = (f"{marker} {first} {second} [{tail}]\n"
                  f"{n} {n + 1} [{n + 32}] {n + 10} {n + 10} {n + 21} [{n + 32}, 40]\n"
                  f"{n} {n + 1} {n + 101} {n + 2}\ntrue [2]\n")
        result.append(Case(f"frame-struct/paths/{n}", "frame_struct_paths", f"{n}\n", answer, group="aggregate"))
    for n in (0, 3):
        chosen = 40 if n > 0 else 50
        interrupted = "77 3 10 11 12" if n > 0 else "0 3 4 5 6"
        answer = (f"{n} {n + 1} {n + 100} {n + 201}\n"
                  f"1 {n} 2 1 {n + 21} {n + 10} 2 {n + 10} 4 2\n"
                  f"{chosen} 60 7 {n}\n{interrupted}\n"
                  f"2 {n + 10} [{n + 21}] {n + 10} 2 {n + 10} [{n + 21}]\n"
                  f"[{n}, 99] 4 [{n}] 4\n")
        result.append(Case(f"nested-owner/values/{n}", "nested_owned_structs", f"{n}\n", answer, group="aggregate"))
    for n in (255, 256):
        result.append(Case(f"nested-owner/narrow/{n}", "nested_struct_narrow", f"{n}\n",
                           "prefix\ntail\n" + ("3 42 255 7\n" if n == 255 else ""),
                           exit_code=0 if n == 255 else 1, diagnostic="" if n == 255 else "storage range", group="aggregate"))
    for n in (0, 3):
        answer = (f"7 9\n{n + 5} {n + 35} {n}\n{n + 35} {n + 10} {n + 35}\n"
                  f"{n} 2 {n + 35}\n{n + 35} {2 * n + 81} {n + 61}\n"
                  f"{65 if n > 0 else 0} 75 {17 if n > 0 else 9} 12\n{n + 80} {n + 10}\n"
                  f"{n + 5} {2 * n + 3} {n + 13} 3\n"
                  f"{n} {n + 1000} {n + 12}\n{n + 100} {n + 1000} {n + 12}\n"
                  f"1\n2\n3\n4\n9\n{2 * n + 190}\n")
        result.append(Case(f"variable-enum/fixed-payloads/{n}", "variable_mode_enums", f"{n}\n", answer, group="aggregate"))
    for n in (0, 3):
        chosen = 30 if n > 0 else 40
        exited = 80 if n > 0 else 2
        answer = (f"0 0 0\n{n} [{n + 1}, {n + 2}] {n + 100} [{n + 201}, {n + 2}]\n"
                  f"{n + 10} [{n + 21}, {n + 2}] {n + 10} {n + 10} [{n + 21}, {n + 2}]\n"
                  f"{chosen} 50 {exited} 7 {n}\n"
                  f"{n} {n + 60} [{n + 61}, {n + 62}] [{n + 161}, {n + 62}]\n"
                  f"{n} [{n + 70}, {n + 71}] [{n + 270}, {n + 71}]\n"
                  f"{n} [{n}, 99] 4 [{n}] 4\n")
        result.append(Case(f"variable-variant/values/{n}", "variable_variants", f"{n}\n", answer, group="aggregate"))
    for n in (255, 256):
        result.append(Case(f"variable-variant/narrow/{n}", "variable_variant_narrow", f"{n}\n",
                           "prefix\ntail\n" + ("42 255 7\n" if n == 255 else ""),
                           exit_code=0 if n == 255 else 1, diagnostic="" if n == 255 else "storage range", group="aggregate"))
    for n in (0, 1, 2, 3):
        exited = {0: 7, 1: 77, 2: 188, 3: 0}[n]
        answer = (f"{2 * n + 3} {2 * n + 33}\n{2 * n + 33} {n + 10} {2 * n + 33}\n"
                  f"{2 * n + 33} {n + 10} {2 * n + 33}\n{n} [{n + 1}, {n + 2}] {2 * n + 33}\n"
                  f"{2 * n + 83} {2 * n + 103} {123 if n > 0 else 0} 143 {exited} 17\n"
                  f"{n} [{n}, 99] 4\n{n} [{n}] 4\n{n + 6} 2 {n + 6}\n7 0\n")
        result.append(Case(f"variable-enum-tail/values/{n}", "variable_enum_tails", f"{n}\n", answer, group="aggregate"))
    for n in (255, 256):
        result.append(Case(f"variable-enum-tail/nested-narrow/{n}", "variable_enum_nested_narrow", f"{n}\n",
                           "prefix\ntail\n" + ("3 42 4 255 7\n" if n == 255 else ""),
                           exit_code=0 if n == 255 else 1, diagnostic="" if n == 255 else "storage range", group="aggregate"))
    for n in (-1, 4294967296):
        result.append(Case(f"variable-enum-tail/capacity-error/{n}", "variable_enum_capacity_errors", f"{n}\n", "prefix\n",
                           exit_code=1, diagnostic="capacity", group="aggregate"))
    for n in (0, 1):
        answer = "0 0 0 0\n" if n > 0 else "100 100 100 200\n"
        result.append(Case(f"variable-enum-tail/replacement-aliases/{n}", "variable_enum_replacement_aliases", f"{n}\n", answer, group="aggregate"))
    for n in (-1, 0, 1):
        answer = ("72057594037927935 1 72057594037927935\n255 65535 4294967295 255\n-1\n" if n < 0 else
                  "283686952306183 1 283686952306183\n8 1543 33752069 1\n50595078\n" if n == 0 else
                  "0 0 0\n0 0 0 0\n0\n")
        result.append(Case(f"image/packed-variant/{n}", "packed_variant_overlap", f"{n}\n", answer, group="aggregate"))
    for n in (-1, 0, 3):
        answer = (f"1 {n + 10} {n + 11} {n + 12}\n7 1 {n + 110} {n + 20}\n"
                  f"4 {n + 11} {n + 12}\n{n + 12} {n + 112}\n")
        result.append(Case(f"image/packed-storage/{n}", "packed_variant_storage", f"{n}\n", answer, group="aggregate"))
    capture_programs = (
        ("upstream-inline", "upstream_inline_nested_calls", "1204\n11 15 1\n63\n36\n5 -1\n32\n"),
        ("upstream-scope", "upstream_nested_fn_scope", "1 6 10\n1 6 11\n1 6 2\n1\n1 3\n10 2\n10 5\n10 3\n1120 5121\n1420 15\n1120 5121\n1420 16\ntrue true 9 2\n"),
        ("upstream-fv-subset", "upstream_funval_captures_subset", "105\n8\n104\n20\n24\n916\n41\n43\n51\n43\n43\n233\n113423\n12\n5\n9\n12\n0\n10\n20\n304\n8\n5\n4 [1, 2, 3, 10]\n28\n24\n9\n51\n56\n105\n12 20 27\n"),
        ("upstream-init-subset", "upstream_initializer_captures_subset", "6 550027 2006 1122\n"),
    )
    for name, fixture, answer in capture_programs:
        for debug in (False, True):
            result.append(Case(f"capture/{name}" + ("-debug" if debug else ""), fixture, stdout=answer, debug=debug, group="control"))
    for n in (0, 3):
        answer = f"{n} {n + 110} {n + 110} {n + 230} 3\n[{n + 1}, {n + 2}, {n + 3}] 1\n[4, 5, 6] 2\n"
        for debug in (False, True):
            result.append(Case(f"capture/bindings/{n}" + ("-debug" if debug else ""), "static_capture_bindings", f"{n}\n", answer, debug=debug, group="control"))
    full_capture_answer = capture_programs[2][2].removesuffix("12 20 27\n") + "12 12 20 27\n"
    for debug in (False, True):
        result.append(Case("capture/upstream-fv-full" + ("-debug" if debug else ""), "upstream_funval_captures_o2",
                           stdout=full_capture_answer, debug=debug, group="control"))
    for n in (0, 3):
        answer = (f"[{n}, {n + 1}] 2 {n + 5} {n + 5} 2\n"
                  f"[{n}, {n + 1}, 7] [{n}, {n + 1}] [{n}, {n + 1}, 77]\n"
                  f"[{n + 1}] {n + 5}\n[{n + 1}, 8]\n77 [{n + 1}, 8] [{n + 1}, 8]\n"
                  f"[{n + 10}, {n + 1}, 99] {n + 5} 3 [{n + 10}, {n + 1}, 99] {n + 5}\n"
                  f"[{n + 10}, {n + 1}, 99, 100] 3 [{n + 10}, {n + 1}, 99]\n"
                  f"[{n + 10}, {n + 1}, 99] 4 3 4\n"
                  f"[{n}, {n + 1}] 2\n20\n0\n0 3\n[9] 6 7\n")
        result.append(Case(f"runtime-limited/values/{n}", "runtime_limited", f"{n}\n", answer, group="aggregate"))
        answer = f"{n} {n + 1} 30 40 4\n{n + 10} 3 4 3\n{n + 2} 40 2 4\n"
        result.append(Case(f"runtime-limited/aggregate/{n}", "runtime_limited_aggregate", f"{n}\n", answer, group="aggregate"))
    for mode in range(12):
        diagnostic = "capacity" if mode <= 6 or mode == 11 else "pop" if mode in (7, 9) else "fill" if mode == 8 else "negative"
        result.append(Case(f"runtime-limited/errors/{mode}", "runtime_limited_errors", f"{mode}\n", "cap\n" if mode == 11 else "", exit_code=1, diagnostic=diagnostic, group="aggregate"))
    result.append(Case("variable/owned-values", "variable_arrays", stdout="[3, 4] [13, 4] [7, 8]\n[14] 2 [14, 99]\n[20, 21] 8\nhello\n[8, 9]\n9\n[5, 6] 0 [30, 31] [5, 6, 7]\n[40]\n[15, 6] 15 [15, 6]\n", group="aggregate"))
    for n in (0, 3):
        answer = (f"2 {n + 1} 2\n[{n}, {n + 1}] [{n + 10}, {n + 11}] 4\n[1, 2] [1, 2]\n"
                  f"[{n}, {n + 1}]\n[2, {2 * n + 1}]\n"
                  f"{n + 20}\n{2 * n + 65}\n{2 * n + 85}\n"
                  f"{2 * n + (101 if n > 0 else 121)} {2 * n + 145}\n{2 * n + 165}\n"
                  f"{2 * n + (181 if n == 0 else 201)}\n{2 * n + 221} 15\n-1\n100\n3 3\n{n} ok [2, {2 * n + 1}]\n")
        result.append(Case(f"temporary/owned-values/{n}", "anonymous_values", f"{n}\n", answer, group="aggregate"))
    result.append(Case("growable/minimal", "growable_minimal", stdout="1\n", group="aggregate"))
    result.append(Case("dynamic/forwarding", "dynamic_forwarding", stdout="1\n", group="aggregate"))
    result.append(Case("dynamic/mixed-minimal", "dynamic_result_minimal", stdout="1\n", group="aggregate"))
    result.append(Case("dynamic/adapted-minimal", "dynamic_result_adaptation", stdout="[1, 2] 3\n", group="aggregate"))
    for n in (0, 3):
        answer = (f"[{n}, {n + 1}] {n + 2}\n[7, 8] [{n}, {n + 1}] [{n + 2}] [20, 21]\n"
                  "[107, 8] [20, 21] 77 88\n44 55 5\n[8, 9] 6 67\n[30, 67] 9\n")
        result.append(Case(f"dynamic/adapted-channels/{n}", "dynamic_adapted_channels", f"{n}\n", answer, group="aggregate"))
    for n in (0, 3):
        answer = (f"[{n}, {n + 1}]\n[{n + 2}, {n + 3}]\n" +
                  ("[7, 8]\n" if n > 0 else "[]\n") + "[33]\n[33] [34]\n[34] [35]\n[42, 44] [20]\n" +
                  ("7 3 1\n8 4 10\n" if n > 0 else "0 3 1\n0 2 0\n") +
                  "[5, 6]\n70 71 [72]\n3 1\n")
        result.append(Case(f"dynamic/assignment/{n}", "dynamic_assignments", f"{n}\n", answer, group="aggregate"))
    for n, answer in ((-1, "[1] [1] [99] [] 1\n[9]\n"),
                      (0, "[2] [2] [] [] 1\n[10]\n"),
                      (3, "[3, 4] [5] [3, 4] [8, 9] 1\n[13]\n")):
        result.append(Case(f"dynamic/control/{n}", "dynamic_control", f"{n}\n", answer, group="aggregate"))
    for n in (0, 3):
        answer = (f"{n} [{n + 1}, 99] [{n + 2}, {n + 3}] [{n + 4}]\n"
                  f"[{n + 10}] {n + 10} [{n + 10}]\n[{n + 10}] 2 [{n + 10}, 99]\n" +
                  (f"[{n}] [{n + 1}]\n" if n > 0 else f"[{n + 1}] [{n}]\n") +
                  f"[{n}] 2 [{n + 10}, 99]\n" +
                  ("[7] 8 [9]\n" if n > 0 else "[1, 2] 3 [4]\n") + "[20] 30 [40]\n")
        result.append(Case(f"dynamic/result-channels/{n}", "dynamic_result_channels", f"{n}\n", answer, group="aggregate"))
    for n in (0, 3):
        answer = (f"{106 + n} [5]\n[5] [5, 99]\n104 [5, 30]\n305 [5, 30]\n{n + 103} 109 110 4\n"
                  "[12, 3] 3 18\n20 [30, 10]\n900000 20 [30, 10] [5, 30]\n")
        result.append(Case(f"dynamic/owned-parameters/{n}", "dynamic_parameters", f"{n}\n", answer, group="aggregate"))
    result.append(Case("dynamic/owned-inline-parameter", "dynamic_parameter_inline", "103\n", "2\n", group="aggregate"))
    for n in (-1, 0, 3):
        answer = (f"[{n}, {n + 1}] [{n + 10}, {n + 11}] [7, 8] 3\n"
                  f"[{n}, {n + 2}] " + (f"[{n}, {n + 1}]" if n > 0 else "[]") +
                  " " + ("[-1]" if n < 0 else f"[{n * 2}]") + "\n"
                  f"[{n + 3}, {n + 4}] [9, 10, 11]\n[{n + 5}] [1, 9]\n[20, 22] [41]\n" +
                  ("[7, 8] " if n > 0 else "[1, 2, 3] ") + (f"[{n + 100}]" if n > 0 else "[0]") +
                  f"\n44 55\n25010000 [{n}, {n + 1}] [{n + 10}, {n + 11}] 3\n")
        result.append(Case(f"dynamic/owned-results/{n}", "dynamic_returns", f"{n}\n", answer, group="aggregate"))
    for debug in (False, True):
        result.append(Case("growable/owners-and-stable-views" + ("-debug" if debug else ""), "growable_arrays",
                           stdout="[]\n[5]\n5001 5000 12 12 1 4999 -4999\n[77, 0, 1] 12\n5001 88 12\n"
                           "[1, 2, 3, 3, 3] 3\n[7, 9, 7, 9]\n[2, 3, 2, 3]\n"
                           "[1, 2] 9 [1, 2, 3]\n[1, 2, 3, 4, 3, 2, 1]\n[1, 2, 3, 4, 3, 2, 1, 6] [50]\n"
                           "abc!def\n[6, 6, 6]\n[0, 0, 0]\n[30, 31] 1\n1 4 1\n40 50\n25005000 210\n20 210\n",
                           debug=debug, group="aggregate"))
        for mode, diagnostic in enumerate(("negative", "pop", "pop", "pop", "fill", "bounds", "bounds", "bounds")):
            index = -1 if mode == 6 else 3 if mode == 7 else 2
            result.append(Case(f"growable/errors/{mode}" + ("-debug" if debug else ""), "growable_errors",
                               f"{mode}\n{index}\n", exit_code=1, diagnostic=diagnostic, debug=debug, group="aggregate"))
    result.append(Case("storage/locations-and-copies", "storage_locations",
                       stdout="30 40 10\n35 41 2\n12 8\n21 22 13\n35 41\n", group="aggregate"))
    result.append(Case("storage/cleanup-exits", "cleanup_exits", stdout="49995000\n",
                       group="aggregate", maximum_pages=1))
    result.append(Case("storage/cleanup-preserves-outer-print", "cleanup_nested_loop", stdout="abc 7 8\n",
                       group="aggregate", maximum_pages=1))
    limited_answer = ("0 8 []\n[1, 2, 3, 4] [1, 2] 4 8\n[1, 2, 3, 4, 9, 9]\n9\n[1, 2, 3]\n0\n"
                      "[7, 9]\n[7, 9]\n[7, 9, 7, 9]\n[10, 11, 12] [30, 31, 32] [20, 21, 22]\n"
                      "[77, 11, 12] [10, 11, 12]\n[1, 2] 5 [99, 2, 3]\n"
                      "[99, 2, 3] 5 [99, 2, 3, 3]\n[99, 2, 3, 3, 6] [50]\n"
                      "[6, 6, 6] 3\n0 0\n[] 4\nabc!\n"
                      "[10, 11, 12]\n2 5 42\n[14, 13] 14 0\n1\n[2, 3, 2, 3]\n"
                      "[10, 11, 12] [10, 11, 12]\n500532\n")
    for debug in (False, True):
        result.append(Case("limited/values" + ("-debug" if debug else ""), "limited_arrays",
                           stdout=limited_answer, debug=debug, group="aggregate"))
        result.append(Case("limited/paths" + ("-debug" if debug else ""), "limited_array_paths",
                           stdout="9\n9 1\n2 2\n1\n30 30 40 2\n10 23 23 10\n6\n6\n1\n6\n6\n6\n", debug=debug, group="aggregate"))
        for mode, diagnostic in enumerate(("capacity", "capacity", "capacity", "negative", "pop", "pop",
                                           "pop", "fill", "bounds", "bounds", "capacity")):
            result.append(Case(f"limited/errors/{mode}" + ("-debug" if debug else ""), "limited_array_errors",
                               f"{mode}\n2\n", exit_code=1, diagnostic=diagnostic, debug=debug, group="aggregate"))
    result.append(Case("checked-callers/diamond", "scalar_callers", stdout="18 0 22 72\n"))
    for n in (-1, 0, 4):
        result.append(Case(f"enums/layouts/{n}", "fixed_enums", f"{n}\n",
                           f"20 11.5\n10 {n + 0.5}\n20 0.0\n50\n{n + 2}\n7 9\n77\n8\n10\n1 2 5\n{2 * n + 1}\n{n + 200}\n", group="aggregate"))
        def score(value):
            return -1 if value < 0 else 30 if value == 0 else 3 * value + 3
        result.append(Case(f"enums/returns/{n}", "enum_returns", f"{n}\n",
                           f"{score(n)} {score(n + 1)} 57\n{score(n)} {n * 2} {n + 7}\n{n + 50}\n"
                           f"-1 {n} 6\n{9 if n > 0 else 19} {22 if n == 0 else 12}\n{n + 100}\n", group="aggregate"))
        result.append(Case(f"enums/snapshots/{n}", "enum_snapshots", f"{n}\n",
                           f"66 -1 66\n{n} {n + 1} {n + 2} -1\n15 99 -1\n6 123\n6\n", group="aggregate"))
    for a, b in ((17, 5), (-7, 3), (-7, -3), (0, 2), (1099511627779, 17)):
        quotient = abs(a) // abs(b)
        if (a < 0) != (b < 0):
            quotient = -quotient
        numbers = f"{a + b} {a - b} {a * b} {quotient} {a % abs(b)}\n"
        comparisons = " ".join(str(x).lower() for x in (a < b, a <= b, a == b, a != b, a > b, a >= b))
        bits = f"{a & b} {a | b} {a ^ b}\n"
        result.append(Case(f"arithmetic/{a}/{b}", "scalar_arithmetic", f"{a} {b}\n", numbers + comparisons + "\n" + bits))
    for n in (0, 1, 8, 20):
        total = sum(i * i for i in range(min(n, 12)) if i % 3 != 1) + n * (n + 1) // 2
        answer = total - 100 if total > 100 else total + 100
        result.append(Case(f"control/{n}", "control_flow", f"{n}\n", f"{answer}\n"))
    for n, answer in ((0, 0), (1, 1), (10, 55), (20, 6765)):
        result.append(Case(f"recursion/{n}", "recursion", f"{n}\n", f"{answer} {n * 2}\n"))
    for n in (127, 255, -129, 65535, 2147483648, 4294967295):
        values = [wrap(n, 8), wrap(n, 8, False), wrap(n, 16), wrap(n, 16, False), wrap(n, 32), wrap(n, 32, False)]
        a, b = wrap(values[0] + 1, 8), wrap(values[1] + 1, 8, False)
        text = " ".join(map(str, values)) + f"\n{a} {b}\n{wrap(a << 1, 8)} {a >> 1} {b >> 1}\n"
        result.append(Case(f"narrow/{n}", "narrow_integers", f"{n}\n", text))
    result.extend([
        Case("narrow/division-wrap", "narrow_division", "-2147483648 -1\n", "-2147483648 0\n"),
        Case("narrow/debug-division", "narrow_division", "-2147483648 -1\n", exit_code=1, diagnostic="overflow", debug=True),
        Case("narrow/debug-add", "narrow_integers", "127\n", "127 127 127 127 127 127\n", 1, "overflow", True),
        Case("float/exact", "float_operations", "2.5 0.5\n", "3.0 2.0 1.25 5.0\n3.0 1.25 5.0\nfalse false true\n"),
        Case("float/rounding", "float_operations", "9 0.1\n"),
        Case("float/nan", "float_operations", "nan 1\n"),
        Case("float/cast-release", "float_to_integer", "1.5\n", "1\n"),
        Case("float/cast-debug", "float_to_integer", "1.5\n", exit_code=1, diagnostic="conversion", debug=True),
        Case("short-circuit/false", "short_circuit", "-5\n", "false\ntrue\n5\n"),
        Case("short-circuit/true", "short_circuit", "5\n", "called\ntrue\ncalled\ntrue\n15\n"),
        Case("assert/pass", "assertion", "1\n", "accepted\n"),
        Case("assert/fail", "assertion", "0\n", exit_code=1, diagnostic="assert"),
        Case("abort/message", "abort", exit_code=1, diagnostic="custom abort message"),
        Case("division/zero", "scalar_arithmetic", "7 0\n", exit_code=1, diagnostic="division by zero"),
        Case("division/i64-overflow", "scalar_arithmetic", "-9223372036854775808 -1\n", exit_code=1, diagnostic="overflow"),
        Case("remainder/minus-one", "remainder", "-9223372036854775808 -1\n", "0\n"),
        Case("remainder/minimum-divisor", "remainder", "-7 -9223372036854775808\n", "9223372036854775801\n"),
        Case("exit/seven", "exit", "7\n", "before exit\n", exit_code=7),
        Case("arrays/fixed", "fixed_arrays", "4\n", "12 33 180\n4 90\n", group="aggregate"),
        Case("storage/sparse-data", "static_data", "255\n", "0 0 17 29\n255 0 20\nA\0B\n\0C\0D\0\n", group="aggregate"),
        Case("arrays/valid-index", "array_bounds", "1\n", "5\n", group="aggregate"),
        Case("arrays/upper-bound", "array_bounds", "3\n", exit_code=1, diagnostic="bounds", group="aggregate"),
        Case("arrays/negative-index", "array_bounds", "-1\n", exit_code=1, diagnostic="bounds", group="aggregate"),
        Case("struct/fields", "struct_values", "5\n", "25 17\n", group="aggregate"),
        Case("values/references-match-and-snapshots", "value_forms", "3\n", "6 10 1\n30 10 11\n10 10 6 2\ninner\nabc 9\n", group="aggregate"),
        Case("values/nullable-identity-copy", "nullable_and_copy", "4\n", "true\ntrue\n4\ntrue false\n[1, 2, 3] [9, 2, 3]\n", group="aggregate"),
        Case("values/inline-print-unwind", "inline_print_unwind", "1\n", "50005000\n", group="aggregate"),
        Case("values/implicit-references", "implicit_references", stdout="6 [1, 6, 3] 9\n", group="aggregate"),
        Case("unsigned/u64-boundaries", "unsigned_wide", "-1 -9223372036854775808\n", "18446744073709551615 9223372036854775808 1 9223372036854775807 9223372036854775807 0\n"),
    ])
    values = ["0", "-0.0", "nan", "inf", "-inf", "0.1", "0.0001", "0.00001", "1e15", "1e14", "1e20", "1.2345678901234567", "3.4028234663852886e38", "1.401298464324817e-45", "5e-324", "1.7976931348623157e308"]
    rng = random.Random(7931)
    for _ in range(96):
        value = struct.unpack("<f", struct.pack("<I", rng.randrange(1 << 32)))[0]
        values.append(repr(value))
    for _ in range(96):
        value = struct.unpack("<d", struct.pack("<Q", rng.randrange(1 << 64)))[0]
        values.append(repr(value))
    result.append(Case("float/render-corpus", "float_render", str(len(values)) + "\n" + "\n".join(values) + "\n"))
    edges = [0.0, -0.0, 1.0, -1.0, 5.5, -5.5, float("inf"), float("-inf"), float("nan"),
             5e-324, 1.5e-323, 2.2250738585072014e-308, 2.225073858507201e-308,
             1.7976931348623157e308, 1e308, 1.401298464324817e-45, 4.203895392974451e-45,
             1.1754943508222875e-38, 1.1754942106924411e-38, 3.4028234663852886e38]
    pairs = [(a, b) for a in edges for b in edges]
    for fmt, integer, bits in (("<f", "<I", 32), ("<d", "<Q", 64)):
        for _ in range(128):
            pairs.append(tuple(struct.unpack(fmt, struct.pack(integer, rng.randrange(1 << bits)))[0] for _ in range(2)))
    # Values immediately around the subtraction/scaling boundaries.
    for value in (1.0, 1e308, 2.2250738585072014e-308):
        pairs.extend([(math.nextafter(value, 0.0), value), (math.nextafter(value, float("inf")), value)])
        if math.isfinite(2 * value):
            pairs.extend([(math.nextafter(2 * value, 0.0), value), (math.nextafter(2 * value, float("inf")), value)])
    data = str(len(pairs)) + "\n" + "".join(f"{a!r} {b!r}\n" for a, b in pairs)
    result.append(Case("float/remainder-corpus", "float_remainder", data))
    for original in list(result):
        if original.fixture in ("frame_structs", "nested_owned_structs", "variable_enum_tails"):
            result.append(replace(original, name="owned-nonlocal/coexist/" + original.name,
                                  fixture="nonlocal_owned_coexist_" + original.fixture))
    return result


def execute(command, *, cwd, stdin="", timeout=180):
    started = time.perf_counter_ns()
    result = subprocess.run([str(x) for x in command], cwd=cwd, input=stdin, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
    return result, (time.perf_counter_ns() - started) / 1e9


def save_log(directory, name, command, result):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{name}.command.json").write_text(json.dumps([str(x) for x in command], indent=2) + "\n", encoding="utf-8")
    (directory / f"{name}.stdout").write_text(result.stdout, encoding="utf-8")
    (directory / f"{name}.stderr").write_text(result.stderr, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--emcc", default=os.environ.get("EMCC", "emcc"))
    parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
    parser.add_argument("--node", default="node")
    parser.add_argument("--engines", nargs="+", choices=("v8", "wasmtime"), default=["v8", "wasmtime"])
    parser.add_argument("--backends", nargs="+", choices=("direct", "c-wasm", "native"), default=["direct", "c-wasm", "native"])
    parser.add_argument("--levels", nargs="+", type=int, choices=(0, 1, 2), default=[0, 2])
    parser.add_argument("--scalar-only", action="store_true")
    parser.add_argument("--filter", default="")
    parser.add_argument("--skip-refusals", action="store_true")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build" / "differential")
    args = parser.parse_args()
    args.goose = args.goose.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    selected = [case for case in cases() if args.filter in case.name and (not args.scalar_only or case.group == "scalar")]
    if not selected:
        parser.error("no cases selected")
    compiled = {}
    rows = []
    native_observations = {}
    order = [name for name in ("native", "c-wasm", "direct") if name in args.backends]
    for level in args.levels:
        for backend in order:
            for case in selected:
                if level not in case.levels:
                    continue
                key = (backend, case.fixture, case.debug, level, case.maximum_pages)
                directory = output / f"O{level}" / ("debug" if case.debug else "release") / case.fixture / backend
                if case.maximum_pages is not None:
                    directory = directory / f"memory-{case.maximum_pages}"
                if key not in compiled:
                    directory.mkdir(parents=True, exist_ok=True)
                    suffix = ".bin" if backend == "native" else ".wasm"
                    artifact = directory / ("program" + suffix)
                    build = [sys.executable, ROOT / "scripts" / "goose_wasm.py", "build", FIXTURES / f"{case.fixture}.goose", "-o", artifact,
                             "--backend", backend, f"-O{level}", "--goose", args.goose, "--no-cache", "--offline"]
                    if backend != "direct":
                        build += ["--c-source", ROOT / "bench" / "host_input.c", "--cc", args.cc, "--emcc", args.emcc]
                    if case.debug:
                        build.append("--debug")
                    if backend == "direct" and case.maximum_pages is not None:
                        build += ["--initial-pages", "1", "--maximum-pages", str(case.maximum_pages)]
                    result, seconds = execute(build, cwd=ROOT)
                    save_log(directory, "compile", build, result)
                    compiled[key] = (artifact, result, seconds)
                artifact, built, compile_seconds = compiled[key]
                engines = ["native"] if backend == "native" else args.engines
                for engine in engines:
                    row = {"case": case.name, "fixture": case.fixture, "backend": backend, "engine": engine,
                           "optimization": level, "debug": case.debug, "compile_seconds": compile_seconds,
                           "direct_maximum_pages": case.maximum_pages if backend == "direct" else None}
                    try:
                        if built.returncode:
                            raise AssertionError("compile failed: " + (built.stdout + built.stderr)[-2000:])
                        if engine == "native":
                            command = [artifact]
                        elif engine == "v8":
                            command = [args.node, ROOT / "scripts" / "run_wasm.mjs", artifact]
                        else:
                            command = [sys.executable, ROOT / "scripts" / "run_wasmtime.py", artifact]
                        result, seconds = execute(command, cwd=directory, stdin=case.stdin, timeout=30)
                        label = case.name.replace("/", "_") + "_" + engine
                        save_log(directory, label, command, result)
                        row.update(run_seconds=seconds, exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr)
                        if result.returncode != case.exit_code:
                            raise AssertionError(f"exit {result.returncode}, expected {case.exit_code}: {result.stderr[-1500:]}")
                        if case.diagnostic and case.diagnostic not in result.stderr.lower():
                            raise AssertionError(f"missing {case.diagnostic!r} diagnostic: {result.stderr[-1500:]}")
                        if case.stdout is not None and result.stdout != case.stdout:
                            raise AssertionError(f"stdout {result.stdout!r}, expected {case.stdout!r}")
                        reference_key = (case.name, level, case.debug)
                        if backend == "native":
                            native_observations[reference_key] = result.stdout
                        elif reference_key in native_observations and result.stdout != native_observations[reference_key]:
                            raise AssertionError(f"stdout differs from native Goose: {result.stdout!r} != {native_observations[reference_key]!r}")
                        row.update(status="pass", module_bytes=artifact.stat().st_size,
                                   sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())
                    except (AssertionError, OSError, subprocess.TimeoutExpired) as failure:
                        row.update(status="fail", error=str(failure))
                    rows.append(row)
                    print(f"{row['status'].upper()} O{level} {backend}/{engine} {case.name}", flush=True)
                    if row["status"] == "fail":
                        print(row["error"], flush=True)
    # The direct fragment must explicitly refuse these valid Goose programs.
    if "direct" in args.backends and not args.filter and not args.skip_refusals:
        for fixture in ("unsupported_varint_array", "unsupported_pointer_extern", "invalid_source"):
            directory = output / "refusals" / fixture
            directory.mkdir(parents=True, exist_ok=True)
            artifact = directory / "program.wasm"
            command = [sys.executable, ROOT / "scripts" / "goose_wasm.py", "build", FIXTURES / f"{fixture}.goose",
                       "-o", artifact, "--backend", "direct", "--goose", args.goose, "--no-cache", "--offline"]
            result, seconds = execute(command, cwd=ROOT)
            save_log(directory, "compile", command, result)
            passed = result.returncode != 0 and not artifact.exists()
            diagnostic = result.stdout + result.stderr
            if fixture == "invalid_source":
                passed = passed and "unknown escape" in diagnostic
            else:
                passed = passed and any(word in diagnostic.lower() for word in ("unsupported", "does not support", "not supported", "direct target"))
            rows.append({"case": fixture, "backend": "direct", "kind": "compile-refusal", "status": "pass" if passed else "fail",
                         "compile_seconds": seconds, "diagnostic": diagnostic})
            print(("PASS " if passed else "FAIL ") + fixture, flush=True)
    failures = sum(row["status"] != "pass" for row in rows)
    report = {"schema": "goose-direct-differential-v1", "platform": platform.platform(),
              "python": sys.version, "toolchain": json.loads((ROOT / "toolchain.json").read_text()),
              "compiler_sha256": hashlib.sha256(args.goose.read_bytes()).hexdigest(),
              "configuration": {"backends": args.backends, "levels": args.levels,
                                "filter": args.filter, "skip_refusals": args.skip_refusals},
              "cases": len(selected), "observations": len(rows), "failures": failures, "results": rows}
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{len(rows) - failures}/{len(rows)} observations passed; {report_path}")
    return int(failures != 0)


if __name__ == "__main__":
    sys.exit(main())
