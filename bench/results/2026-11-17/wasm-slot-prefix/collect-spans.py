import collections
from pathlib import Path
import struct
import sys

def leb(code, off):
    result = shift = 0
    while True:
        b = code[off]
        off += 1
        result |= (b & 127) << shift
        if b < 128:
            return result, off
        shift += 7

def spans(code, params, count):
    first = [-1] * (params + count)
    last = [-1] * (params + count)
    written = [0] * (params + count)
    arm = [-1] * (params + count)
    stamp = [-1] * (params + count)
    frames = []
    undo = []
    covers = []
    loop_ends = {}
    off = 0
    position = -1
    while off < len(code):
        position += 1
        op = code[off]
        off += 1
        if op in (2, 3, 4):
            _, off = leb(code, off)
            frames.append([position, op, len(undo), False, False])
        elif op == 5:
            pos, _, mark, _, _ = frames[-1]
            for local in undo[mark:]:
                arm[local] = pos
                written[local] = 0
            del undo[mark:]
            frames[-1][3] = True
        elif op == 0x0b:
            if not frames:
                break
            pos, opener, mark, alternative, branched = frames.pop()
            merged = []
            for local in undo[mark:]:
                written[local] = 0
                if opener == 4 and alternative and not branched and arm[local] == pos:
                    merged.append(local)
            del undo[mark:]
            for local in merged:
                if written[local] == 0:
                    written[local] = len(frames) + 1
                    undo.append(local)
            if opener == 3:
                loop_ends[pos] = position
        elif op in (0x0c, 0x0d, 0x0e):
            count, off = leb(code, off)
            if op == 0x0e:
                for _ in range(count+1):
                    target, off = leb(code, off)
                    if target < len(frames):
                        frames[-1-target][4] = True
            elif count < len(frames):
                frames[-1-count][4] = True
        elif op in (0x20, 0x21, 0x22):
            local, off = leb(code, off)
            if local < params:
                continue
            if first[local] < 0:
                first[local] = position
            last[local] = position
            if op == 0x20:
                depth = written[local]-1
                if depth < 0:
                    first[local] = 0
                    depth = 0
                while depth < len(frames) and frames[depth][1] != 3:
                    depth += 1
                if depth < len(frames):
                    loop = frames[depth][0]
                    if stamp[local] != loop:
                        stamp[local] = loop
                        covers.append((local, loop))
            elif written[local] == 0:
                written[local] = len(frames)+1
                undo.append(local)
        elif op in (0x10, 0x23, 0x24, 0x3f, 0x40, 0x41, 0x42):
            _, off = leb(code, off)
        elif op == 0x11 or 0x28 <= op <= 0x3e:
            _, off = leb(code, off)
            _, off = leb(code, off)
        elif op == 0x43:
            off += 4
        elif op == 0x44:
            off += 8
        elif op == 0x1c:
            count, off = leb(code, off)
            off += count
        elif op == 0xfc:
            sub, off = leb(code, off)
            if sub in (8, 9, 10, 11):
                _, off = leb(code, off)
            if sub in (8, 10):
                _, off = leb(code, off)
        elif op == 0xfd:
            sub, off = leb(code, off)
            if sub <= 0x0b or sub in (0x5c, 0x5d) or 0x54 <= sub <= 0x5b:
                _, off = leb(code, off)
                _, off = leb(code, off)
            if sub in (0x0c, 0x0d):
                off += 16
            elif 0x15 <= sub <= 0x22 or 0x54 <= sub <= 0x5b:
                off += 1
    assert off == len(code), (position, off, len(code))
    for local, start in covers:
        first[local] = min(first[local], start)
        last[local] = max(last[local], loop_ends[start])
    return first[params:], last[params:], position + 1

def main():
    bodyfile = Path(sys.argv[1])
    raw = bodyfile.read_bytes()
    off = 0
    bodies = []
    kinds = collections.Counter()
    slots_hist = collections.Counter()
    kind_slots_hist = collections.Counter()
    all_probes = all_count = all_size = all_changes = all_instructions = 0
    while off < len(raw):
        params, nlocals, size = struct.unpack_from('<QQQ', raw, off)
        off += 24
        if off + 8*nlocals + size > len(raw):
            raise ValueError("partial record")
        types = struct.unpack_from(f'<{nlocals}Q', raw, off)
        off += 8*nlocals
        first, last, instructions = spans(raw[off:off+size], params, nlocals)
        off += size
        kinds.update(types)
        all_size += size
        all_instructions += instructions
        slots = []
        per_kind = collections.Counter()
        probes = count = changes = 0
        entries = sorted((start, i) for i, start in enumerate(first) if start >= 0)
        prev_start = -1
        for start, i in entries:
            kind = types[i]
            end = last[i]
            assert end >= start
            count += 1
            changes += (prev_start != start)
            prev_start = start
            local_probes = 0
            for slot, (slot_type, slot_end) in enumerate(slots):
                local_probes += 1
                if slot_end < start and slot_type == kind:
                    slots[slot] = (kind, end)
                    break
            else:
                per_kind[kind] += 1
                slots.append((kind, end))
            probes += local_probes
        all_probes += probes
        all_count += count
        all_changes += changes
        slots_hist[len(slots).bit_length()] += 1
        kind_slots_hist[max(per_kind.values(), default=0).bit_length()] += 1
        bodies.append((probes, count, len(slots), per_kind, nlocals, size, instructions))
    print('bodies', len(bodies), 'input locals by kind', kinds, 'slot counts by log2 total and per kind', sorted(slots_hist.items()), sorted(kind_slots_hist.items()))
    print('input bytes', all_size, 'instructions', all_instructions, 'total local spans/probes/start positions', all_count, all_probes, all_changes, 'checks avg', all_probes/all_count)
    print('greatest probe bodies', *sorted(bodies, key=lambda entry: entry[0], reverse=True)[:20], sep='\n')
    print('max slots', max(bodies, key=lambda entry: entry[2]))

if __name__ == '__main__':
    main()
