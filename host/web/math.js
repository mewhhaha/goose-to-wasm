import { cRound, cRoundF32, frexp, gooseFloatDigits, ldexp } from "./float.js";

const bits = new DataView(new ArrayBuffer(8));

function copysign(x, y) {
  bits.setFloat64(0, y);
  const sign = bits.getUint8(0) & 0x80;
  bits.setFloat64(0, x);
  bits.setUint8(0, (bits.getUint8(0) & 0x7f) | sign);
  return bits.getFloat64(0);
}

const float64 = {
  sqrt: Math.sqrt,
  sin: Math.sin,
  cos: Math.cos,
  tan: Math.tan,
  asin: Math.asin,
  acos: Math.acos,
  atan: Math.atan,
  atan2: Math.atan2,
  exp: Math.exp,
  exp2: (x) => 2 ** x,
  expm1: Math.expm1,
  log: Math.log,
  log2: Math.log2,
  log10: Math.log10,
  log1p: Math.log1p,
  pow: Math.pow,
  hypot: Math.hypot,
  cbrt: Math.cbrt,
  sinh: Math.sinh,
  cosh: Math.cosh,
  tanh: Math.tanh,
  asinh: Math.asinh,
  acosh: Math.acosh,
  atanh: Math.atanh,
  mul_add: (x, y, z) => x * y + z,
  floor: Math.floor,
  ceil: Math.ceil,
  trunc: Math.trunc,
  round: cRound,
  copysign,
  fmod: (x, y) => x % y,
  fabs: Math.abs,
};

function mulAddF32(x, y, z) {
  const product = Math.fround(Math.fround(x) * Math.fround(y));
  return Math.fround(product + Math.fround(z));
}

function popcount(x) {
  let count = 0n;
  for (let remaining = BigInt.asUintN(64, x); remaining; remaining &= remaining - 1n) {
    count++;
  }
  return count;
}

function clz(x) {
  const word = BigInt.asUintN(64, x);
  return word === 0n ? 64n : BigInt(64 - word.toString(2).length);
}

function ctz(x) {
  const word = BigInt.asUintN(64, x);
  return word === 0n ? 64n : 63n - clz(word & -word);
}

function rotl32(x, n) {
  const shift = Number(BigInt(n) & 31n);
  return ((x << shift) | (x >>> (-shift & 31))) >>> 0;
}

function rotl64(x, n) {
  const word = BigInt.asUintN(64, x);
  const shift = BigInt(n) & 63n;
  return BigInt.asUintN(64, (word << shift) | (word >> (-shift & 63n)));
}

export function createMathImports(mem) {
  const imports = {
    frexp(x, expPtr) {
      const [fraction, exponent] = frexp(x);
      mem.writeI32(expPtr, exponent);
      return fraction;
    },
    ldexp,
    gs_f64_digits(x, ...rest) {
      const { len, view, next } = mem.readSliceView(rest);
      const { digits, point } = gooseFloatDigits(x);
      if (digits.length === 0) return 0n;
      const n = Math.min(digits.length, len);
      view.set(digits.subarray(0, n));
      mem.writeI64(rest[next], BigInt(point));
      return BigInt(n);
    },
    gs_popcount: popcount,
    gs_clz: clz,
    gs_ctz: ctz,
    gs_rotl32: rotl32,
    gs_rotl64: rotl64,
    gs_rotr32: (x, n) => rotl32(x, -BigInt(n)),
    gs_rotr64: (x, n) => rotl64(x, -BigInt(n)),
    gs_byte_swap16(x) {
      bits.setUint16(0, x, true);
      return bits.getUint16(0);
    },
    gs_byte_swap32(x) {
      bits.setUint32(0, x, true);
      return bits.getUint32(0);
    },
    gs_byte_swap64(x) {
      bits.setBigUint64(0, x, true);
      return bits.getBigUint64(0);
    },
    gs_f32_from_bits(b) {
      bits.setUint32(0, b);
      return bits.getFloat32(0);
    },
    gs_f64_from_bits(b) {
      bits.setBigUint64(0, b);
      return bits.getFloat64(0);
    },
    gs_f32_to_bits(x) {
      bits.setFloat32(0, x);
      return bits.getUint32(0);
    },
    gs_f64_to_bits(x) {
      bits.setFloat64(0, x);
      return bits.getBigUint64(0);
    },
  };

  const float32Overrides = { mul_add: mulAddF32, round: cRoundF32 };
  for (const [name, fn] of Object.entries(float64)) {
    const f32 = float32Overrides[name] ?? ((...args) => Math.fround(fn(...args.map(Math.fround))));
    imports[name] = imports[`gs_${name}`] = fn;
    imports[`${name}f`] = imports[`gs_${name}f`] = f32;
  }
  // The direct host uses separate multiply and add roundings.
  imports.fma = imports.gs_fma = imports.mul_add;
  imports.fmaf = imports.gs_fmaf = imports.mul_addf;
  return imports;
}
