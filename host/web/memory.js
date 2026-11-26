export const utf8Encoder = new TextEncoder();
// Keep a leading BOM, as it is part of the bytes in a Goose string.
export const utf8Decoder = new TextDecoder("utf-8", { ignoreBOM: true });

export function detectMemory64(wasmBytes) {
  const header = [0, 97, 115, 109, 1, 0, 0, 0];
  if (!header.every((byte, index) => wasmBytes[index] === byte)) return false;

  let at = header.length;
  let end = wasmBytes.length;
  let memory64 = false;

  function byte() {
    if (at >= end) throw new RangeError("truncated Wasm section");
    return wasmBytes[at++];
  }

  function unsignedLeb(bits) {
    let value = 0n;
    for (let shift = 0; shift < bits; shift += 7) {
      const next = byte();
      const payload = next & 0x7f;
      if (bits - shift < 7 && payload >= 2 ** (bits - shift)) break;
      value |= BigInt(payload) << BigInt(shift);
      if ((next & 0x80) === 0) return value;
    }
    throw new RangeError("invalid Wasm unsigned LEB128");
  }

  function u32() {
    return Number(unsignedLeb(32));
  }

  function skipName() {
    const length = u32();
    if (length > end - at) throw new RangeError("truncated Wasm name");
    at += length;
  }

  function valueType() {
    const type = byte();
    if (type === 0x63 || type === 0x64) unsignedLeb(35); // Signed heap type.
  }

  function limits(isMemory) {
    const flags = byte();
    if (flags > 7 || ((flags & 2) && !(flags & 1))) {
      throw new RangeError("invalid Wasm limits flags");
    }
    const wide = (flags & 4) !== 0;
    const bits = wide ? 64 : 32;
    const min = unsignedLeb(bits);
    if ((flags & 1) && unsignedLeb(bits) < min) {
      throw new RangeError("invalid Wasm limits");
    }
    if (isMemory && wide) memory64 = true;
  }

  function importType() {
    switch (byte()) {
      case 0: u32(); break; // Function type index.
      case 1: valueType(); limits(false); break;
      case 2: limits(true); break;
      case 3: valueType(); byte(); break; // Mutability.
      case 4: byte(); u32(); break; // Tag attribute and type index.
      default: throw new RangeError("invalid Wasm import kind");
    }
  }

  try {
    while (at < wasmBytes.length) {
      const section = byte();
      const size = u32();
      if (size > end - at) return false;
      end = at + size;
      if (section === 2 || section === 5) {
        const count = u32();
        for (let i = 0; i < count; i++) {
          if (section === 2) {
            skipName();
            skipName();
            importType();
          } else {
            limits(true);
          }
        }
        if (at !== end) return false;
      }
      at = end;
      end = wasmBytes.length;
    }
    return memory64;
  } catch (error) {
    if (error instanceof RangeError) return false;
    throw error;
  }
}

export function createMemoryAccess(state) {
  function address(raw) {
    const ptr = Number(raw);
    if (!Number.isSafeInteger(ptr) || ptr < 0) {
      throw new RangeError("invalid Wasm address");
    }
    return ptr;
  }

  function bytes() {
    return new Uint8Array(state.memory.buffer);
  }

  function view() {
    return new DataView(state.memory.buffer);
  }

  function readSliceArgs(args, startIndex = 0) {
    if (state.memory64) {
      return {
        ptr: address(args[startIndex]),
        len: Number(args[startIndex + 1]),
        next: startIndex + 2,
      };
    }
    const packed = BigInt.asUintN(64, BigInt(args[startIndex]));
    return {
      ptr: Number(packed & 0xffffffffn),
      len: Number(packed >> 32n),
      next: startIndex + 1,
    };
  }

  function checkedLength(buffer, ptr, len) {
    if (!Number.isSafeInteger(len) || len < 0 || ptr > buffer.byteLength - len) {
      throw new RangeError("range is outside Wasm memory");
    }
    return len;
  }

  function readBytes(ptr, len) {
    if (len <= 0) return new Uint8Array(0);
    const buffer = state.memory.buffer;
    ptr = address(ptr);
    return new Uint8Array(buffer, ptr, checkedLength(buffer, ptr, len));
  }

  function readBytesCopy(ptr, len) {
    return readBytes(ptr, len).slice();
  }

  function readSlice(args, startIndex = 0) {
    const slice = readSliceArgs(args, startIndex);
    return { ...slice, bytes: readBytesCopy(slice.ptr, slice.len) };
  }

  function readSliceView(args, startIndex = 0) {
    const slice = readSliceArgs(args, startIndex);
    return { ...slice, view: readBytes(slice.ptr, slice.len) };
  }

  function readUtf8(ptr, len) {
    return utf8Decoder.decode(readBytes(ptr, len));
  }

  function readSliceUtf8(args, startIndex = 0) {
    const slice = readSlice(args, startIndex);
    return { ...slice, text: utf8Decoder.decode(slice.bytes) };
  }

  function appendBuilder(control, data) {
    if (typeof data === "string") data = utf8Encoder.encode(data);
    if (data.length === 0) return;
    if (data.buffer === state.memory.buffer) data = data.slice();
    const length = data.length;
    const count = state.memory64 ? BigInt(length) : length;
    const dest = address(state.reserve(control, count));
    new Uint8Array(state.memory.buffer, dest, length).set(data);
  }

  function writeI32(rawPtr, value) {
    view().setInt32(address(rawPtr), value, true);
  }

  function writeI64(rawPtr, value) {
    view().setBigInt64(address(rawPtr), BigInt(value), true);
  }

  const littleEndian = new Uint8Array(Uint32Array.of(1).buffer)[0] === 1;

  function readF32Array(ptr, len) {
    const buffer = state.memory.buffer;
    ptr = address(ptr);
    if (!Number.isSafeInteger(len)) throw new RangeError("invalid f32 element count");
    const size = checkedLength(buffer, ptr, len * 4);
    if (littleEndian && ptr % 4 === 0) return new Float32Array(buffer, ptr, len).slice();

    const source = new DataView(buffer, ptr, size);
    const result = new Float32Array(len);
    const bits = new Uint32Array(result.buffer);
    for (let i = 0; i < len; i++) bits[i] = source.getUint32(i * 4, true);
    return result;
  }

  function writeF32Array(ptr, srcFloat32Array) {
    const buffer = state.memory.buffer;
    ptr = address(ptr);
    const size = checkedLength(buffer, ptr, srcFloat32Array.byteLength);
    if (littleEndian && ptr % 4 === 0) {
      new Float32Array(buffer, ptr, srcFloat32Array.length).set(srcFloat32Array);
      return;
    }

    const target = new DataView(buffer, ptr, size);
    const source = srcFloat32Array.buffer === buffer ? srcFloat32Array.slice() : srcFloat32Array;
    const bits = new Uint32Array(source.buffer, source.byteOffset, source.length);
    for (let i = 0; i < bits.length; i++) target.setUint32(i * 4, bits[i], true);
  }

  return {
    get memory64() { return Boolean(state.memory64); },
    address, bytes, view, readSliceArgs, readBytes, readBytesCopy, readSlice,
    readSliceView, readUtf8, readSliceUtf8, appendBuilder, writeI32, writeI64,
    readF32Array, writeF32Array,
  };
}
