"""Run in GDB against the pinned x86-64 compiler."""

import os
import struct

import gdb

limit = int(os.environ.get('GOOSE_CAPTURE_LIMIT', '0'))
output = open(os.environ['GOOSE_CAPTURE'], 'wb')


class Capture(gdb.Breakpoint):
    count = 0

    def stop(self):
        if limit and self.count >= limit:
            return False
        inferior = gdb.selected_inferior()
        # Clang has removed the unused closure parameter from this static
        # function. Its remaining parameters are base, locals, code, params.
        locals_ref = int(gdb.parse_and_eval('$rsi'))
        code_ref = int(gdb.parse_and_eval('$rdx'))
        params = int(gdb.parse_and_eval('$rcx'))
        locals_ptr, locals_len = struct.unpack('<QQ', inferior.read_memory(locals_ref, 16))
        code_ptr, code_len = struct.unpack('<QQ', inferior.read_memory(code_ref, 16))
        if locals_len >= 2:
            output.write(struct.pack('<QQQ', params, locals_len, code_len))
            output.write(inferior.read_memory(locals_ptr, 8 * locals_len))
            output.write(inferior.read_memory(code_ptr, code_len))
            self.count += 1
        return False


Capture('*g_fn259276')
