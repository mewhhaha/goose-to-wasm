#!/usr/bin/env python3
"""Compare arbitrary nested byte output without decoding it as UTF-8."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
GOOSE=ROOT/'build/bin/goose'


class AggregatePrint(unittest.TestCase):
    def test_nested_binary_bytes_agree_with_native(self):
        source='struct Text{bytes:u8[7]} fn main(){print(Text{[255,0,128,34,92,10,9]});}'
        expected=bytes([84,101,120,116,32,123,32,34,255,0,128,92,34,92,92,92,110,92,116,34,32,125,10])
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as directory:
            work=Path(directory);path=work/'main.goose';path.write_text(source)
            for level in (0,2):
                common=[str(GOOSE),str(path),'--offline',f'-O{level}']
                c=work/'native.c';binary=work/'native';wasm=work/'direct.wasm'
                compiled=subprocess.run(common+['--target','native','--standalone','-o',str(c)],capture_output=True)
                self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
                subprocess.run(['cc',str(c),'-lm','-o',str(binary)],check=True,capture_output=True)
                native=subprocess.run([str(binary)],check=True,capture_output=True)
                self.assertEqual(native.stdout,expected)
                compiled=subprocess.run(common+['--target','wasm-direct','-o',str(wasm)],capture_output=True)
                self.assertEqual(compiled.returncode,0,compiled.stdout+compiled.stderr)
                for engine,command in (
                    ('V8',['node',str(ROOT/'scripts/run_wasm.mjs'),str(wasm)]),
                    ('Wasmtime',[sys.executable,str(ROOT/'scripts/run_wasmtime.py'),str(wasm)]),
                ):
                    with self.subTest(level=level,engine=engine):
                        result=subprocess.run(command,check=True,capture_output=True)
                        self.assertEqual(result.stdout,native.stdout)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--goose',type=Path,default=GOOSE)
    args,remaining=parser.parse_known_args();GOOSE=args.goose.resolve()
    unittest.main(argv=[sys.argv[0],*remaining])
