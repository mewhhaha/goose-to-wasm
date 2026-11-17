import sys
from pathlib import Path
import struct
root = Path(sys.argv[1]).resolve()
def uleb(value):
    while value > 127:
        yield (value & 127) | 128
        value >>= 7
    yield value

constants = {127: b'\x41\x00', 126: b'\x42\x00', 125: b'\x43'+bytes(4), 124: b'\x44'+bytes(8), 123:b'\xfd\x0c'+bytes(16)}
def case(n, type_count, waves):
    locals_ = list(range(127, 127-type_count, -1)) * ((n*waves+type_count-1)//type_count)
    locals_ = locals_[:n*waves]
    code = bytearray()
    for j in range(waves):
        for i in range(j*n, j*n+n):
            code.extend(constants[locals_[i]])
            code.append(0x21)
            code.extend(uleb(i))
        for i in reversed(range(j*n, j*n+n)):
            code.append(0x20)
            code.extend(uleb(i))
            code.append(0x1a)
    code.append(0x0b)
    return struct.pack(f'<{3+len(locals_)}Q', 0, len(locals_), len(code), *locals_) + code
(root/'synthetic.bin').write_bytes(case(17, 5, 3)*50 + case(127, 2, 5) * 200 + case(5000, 5, 6) + case(11000, 1, 2) + case(17000, 3, 1))
(root/'tiny.bin').write_bytes(case(2, 1, 1) * 40000 + case(3, 2, 1) * 15000 + case(5, 4, 2) * 5000)
