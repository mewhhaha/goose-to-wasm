import { utf8Encoder } from "./memory.js";

function shortestDecimal(shortest) {
  const [mantissa, exponentText = "0"] = shortest.toLowerCase().split("e");
  const point = mantissa.includes(".") ? mantissa.indexOf(".") : mantissa.length;
  let digits = mantissa.replace(".", "");
  let leading = 0;
  while (digits[leading] === "0") leading++;
  const decimalPoint = Number(exponentText) + point - leading;
  digits = digits.slice(leading).replace(/0+$/, "");
  return { digits, point: decimalPoint };
}

// The shortest scientific text of a positive finite f32, chosen as native
// gs_fmt_f32 chooses it: the fewest significant digits that read back as the
// same f32, of those the nearest to its exact value, and of two as near the
// even one. Exact integers decide each step. toPrecision rounds a decimal tie
// up, and one rounded candidate per length misses shorter text below a power
// of two, where the gap to the next f32 down is half the gap up.
function f32Scientific(magnitude) {
  const view = new DataView(new ArrayBuffer(4));
  view.setFloat32(0, magnitude);
  const bits = view.getUint32(0);
  const biased = bits >>> 23;
  const fraction = bits & 0x7fffff;
  const significand = biased ? fraction | 0x800000 : fraction;
  // The value is quarter * 2^binary; what reads back as it reaches from
  // quarter - below to quarter + 2 in the same unit, ends included when the
  // significand is even, since reading rounds a tie to the even significand.
  const quarter = BigInt(significand) * 4n;
  const binary = (biased || 1) - 152;
  const below = fraction === 0 && biased > 1 ? 1n : 2n;
  const inclusive = significand % 2 === 0;
  // Integers proportional to one unit of the value and one unit of 10^scale.
  const scaled = (scale) => [
    (binary > 0 ? 1n << BigInt(binary) : 1n) * (scale < 0 ? 10n ** BigInt(-scale) : 1n),
    (binary < 0 ? 1n << BigInt(-binary) : 1n) * (scale > 0 ? 10n ** BigInt(scale) : 1n),
  ];
  let exponent = Math.floor(Math.log10(magnitude));
  for (;;) {
    const [valueUnit, decimalUnit] = scaled(exponent);
    const leading = quarter * valueUnit / decimalUnit;
    if (leading >= 10n) exponent++;
    else if (leading < 1n) exponent--;
    else break;
  }
  for (let precision = 1; ; precision++) {
    const [valueUnit, decimalUnit] = scaled(exponent - precision + 1);
    const exact = quarter * valueUnit;
    const low = (quarter - below) * valueUnit;
    const high = (quarter + 2n) * valueUnit;
    const truncated = exact / decimalUnit;
    let best;
    let bestDistance;
    for (const digits of [truncated, truncated + 1n]) {
      const candidate = digits * decimalUnit;
      if (inclusive ? candidate < low || candidate > high : candidate <= low || candidate >= high) continue;
      const distance = candidate > exact ? candidate - exact : exact - candidate;
      if (best === undefined || distance < bestDistance || (distance === bestDistance && digits % 2n === 0n)) {
        best = digits;
        bestDistance = distance;
      }
    }
    if (best !== undefined) {
      // A carry to 10^precision spells one more digit at the next power.
      const text = best.toString();
      const digits = text.replace(/0+$/, "");
      return digits[0] + (digits.length > 1 ? "." + digits.slice(1) : "") + "e" + (exponent + text.length - precision);
    }
  }
}

export function gooseFloat(value, bits = 64) {
  if (bits === 32) value = Math.fround(value);
  if (Number.isNaN(value)) return "nan";
  if (value === Infinity) return "inf";
  if (value === -Infinity) return "-inf";
  const negative = value < 0 || Object.is(value, -0);
  if (value === 0) return negative ? "-0.0" : "0.0";
  const magnitude = Math.abs(value);
  const shortest = bits === 32 ? f32Scientific(magnitude) : magnitude.toString();
  const { digits, point } = shortestDecimal(shortest);
  const exponent = point - 1;
  let text;
  if (exponent < -4 || exponent >= Math.max(15, digits.length)) {
    text = digits[0];
    if (digits.length > 1) text += "." + digits.slice(1);
    text += "e" + (exponent < 0 ? "-" : "+") + String(Math.abs(exponent)).padStart(2, "0");
  } else if (exponent < 0) {
    text = "0." + "0".repeat(-exponent - 1) + digits;
  } else if (digits.length <= exponent + 1) {
    text = digits + "0".repeat(exponent + 1 - digits.length) + ".0";
  } else {
    text = digits.slice(0, exponent + 1) + "." + digits.slice(exponent + 1);
  }
  return (negative ? "-" : "") + text;
}

export function gooseFloatDigits(value) {
  if (!Number.isFinite(value) || value === 0) {
    return { digits: new Uint8Array(0), point: 0 };
  }
  const { digits, point } = shortestDecimal(Math.abs(value).toString());
  return { digits: utf8Encoder.encode(digits), point };
}

export function cRound(x) {
  if (!Number.isFinite(x) || x === 0) return x;
  const a = Math.abs(x);
  const t = Math.trunc(a);
  const r = a - t >= 0.5 ? t + 1 : t;
  return x < 0 ? -r : r;
}

const f64Buf = new ArrayBuffer(8);
const f64View = new DataView(f64Buf);
export function frexp(x) {
  if (x === 0 || !Number.isFinite(x)) return [x, 0];
  f64View.setFloat64(0, x, true);
  let bits = f64View.getBigUint64(0, true);
  let exp = Number((bits >> 52n) & 0x7ffn);
  let adjust = 0;
  if (exp === 0) {
    f64View.setFloat64(0, x * 18014398509481984.0, true); // 2^54
    bits = f64View.getBigUint64(0, true);
    exp = Number((bits >> 52n) & 0x7ffn);
    adjust = -54;
  }
  const e = exp - 1022 + adjust;
  f64View.setBigUint64(0, (bits & 0x800fffffffffffffn) | (1022n << 52n), true);
  return [f64View.getFloat64(0, true), e];
}

export function cRoundF32(x) {
  return Math.fround(cRound(Math.fround(x)));
}

export function ldexp(mantissa, exp) {
  if (mantissa === 0 || !Number.isFinite(mantissa) || exp === 0) return mantissa;
  if (exp >= -1022 && exp <= 1023) return mantissa * 2 ** exp;

  // Normalize before scaling so a subnormal result rounds only once.
  const [fraction, exponent] = frexp(mantissa);
  const target = exponent + exp;
  if (target < -1074) return fraction * 0;
  if (target > 1024) return fraction * Infinity;
  if (target === 1024) return (fraction * 2) * 2 ** 1023;
  return fraction * 2 ** target;
}
