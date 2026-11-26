export function createStdImports(mem) {
  const byteSet = (ptr) => mem.readBytes(mem.address(ptr), 256);

  return {
    gs_find_any(...args) {
      const { view, next } = mem.readSliceView(args);
      const members = byteSet(args[next]);
      for (let i = 0; i < view.length; i++) {
        if (members[view[i]]) return BigInt(i);
      }
      return -1n;
    },
    gs_find_pair(...args) {
      const { view, next } = mem.readSliceView(args);
      const first = byteSet(args[next]);
      const distance = Number(args[next + 1]);
      const second = byteSet(args[next + 2]);
      if (distance < 0 || distance >= view.length) return -1n;
      for (let i = 0; i + distance < view.length; i++) {
        if (first[view[i]] && second[view[i + distance]]) return BigInt(i);
      }
      return -1n;
    },
    gs_ffi_cstr(ptr, out) {
      const raw = BigInt.asUintN(64, BigInt(ptr));
      if (raw === 0n) return 0;
      const buf = mem.bytes();
      if (raw >= BigInt(buf.length)) return 0;
      const addr = Number(raw);
      const end = buf.indexOf(0, addr);
      mem.appendBuilder(out, buf.slice(addr, end === -1 ? buf.length : end));
      return 1;
    },
    gs_ffi_bytes(ptr, n, out) {
      const raw = BigInt.asUintN(64, BigInt(ptr));
      if (raw === 0n) return 0;
      const count = Number(n);
      if (!Number.isSafeInteger(count) || count < 0) return 0;
      const buf = mem.bytes();
      if (count > buf.length || raw > BigInt(buf.length - count)) return 0;
      const addr = Number(raw);
      mem.appendBuilder(out, buf.slice(addr, addr + count));
      return 1;
    },
  };
}
