//! Float text, byte for byte what `goose_float` in scripts/run_wasmtime.py gives.
//!
//! An f64 is its shortest round-trip digits (what Python's `repr` and Rust's
//! `{:e}` both choose) in Goose's layout. An f32 is the shortest text that
//! reads back as the same f32, chosen by the exact-integer steps of
//! `f32_scientific`; they need about 200 bits, kept here in `Wide`.

use std::cmp::Ordering;

/// The text of an f64 as `goose.print_f64` and `goose.format_f64` give it.
pub fn f64_text(value: f64) -> String {
    if let Some(text) = special(value.is_nan(), value.is_infinite(), value == 0.0, value.is_sign_negative()) {
        return text.to_string();
    }
    let (digits, exponent) = f64_shortest(value.abs());
    layout(value.is_sign_negative(), digits.to_string().trim_end_matches('0'), exponent)
}

/// The shortest digits that read back as a positive finite f64, as an
/// integer, and the decimal exponent of the first of them.
///
/// Rust's `{:e}` chooses the fewest digits and of those the nearest to the
/// value, as Python's `repr` does. They part where the value is exactly half
/// way between two such texts: Rust takes the upper one, Python the one
/// whose last digit is even if both read back. That case is found exactly
/// and decided Python's way.
pub fn f64_shortest(magnitude: f64) -> (u64, i32) {
    // `{:e}` gives d[.ddd]e[-]x.
    let scientific = format!("{magnitude:e}");
    let (mantissa, exponent) = scientific.split_once('e').expect("scientific text has an exponent");
    let exponent: i32 = exponent.parse().expect("scientific text has a decimal exponent");
    let count = mantissa.len() as i32 - i32::from(mantissa.len() > 1);
    let digits = mantissa.bytes().filter(u8::is_ascii_digit).fold(0u64, |digits, digit| digits * 10 + u64::from(digit - b'0'));
    if digits % 2 == 0 {
        return (digits, exponent);
    }
    // The value is significand * 2**binary, both reduced so that it is odd.
    let bits = magnitude.to_bits();
    let (biased, fraction) = ((bits >> 52) as i32, bits & ((1 << 52) - 1));
    let significand = if biased != 0 { fraction | 1 << 52 } else { fraction };
    let binary = biased.max(1) - 1075 + significand.trailing_zeros() as i32;
    let significand = significand >> significand.trailing_zeros();
    // The last digit counts 10**last. Half way to the next text up or down is
    // (2 * digits +- 1) * 5 * 10**(last - 1), an odd number times that power.
    let last = exponent - count + 1;
    let half_way = |odd: u64| {
        let ten = last - 1;
        let fives = 5u128.checked_pow(ten.unsigned_abs());
        match fives {
            // odd * 5**ten * 2**ten is the value: an odd number at 2**binary.
            Some(fives) if ten >= 0 => binary == ten && u128::from(odd).checked_mul(fives) == Some(u128::from(significand)),
            // The value times 10**-ten is the odd number.
            Some(fives) => binary == ten && u128::from(significand).checked_mul(fives) == Some(u128::from(odd)),
            None => false,
        }
    };
    let other = if half_way((2 * digits + 1) * 5) {
        digits + 1
    } else if half_way((2 * digits - 1) * 5) {
        digits - 1
    } else {
        return (digits, exponent);
    };
    // The even neighbour, if it has as many digits and reads back as the value.
    let same_length = other.to_string().len() as i32 == count;
    if same_length && format!("{other}e{last}").parse::<f64>() == Ok(magnitude) {
        (other, exponent)
    } else {
        (digits, exponent)
    }
}

/// The text of an f32 as `goose.print_f32` and `goose.format_f32` give it.
pub fn f32_text(value: f32) -> String {
    if let Some(text) = special(value.is_nan(), value.is_infinite(), value == 0.0, value.is_sign_negative()) {
        return text.to_string();
    }
    let (digits, exponent) = f32_scientific(value.abs());
    layout(value.is_sign_negative(), &digits, exponent)
}

fn special(nan: bool, infinite: bool, zero: bool, negative: bool) -> Option<&'static str> {
    if nan {
        Some("nan")
    } else if infinite {
        Some(if negative { "-inf" } else { "inf" })
    } else if zero {
        Some(if negative { "-0.0" } else { "0.0" })
    } else {
        None
    }
}

/// Goose's layout of `digits` (no leading or trailing zero) times ten to the
/// `exponent` of the first digit.
fn layout(negative: bool, digits: &str, exponent: i32) -> String {
    let count = digits.len() as i32;
    let mut text = String::with_capacity(32);
    if negative {
        text.push('-');
    }
    if exponent < -4 || exponent >= count.max(15) {
        text.push_str(&digits[..1]);
        if count > 1 {
            text.push('.');
            text.push_str(&digits[1..]);
        }
        text.push('e');
        text.push(if exponent < 0 { '-' } else { '+' });
        text.push_str(&format!("{:02}", exponent.unsigned_abs()));
    } else if exponent < 0 {
        text.push_str("0.");
        text.extend(std::iter::repeat_n('0', (-exponent - 1) as usize));
        text.push_str(digits);
    } else if count <= exponent + 1 {
        text.push_str(digits);
        text.extend(std::iter::repeat_n('0', (exponent + 1 - count) as usize));
        text.push_str(".0");
    } else {
        let whole = (exponent + 1) as usize;
        text.push_str(&digits[..whole]);
        text.push('.');
        text.push_str(&digits[whole..]);
    }
    text
}

/// The shortest scientific digits of a positive finite f32 and the exponent of
/// the first: the fewest significant digits that read back as the same f32, of
/// those the nearest to its exact value, and of two as near the even one.
fn f32_scientific(magnitude: f32) -> (String, i32) {
    let bits = magnitude.to_bits();
    let (biased, fraction) = ((bits >> 23) as i32, bits & 0x7F_FFFF);
    let significand = if biased != 0 { fraction | 0x80_0000 } else { fraction };
    // The value is quarter * 2**binary; what reads back as it reaches from
    // quarter - below to quarter + 2 in the same unit, ends included when the
    // significand is even, since reading rounds a tie to the even significand.
    let quarter = u64::from(significand) * 4;
    let binary = biased.max(1) - 152;
    let below = if fraction == 0 && biased > 1 { 1 } else { 2 };
    let inclusive = significand % 2 == 0;
    // Integers proportional to one unit of the value and one unit of 10**scale.
    let scaled = |scale: i32| {
        (
            Wide::power_of_ten(scale.min(0).unsigned_abs()).shifted(binary.max(0) as u32),
            Wide::power_of_ten(scale.max(0) as u32).shifted(binary.min(0).unsigned_abs()),
        )
    };
    let mut exponent = f64::from(magnitude).log10().floor() as i32;
    loop {
        let (value_unit, decimal_unit) = scaled(exponent);
        let leading = value_unit.times(quarter).divided_by(&decimal_unit);
        if leading >= 10 {
            exponent += 1;
        } else if leading < 1 {
            exponent -= 1;
        } else {
            break;
        }
    }
    let mut precision = 1;
    loop {
        let (value_unit, decimal_unit) = scaled(exponent - precision + 1);
        let exact = value_unit.times(quarter);
        let (low, high) = (value_unit.times(quarter - below), value_unit.times(quarter + 2));
        let truncated = exact.divided_by(&decimal_unit);
        let mut best: Option<(u64, Wide)> = None;
        for digits in [truncated, truncated + 1] {
            let candidate = decimal_unit.times(digits);
            let inside = if inclusive {
                low <= candidate && candidate <= high
            } else {
                low < candidate && candidate < high
            };
            if !inside {
                continue;
            }
            let distance = if candidate > exact { candidate.minus(&exact) } else { exact.minus(&candidate) };
            let better = match &best {
                None => true,
                Some((_, least)) => distance < *least || (distance == *least && digits % 2 == 0),
            };
            if better {
                best = Some((digits, distance));
            }
        }
        if let Some((digits, _)) = best {
            // A carry to 10**precision spells one more digit at the next power.
            let text = digits.to_string();
            let exponent = exponent + text.len() as i32 - precision;
            return (text.trim_end_matches('0').to_string(), exponent);
        }
        precision += 1;
    }
}

/// An unsigned integer of 256 bits, least significant word first. The largest
/// the f32 steps reach is below 2**210 (2**26 * 10**53, or 2**151 * 10**9), so
/// an overflow here is a mistake in them and panics.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct Wide([u64; 4]);

impl Wide {
    fn power_of_ten(mut power: u32) -> Wide {
        let mut value = Wide([1, 0, 0, 0]);
        while power >= 19 {
            value = value.times(10_000_000_000_000_000_000);
            power -= 19;
        }
        value.times(10u64.pow(power))
    }

    fn times(&self, factor: u64) -> Wide {
        let mut words = [0u64; 4];
        let mut carry = 0u128;
        for (word, &own) in words.iter_mut().zip(&self.0) {
            let product = u128::from(own) * u128::from(factor) + carry;
            *word = product as u64;
            carry = product >> 64;
        }
        assert!(carry == 0, "f32 text arithmetic overflowed");
        Wide(words)
    }

    fn shifted(&self, bits: u32) -> Wide {
        assert!(self.bits() + bits <= 256, "f32 text arithmetic overflowed");
        let (whole, part) = ((bits / 64) as usize, bits % 64);
        let mut words = [0u64; 4];
        for index in whole..4 {
            words[index] = self.0[index - whole] << part;
            if part != 0 && index > whole {
                words[index] |= self.0[index - whole - 1] >> (64 - part);
            }
        }
        Wide(words)
    }

    fn minus(&self, other: &Wide) -> Wide {
        let mut words = [0u64; 4];
        let mut borrow = false;
        for index in 0..4 {
            let (difference, first) = self.0[index].overflowing_sub(other.0[index]);
            let (difference, second) = difference.overflowing_sub(u64::from(borrow));
            words[index] = difference;
            borrow = first || second;
        }
        assert!(!borrow, "f32 text arithmetic went negative");
        Wide(words)
    }

    fn bits(&self) -> u32 {
        for index in (0..4).rev() {
            if self.0[index] != 0 {
                return index as u32 * 64 + 64 - self.0[index].leading_zeros();
            }
        }
        0
    }

    /// The low 128 bits of this number shifted right by `bits`.
    fn top(&self, bits: u32) -> u128 {
        let (whole, part) = ((bits / 64) as usize, bits % 64);
        let word = |index: usize| u128::from(*self.0.get(index).unwrap_or(&0));
        let wide = word(whole) | word(whole + 1) << 64;
        if part == 0 {
            wide
        } else {
            wide >> part | word(whole + 2) << (128 - part)
        }
    }

    /// The whole quotient, which fits in 64 bits for every division the f32
    /// steps make (at most ten decimal digits). Estimated from the leading 64
    /// bits of the divisor, which is within one of it, then made exact.
    fn divided_by(&self, divisor: &Wide) -> u64 {
        assert!(divisor.bits() != 0, "f32 text arithmetic divided by zero");
        let shift = divisor.bits().saturating_sub(64);
        assert!(self.bits().saturating_sub(shift) <= 128, "f32 text quotient is too large");
        let estimate = self.top(shift) / divisor.top(shift);
        let mut quotient = u64::try_from(estimate).expect("f32 text quotient is too large");
        while divisor.times(quotient) > *self {
            quotient -= 1;
        }
        while divisor.times(quotient + 1) <= *self {
            quotient += 1;
        }
        quotient
    }
}

impl PartialOrd for Wide {
    fn partial_cmp(&self, other: &Wide) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Wide {
    fn cmp(&self, other: &Wide) -> Ordering {
        self.0.iter().rev().cmp(other.0.iter().rev())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn f64_layouts() {
        for (value, text) in [
            (0.0, "0.0"),
            (-0.0, "-0.0"),
            (f64::NAN, "nan"),
            (f64::INFINITY, "inf"),
            (f64::NEG_INFINITY, "-inf"),
            (1.0, "1.0"),
            (-1.5, "-1.5"),
            (0.1, "0.1"),
            (123.456, "123.456"),
            (1e-4, "0.0001"),
            (1e-5, "1e-05"),
            (1.5e-7, "1.5e-07"),
            (1e14, "100000000000000.0"),
            (1e15, "1e+15"),
            (123456789012345680.0, "1.2345678901234568e+17"),
            (1234567890123456.0, "1234567890123456.0"),
            (1e100, "1e+100"),
            (5e-324, "5e-324"),
            (f64::MAX, "1.7976931348623157e+308"),
            (f64::MIN_POSITIVE, "2.2250738585072014e-308"),
            (0.30000000000000004, "0.30000000000000004"),
            // Half way between two shortest texts: the even last digit.
            (2.0f64.powi(-25), "2.9802322387695312e-08"),
            (12345678901234.5625, "12345678901234.562"),
            (597659464700.90625, "597659464700.9062"),
            (9007199254740993.0 * 4.0, "3.602879701896397e+16"),
        ] {
            assert_eq!(f64_text(value), text);
        }
    }

    #[test]
    fn f32_layouts() {
        for (value, text) in [
            (0.0f32, "0.0"),
            (-0.0, "-0.0"),
            (f32::NAN, "nan"),
            (f32::INFINITY, "inf"),
            (f32::NEG_INFINITY, "-inf"),
            (1.0, "1.0"),
            (0.1, "0.1"),
            (-2.5, "-2.5"),
            (16777216.0, "16777216.0"),
            (1e10, "10000000000.0"),
            (1e15, "1e+15"),
            (1e-5, "1e-05"),
            (3.4028235e38, "3.4028235e+38"),
            (1.1754944e-38, "1.1754944e-38"),
            (1e-45, "1e-45"),
            (0.3, "0.3"),
            (9.999999e-5, "9.999999e-05"),
        ] {
            assert_eq!(f32_text(value), text);
        }
    }

    #[test]
    fn wide_division() {
        let ten_to_fifty = Wide::power_of_ten(50);
        assert_eq!(ten_to_fifty.times(123_456_789).divided_by(&ten_to_fifty), 123_456_789);
        assert_eq!(ten_to_fifty.times(7).minus(&Wide([1, 0, 0, 0])).divided_by(&ten_to_fifty), 6);
        assert_eq!(Wide([0, 0, 1, 0]).shifted(70).bits(), 199);
        assert_eq!(Wide([5, 0, 0, 0]).shifted(130).divided_by(&Wide([1, 0, 0, 0]).shifted(128)), 20);
        assert!(Wide([0, 1, 0, 0]) > Wide([u64::MAX, 0, 0, 0]));
    }
}
