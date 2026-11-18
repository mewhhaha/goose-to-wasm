"""Change only the partition boundaries of a fresh instance of the trial compiler."""

import json
import os
from pathlib import Path
import struct
import tempfile

FOOTER = 12
WORD_MASK = 0xFFFFFFFF


def distribute(units, weights):
    total = sum(weights)
    if total == 0:
        if units:
            raise ValueError("no regions for remaining space")
        return [0] * len(weights)
    edges = [0]
    assigned = 0
    for weight in weights:
        assigned += weight
        edges.append(units * assigned // total)
    return [b - a for a, b in zip(edges, edges[1:])]


def read_layout(directory, digest):
    if directory is None:
        return None
    path = directory / (digest + ".json")
    try:
        data = json.loads(path.read_bytes())
    except (FileNotFoundError, ValueError, UnicodeDecodeError):
        return None
    if (
        isinstance(data, dict)
        and data.get("module_sha256") == digest
        and isinstance(data.get("bounds"), list)
    ):
        return data["bounds"]
    return None


def save_layout(directory, digest, bounds):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / (digest + ".json")
    with tempfile.NamedTemporaryFile(dir=directory, mode="w", delete=False) as stream:
        tmp = Path(stream.name)
        try:
            json.dump({"module_sha256": digest, "bounds": bounds}, stream)
            stream.write("\n")
            stream.close()
            os.replace(tmp, path)
        finally:
            tmp.unlink(missing_ok=True)


class Partition:
    def __init__(self, factor, saved=None):
        self.factor = factor
        self.saved = saved
        self.original = None
        self.bounds = None
        self.minimum = []
        self.wanted = []
        self.failures = []
        self.can_retry = False

    def invoke(self, store, exports):
        self.install(exports, store)
        try:
            exports["_start"](store)
        except Exception:
            self.observe_failure(exports, store)
            raise

    def install(self, exports, store):
        self.can_retry = False
        memory = exports["memory"]
        table = exports["goose.region_table"].value(store) & WORD_MASK
        n = exports["goose.region_count"].value(store)
        if not 0 < n <= 65536:
            raise ValueError("invalid region count")
        layout = struct.Struct(f"<{n + 1}I")
        raw = memory.read(store, table, table + layout.size)
        initial = list(layout.unpack(raw))
        widths = [b - a for a, b in zip(initial, initial[1:])]
        if any(w < 24 or w % 8 for w in widths):
            raise ValueError("invalid region partition")
        if self.original is None:
            self.original = initial
            self.bounds = initial
            if self.saved is not None and len(self.saved) == len(initial):
                saved = self.saved
                if (
                    all(type(v) is int for v in saved)
                    and saved[0] == initial[0]
                    and saved[-1] == initial[-1]
                    and all(
                        b - a >= 24 and (b - a) % 8 == 0
                        for a, b in zip(saved, saved[1:])
                    )
                ):
                    self.bounds = saved
            self.minimum = [3] * n
            self.wanted = [0] * n
        if self.original != initial:
            raise ValueError("partition belongs to a different module layout")
        if self.bounds != initial:
            memory.write(store, layout.pack(*self.bounds), table)

    def observe_failure(self, exports, store):
        limit = exports["trial.failed_limit"].value(store) & WORD_MASK
        if not limit:
            return
        bounds = self.bounds
        failed = bounds.index(limit + FOOTER) - 1
        if failed < 0:
            raise ValueError("invalid failed region")
        request = exports["trial.request_bytes"].value(store) & 0xFFFFFFFFFFFFFFFF
        memory = exports["memory"]
        size = memory.data_len(store)
        used = []
        for base, end in zip(bounds, bounds[1:]):
            held = 0
            if end <= size:
                cursor, origin = struct.unpack(
                    "<II", memory.read(store, end - FOOTER, end - 4)
                )
                if origin == base:
                    if not base <= cursor <= end - FOOTER:
                        raise ValueError("invalid region cursor")
                    held = cursor - base
            used.append(held)
        need = used[failed] + request
        if need <= limit - bounds[failed]:
            raise ValueError("unexpected reservation failure")
        self.failures.append(
            dict(
                region=failed,
                used=used[failed],
                request=request,
                capacity=limit - bounds[failed],
            )
        )
        self.can_retry = self.rebalance(used, failed, need)

    def rebalance(self, used, failed, need):
        """Reserve proven needs first. Give more headroom to nearly full regions."""
        sizes = [b - a for a, b in zip(self.bounds, self.bounds[1:])]
        initial = [b - a for a, b in zip(self.original, self.original[1:])]
        budget = sum(sizes) // 8
        for i, (held, size) in enumerate(zip(used, sizes)):
            required = held
            if i == failed:
                required = need
            self.minimum[i] = max(self.minimum[i], (required + FOOTER + 7) // 8)
            if i == failed or 2 * held >= size - FOOTER:
                self.wanted[i] = max(
                    self.wanted[i], (self.factor * required + FOOTER + 7) // 8
                )
        minimum = sum(self.minimum)
        if minimum > budget:
            return False
        spare = budget - minimum
        boosts = [
            max(0, target - low) for target, low in zip(self.wanted, self.minimum)
        ]
        amount = min(spare, sum(boosts))
        extra = distribute(amount, boosts)
        weights = initial.copy()
        for i, target in enumerate(self.wanted):
            if target:
                weights[i] = 0
        if not any(weights):
            weights = initial
        remainder = distribute(spare - amount, weights)
        new = [self.original[0]]
        for low, high, rest in zip(self.minimum, extra, remainder):
            new.append(new[-1] + 8 * (low + high + rest))
        assert new[-1] == self.original[-1]
        if new == self.bounds:
            return False
        self.bounds = new
        return True


def compile_with_recovery(data, prepared, arguments, partition, output=None):
    """Run one frozen compiler request. Only the private output may be replayed."""
    from run_wasmtime import run_module

    attempts = []
    for _ in range(8):
        if output is not None:
            output.unlink(missing_ok=True)
        partition.can_retry = False
        result = run_module(
            data,
            b"",
            arguments=arguments,
            prepared=prepared,
            invoke_start=partition.invoke,
        )
        attempts.append(result["timing"]["start_function_ns"])
        if not partition.can_retry:
            break
    return result, attempts
