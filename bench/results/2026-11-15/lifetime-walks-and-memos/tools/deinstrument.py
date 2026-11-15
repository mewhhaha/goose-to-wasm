"""deinstrument.py IN OUT: remove what progress.py added to a checker_lifetimes.goose."""
import sys
s = open(sys.argv[1]).read()
s = s.replace('import model;\nimport os;', 'import model;', 1)
a = s.index('\nfn dbg_num('); b = s.index('\nfn check_lifetimes(')
s = s[:a] + s[b:]
lines = [l for l in s.split('\n') if 'dbg_' not in l]
open(sys.argv[2], 'w').write('\n'.join(lines))
