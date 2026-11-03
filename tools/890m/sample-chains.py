#!/usr/bin/env python3
# Ancestor chains in a macOS `sample` call graph for nodes matching a regex (outermost match only), with counts.
#   sample-chains.py ws.sample.txt '__ioctl|memmove' [min_count] [depth]
import re
import sys

lines = open(sys.argv[1]).read().split('\n')
pat = re.compile(sys.argv[2])
minc = int(sys.argv[3]) if len(sys.argv) > 3 else 20
depth = int(sys.argv[4]) if len(sys.argv) > 4 else 14
end = next(i for i, l in enumerate(lines) if l.startswith('Total number in stack'))
stack = []
for l in lines[:end]:
    m = re.match(r'^([ +!:|]*)(\d+) (.*)$', l)
    if not m:
        continue
    d, c = len(m.group(1)), int(m.group(2))
    name = re.sub(r'\s*\+ \d+.*$', '', re.sub(r'\s+\(in ', ' (', m.group(3)))
    while stack and stack[-1][0] >= d:
        stack.pop()
    stack.append((d, c, name))
    if pat.search(name) and c >= minc and not any(pat.search(s[2]) for s in stack[:-1]):
        print(f'--- {c}')
        for s in stack[-depth:]:
            print(f'  {s[1]:6d} {s[2][:150]}')
