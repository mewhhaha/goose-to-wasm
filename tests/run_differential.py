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


def cases():
    result = [Case("checked-leaves/scalars", "checked_leaves", stdout="65 70 true\n25 63 4.25\n7 6 7 9\n-inf 1.25 -2.0\n")]
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
    if "direct" in args.backends and not args.filter:
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
              "cases": len(selected), "observations": len(rows), "failures": failures, "results": rows}
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{len(rows) - failures}/{len(rows)} observations passed; {report_path}")
    return int(failures != 0)


if __name__ == "__main__":
    sys.exit(main())
