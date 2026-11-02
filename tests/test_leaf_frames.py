#!/usr/bin/env python3
"""Qualify frame-free numeric leaves and ownership/addressing fallbacks."""
import argparse
from pathlib import Path
import subprocess
import sys
import unittest

import test_prefix_resolution as prefix
import test_strip_loops as strip
from test_fill_loops import function_body

POSITIVE = '''extern fn root(x:f64)->f64="sqrt";
recursive fn kernel(xs:i64[:],limit:i64)->i64 {
    var sum=0;
    for i in xs.len {
        if i==1 { continue; }
        sum+=xs[i]; if sum>limit { return sum; }
    }
    return sum;
}
recursive fn numeric(x:f64)->f64 { root(x)+1.0 }
fn main() {
    var rows:i64[>..]=[2,3,4,5]; var captured=0;
    recursive fn touch() { captured++; }
    touch(); print(kernel(rows,100)," ",kernel(rows,3)," ",numeric(9.0)," ",captured);
}
'''
FALLBACK = '''recursive fn referenced(value:i64)->i64 {
    let alias:i64& = value; alias+=2; return alias;
}
recursive fn called(value:i64)->i64 { referenced(value) }
recursive fn produced()->i64[>..] { return [7,8]; }
recursive fn viewed(xs:i64[:])->i64 {
    for &x in xs { x+=1; }
    return xs[0];
}
fn main() {
    var rows:i64[>..]=produced();
    print(referenced(3)," ",called(4)," ",viewed(rows)," ",rows);
}
'''
PREFIX = prefix.ENABLE+'''struct Packet { head:i64[2], values:i64[>..] }
recursive fn make(n:i64)->Packet { return Packet {[n,n+1],[9]}; }
recursive fn read_prefix(xs:i64[:])->i64 {
    var total=0; for value in xs { total+=value; } return total;
}
fn main() {
    let packet=make(10); let kept=packet.head[..]; let temporary=make(3);
    print(read_prefix(kept)," ",read_prefix(temporary.head[..])," ",packet.values[0]);
    packet.head[0]+=2;
    print(read_prefix(kept)," ",packet.head[0]," ",enable().len);
}
'''
RECURSIVE = prefix.ENABLE+'''struct Board { cells:i64[4], marker:i64 }
struct Packet { board:Board, values:i64[>..] }
recursive fn make(n:i64)->Packet {
    recursive fn observe()->i64 { return n+1; }
    return Packet {Board {[n,observe(),n+2,n+3],20},[9]};
}
recursive fn score(b:Board&)->i64 { b.cells[0]+b.cells[1]+b.cells[2]+b.cells[3]+b.marker }
recursive fn place(b:Board&,n:i64) { b.cells[0]+=n; b.marker++; }
recursive fn unplace(b:Board&,n:i64) { b.cells[0]-=n; b.marker--; }
recursive fn solve(b:Board&,n:i64)->i64 {
    if n==0 { return score(b); }
    place(b,n); let value=solve(b,n-1); unplace(b,n); return value+score(b);
}
recursive fn even(b:Board&,n:i64)->i64 {
    if n==0 { return score(b); }
    place(b,n); let value=odd(b,n-1); unplace(b,n); return value+1;
}
recursive fn odd(b:Board&,n:i64)->i64 {
    if n==0 { return score(b); }
    place(b,n); let value=even(b,n-1); unplace(b,n); return value+2;
}
fn main() {
    let packet=make(10); let board:Board& = packet.board; let temporary=make(3);
    print(solve(board,3)," ",score(board)," ",even(board,4)," ",score(board)," ",packet.values[0]);
    print(enable().len);
}
'''
UNSAFE_CYCLE = '''recursive fn cycle_a(n:i64)->i64 {
    if n>0 { return cycle_b(n-1); } return 1;
}
recursive fn cycle_b(n:i64)->i64 {
    if n>0 { return cycle_a(n-1); } return bad_owner();
}
recursive fn bad_owner()->i64 { var values:i64[>..]=[7]; return values[0]; }
fn main() { print(cycle_a(2)," ",cycle_b(2)); }
'''
AGGREGATES = '''struct Fixed { values:i64[2] }
struct Links { value:i64& }
recursive fn replace(var dst:Fixed&,src:Fixed&) { dst=src; }
recursive fn by_value(value:Fixed)->i64 { value.values[0] }
recursive fn embedded(links:Links&)->i64 { links.value }
recursive fn alias(value:i64)->i64 { let kept:i64& = value; kept+=2; return kept; }
recursive fn local_array(n:i64)->i64 { var values=[n,n+1]; return values[0]; }
fn main() {
    var a=Fixed {[1,2]}; var b=Fixed {[7,8]}; var value=10; var links=Links {value};
    replace(a,b); print(a.values[0]," ",by_value(a)," ",embedded(links)," ",alias(3)," ",local_array(5));
}
'''
SUDOKU_SHAPE = '''struct Board { cells:u8[81], rows:u16[9], cols:u16[9], boxes:u16[9] }
fn bit(d:u8)->u16 { (1<<d) as! u16 }
fn box_of(i:i64)->i64 { (i/27)*3+(i%9)/3 }
recursive fn count_bits(mask:u16)->i64 {
    var bits=mask; var count=0; while bits!=0 { bits&=bits-1; count++; } return count;
}
fn place(b:Board&,i:i64,d:u8) {
    b.cells[i]=d; b.rows[i/9]|=bit(d); b.cols[i%9]|=bit(d); b.boxes[box_of(i)]|=bit(d);
}
fn unplace(b:Board&,i:i64,d:u8) {
    b.cells[i]=0; b.rows[i/9]&=~bit(d); b.cols[i%9]&=~bit(d); b.boxes[box_of(i)]&=~bit(d);
}
fn candidates(b:Board&,i:i64)->u16 {
    let used=b.rows[i/9]|b.cols[i%9]|b.boxes[box_of(i)]; ~used&0x3FE
}
recursive fn probe(b:Board&,i:i64,d:u8)->i64 {
    place(b,i,d); let result=count_bits(candidates(b,i)); unplace(b,i,d); return result;
}
fn main() {
    var b=Board {[0;81],[0;9],[0;9],[0;9]}; print(probe(b,0,1)," ",b.cells[0]," ",b.rows[0]);
}
'''
INLINE_RETURNS = '''inline fn inner(n:i64)->i64 {
    if n<0 { return -n from inner; } if n==0 { return 3; } return n+2;
}
inline fn outer(n:i64)->i64 {
    if n==7 { return inner(-n); } let value=inner(n);
    if value>5 { return value*2; } return value+1;
}
recursive fn evaluate(n:i64)->i64 { let value=outer(n); return value+1; }
fn main() { print(evaluate(-2)," ",evaluate(0)," ",evaluate(7)," ",evaluate(10)); }
'''
INLINE_FALLBACK = '''inline fn adjust(n:i64)->i64 { if n==0 { return 1; } return n+1; }
inline fn owner(n:i64)->i64[>..] { return [n]; }
recursive fn produce(n:i64)->i64[>..] { return [n,n+1]; }
recursive fn take(value:i64&)->i64 { value+=1; return value; }
fn owner_result(n:i64)->i64 { let values=owner(n); return values[0]; }
fn allocation_arg(n:i64)->i64 { adjust(produce(n)[0]) }
fn addressed_arg(var n:i64)->i64 { adjust(take(n)) }
recursive fn default_value()->i64 { var values:i64[>..]=[9]; return values[0]; }
struct Defaulted { value:i64=default_value() }
inline fn defaults(n:i64)->i64 { let item=default<Defaulted>(); return item.value+n; }
fn default_arg(n:i64)->i64 { adjust(defaults(n)) }
inline fn escape_inner(n:i64)->i64 { if n<0 { return 7 from escape_outer; } return n+2; }
inline fn escape_outer(n:i64)->i64 { return escape_inner(n)+1; }
fn escape(n:i64)->i64 { escape_outer(n) }
fn captured_input(n:i64)->i64 {
    let extra=n+3; inline fn add(value:i64)->i64 { return extra+value; } return add(n);
}
recursive fn driver() {
    print(owner_result(2)," ",allocation_arg(4)," ",addressed_arg(5)," ",default_arg(1)," ",
          escape(-1)," ",escape(2)," ",captured_input(4));
}
fn main() { driver(); }
'''


class LeafFrames(unittest.TestCase):
    setUp = strip.StripLoops.setUp
    compile = strip.StripLoops.compile
    native = prefix.PrefixResolution.native

    def qualify(self, source, expected, names, frame_free, prefix_mapping=False, clone_prefix=None):
        for level in (0,2):
            for debug in (False,True):
                path,stats=self.compile(level,debug=debug,text=source)
                if prefix_mapping:
                    self.assertGreater(stats["region_count"],0)
                    self.assertGreater(next(item["code_bytes"] for item in stats["function_info"]
                                            if item["name"] == "resolve_prefix"),8)
                targets = list(names)
                if clone_prefix:
                    clones = [item["name"].split("#")[0] for item in stats["function_info"]
                              if item["name"].startswith(clone_prefix)]
                    self.assertEqual(len(clones),1)
                    targets += clones
                for name in targets:
                    ops=list(strip.instructions(function_body(path,stats,name)))
                    with self.subTest(level=level,debug=debug,function=name):
                        if frame_free:
                            self.assertNotIn(0x23,ops)
                            self.assertNotIn(0x24,ops)
                        else:
                            self.assertIn(0x24,ops)
                self.assertEqual(self.native(self.work/"main.goose",level),expected)
                for engine,command in (
                    ("v8",[strip.NODE,str(strip.ROOT/"scripts/run_wasm.mjs"),str(path)]),
                    ("wasmtime",[sys.executable,str(strip.ROOT/"scripts/run_wasmtime.py"),str(path)]),
                ):
                    with self.subTest(level=level,debug=debug,engine=engine):
                        result=subprocess.run(command,capture_output=True,text=True,timeout=30)
                        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                        self.assertEqual(result.stdout,expected)

    def test_numeric_views_intrinsics_and_unrelated_captures_need_no_frame(self):
        self.qualify(POSITIVE,"11 6 4.0 1\n",["kernel","numeric"],True)

    def test_addresses_calls_owners_and_reference_loops_keep_frames(self):
        self.qualify(FALLBACK,"5 6 8 [8, 9]\n",["referenced","called","produced","viewed"],False)

    def test_leaf_keeps_caller_prefix_mapping_active(self):
        self.qualify(PREFIX,"21 7 9\n23 12 1\n",["read_prefix"],True)

    def test_recursive_fixed_data_references_keep_caller_prefix_mapping(self):
        self.qualify(RECURSIVE,"284 66 86 66 9\n1\n",
                     ["score","place","unplace","solve","even","odd"],True,prefix_mapping=True)

    def test_recursive_backedge_does_not_publish_success_before_bad_callee(self):
        self.qualify(UNSAFE_CYCLE,"1 7\n",["cycle_a","cycle_b","bad_owner"],False)

    def test_aggregate_copy_materialization_and_embedded_reference_keep_frames(self):
        self.qualify(AGGREGATES,"7 7 10 5 5\n",["replace","by_value","embedded","alias","local_array"],False)

    def test_divisor_clone_keeps_transitive_by_value_parameter_mutation_private(self):
        source = '''var canary:i64[>..]=[99];
recursive fn copy_increment(var value:i64)->i64 { value++; return value; }
recursive fn cloned(value:i64,divisor:i64)->i64 {
    let after=copy_increment(divisor); return value%divisor+after;
}
fn main() { print(cloned(-17,8)," ",cloned(-17,3)," ",canary[0]); }
'''
        self.qualify(source,"16 5 99\n",["copy_increment","cloned"],True,clone_prefix="cloned_const_")

    def test_original_numeric_helpers_can_inline_inside_reference_call_graph(self):
        self.qualify(SUDOKU_SHAPE,"8 0 0\n",["place","unplace","candidates","probe"],True)

    def test_nested_numeric_inline_early_returns_keep_their_lexical_targets(self):
        self.qualify(INLINE_RETURNS,"4 5 8 25\n",["evaluate"],True)

    def test_inline_actual_initializers_owners_defaults_captures_and_nonlocal_returns_keep_frames(self):
        self.qualify(INLINE_FALLBACK,"2 5 7 11 7 5 11\n",
                     ["owner_result","allocation_arg","addressed_arg","default_arg","escape","captured_input"],False)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose",type=Path,default=strip.GOOSE)
    parser.add_argument("--node",default=strip.NODE)
    parser.add_argument("--cc",default=prefix.CC)
    args,remaining=parser.parse_known_args()
    strip.GOOSE=prefix.GOOSE=args.goose.resolve()
    strip.NODE=prefix.NODE=args.node
    prefix.CC=args.cc
    unittest.main(argv=[sys.argv[0],*remaining])
