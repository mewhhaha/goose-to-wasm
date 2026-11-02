#!/usr/bin/env python3
"""Check the independent answers used to qualify warmed example adapters."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("reference_examples", ROOT / "bench/reference_examples.py")
REFERENCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REFERENCE)


class ReferenceExamples(unittest.TestCase):
    def test_splitmix_known_stream(self):
        self.assertEqual(list(REFERENCE.random_words(0, 3)),
                         [0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F])

    def test_bitplane_life_matches_scalar_on_every_small_torus(self):
        for width, height in [(2, 2), (3, 3)]:
            for bits in range(1 << (width * height)):
                rows = [(bits >> (y * width)) & ((1 << width) - 1) for y in range(height)]
                expected = []
                for y in range(height):
                    row = 0
                    for x in range(width):
                        neighbours = 0
                        for dy in (-1, 0, 1):
                            for dx in (-1, 0, 1):
                                if dx == 0 and dy == 0:
                                    continue
                                neighbours += (rows[(y + dy) % height] >> ((x + dx) % width)) & 1
                        alive = (rows[y] >> x) & 1
                        if neighbours == 3 or (alive and neighbours == 2):
                            row |= 1 << x
                    expected.append(row)
                self.assertEqual(REFERENCE.life_step(rows, width), expected)

    def test_sudoku_solutions_and_search_counts(self):
        for puzzle, expected_guesses in zip(REFERENCE.PUZZLES, (51, 10101)):
            cells, guesses = REFERENCE.solve_sudoku(puzzle)
            self.assertEqual(guesses, expected_guesses)
            for index, given in enumerate(puzzle):
                if given != ".":
                    self.assertEqual(cells[index], int(given))
            for y in range(0, 9, 3):
                for x in range(0, 9, 3):
                    self.assertEqual({cells[(y + dy) * 9 + x + dx]
                                      for dy in range(3) for dx in range(3)}, set(range(1, 10)))

    def test_staging_retains_original_algorithm_prefixes(self):
        with tempfile.TemporaryDirectory() as temporary:
            import json
            output = Path(temporary)
            manifest = json.loads(REFERENCE.stage(output).read_text())
            self.assertEqual(len(manifest["cases"]), 3)
            for case in manifest["cases"]:
                original = Path(case["original"]).read_text().partition("\nfn main() {")[0]
                staged = (output / case["source"]).read_text()
                self.assertTrue(staged.startswith(original))
                self.assertEqual(staged.count("\nfn main() {"), 1)
                for profile in ("test", "run"):
                    self.assertGreaterEqual(case[profile]["checksum"], 0)


if __name__ == "__main__":
    unittest.main()
