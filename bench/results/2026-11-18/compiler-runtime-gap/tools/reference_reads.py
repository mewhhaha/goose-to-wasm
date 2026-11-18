"""Run beside replay_reads.py with /path/to/reference.cwasm as the argument."""
import json
from pathlib import Path
import sys
from replay_reads import summarize

report = summarize(Path(sys.argv[1]), 'wasm[0]::function[810]::life_replay',
                   0x626e, 0x6295, {})
assert report['instruction_count'] == 8
report.update({
    'goose': [
        'let entry = read; let item: const LifeReadEntry& = l.summary_reads[entry];',
        'let leaf = item.leaf as i64; read = item.next as i64;',
    ],
    'source_change': 'Single checked reference for both fields in life_replay. The surrounding loop and the before comparison are unchanged.',
    'input_wasm_sha256': '98972c6d502dcc204fdbc4f54e76eace7f82453d643c476de42c2f7f6ae54423',
    'name_section_appended_wasm_sha256': '95bdc42358716fa0ebf396f292c1e47669b346e2784e4f911d855085b391ad61',
    'evidence': 'Wasmtime address-map locations 0x6bd6f8 and 0x6bd70a are i32.load in the candidate file. The preceding address adds are 8 (leaf) and 24 (next).',
    'scope': 'Both x86 loads included. The first element address and its guard have already been computed at the start of the counted fragment, just as in replay-reads.json.',
    'reproduce': 'python reference_reads.py /path/to/reference.cwasm',
})
print(json.dumps(report, indent=2))
