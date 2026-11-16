//! Text the Python runner leaves to Python itself: how `int` and `float` read
//! an input token and word their refusal, `repr` of a string, and the spelling
//! `pathlib.Path` gives a path. Spelled the same here so that the two hosts
//! agree on what a program sees and on what a failure prints.

/// `repr` of a string whose characters are the given bytes (a latin-1 view).
pub fn repr_latin1(bytes: &[u8]) -> String {
    repr(bytes.iter().map(|&byte| char::from(byte)))
}

/// `repr` of a string.
pub fn repr_str(text: &str) -> String {
    repr(text.chars())
}

fn repr(characters: impl Iterator<Item = char> + Clone) -> String {
    let single = characters.clone().any(|character| character == '\'');
    let double = characters.clone().any(|character| character == '"');
    let quote = if single && !double { '"' } else { '\'' };
    let mut text = String::new();
    text.push(quote);
    for character in characters {
        match character {
            '\\' => text.push_str("\\\\"),
            '\n' => text.push_str("\\n"),
            '\r' => text.push_str("\\r"),
            '\t' => text.push_str("\\t"),
            _ if character == quote => {
                text.push('\\');
                text.push(character);
            }
            // Not printable: controls, the no-break space and the soft hyphen.
            '\0'..='\x1f' | '\x7f'..='\u{a0}' | '\u{ad}' => text.push_str(&format!("\\x{:02x}", character as u32)),
            _ => text.push(character),
        }
    }
    text.push(quote);
    text
}

/// A token without the spaces `int` and `float` skip at its ends. Split on
/// ASCII whitespace already, it can only hold the two latin-1 ones.
fn stripped(token: &[u8]) -> &[u8] {
    let space = |byte: &u8| matches!(byte, 0x85 | 0xa0);
    let start = token.iter().position(|byte| !space(byte)).unwrap_or(token.len());
    let end = token.iter().rposition(|byte| !space(byte)).map_or(start, |last| last + 1);
    &token[start..end]
}

/// The text without its underscores, which may only stand between two digits.
fn without_underscores(text: &[u8]) -> Option<Vec<u8>> {
    let mut plain = Vec::with_capacity(text.len());
    for (index, &byte) in text.iter().enumerate() {
        if byte != b'_' {
            plain.push(byte);
        } else if index == 0 || !text[index - 1].is_ascii_digit() || !text.get(index + 1).is_some_and(u8::is_ascii_digit) {
            return None;
        }
    }
    Some(plain)
}

/// `int(token, 10)` held to an i64, with the Python runner's two refusals.
pub fn parse_int(token: &[u8]) -> Result<i64, String> {
    let invalid = || {
        let shown: String = repr_latin1(token).chars().take(200).collect();
        format!("invalid literal for int() with base 10: {shown}")
    };
    let text = stripped(token);
    let (negative, digits) = match text.first() {
        Some(b'-') => (true, &text[1..]),
        Some(b'+') => (false, &text[1..]),
        _ => (false, text),
    };
    let digits = without_underscores(digits).ok_or_else(invalid)?;
    if digits.is_empty() || !digits.iter().all(u8::is_ascii_digit) {
        return Err(invalid());
    }
    if digits.len() > 4300 {
        return Err(format!(
            "Exceeds the limit (4300 digits) for integer string conversion: value has {} digits; use sys.set_int_max_str_digits() to increase the limit",
            digits.len()
        ));
    }
    let mut value: i128 = 0;
    for digit in digits.iter().skip_while(|&&digit| digit == b'0') {
        value = value * 10 + i128::from(digit - b'0');
        if value > 1 << 63 {
            return Err("host input exceeds i64".to_string());
        }
    }
    i64::try_from(if negative { -value } else { value }).map_err(|_| "host input exceeds i64".to_string())
}

/// `float(token)`.
pub fn parse_float(token: &[u8]) -> Result<f64, String> {
    let invalid = || format!("could not convert string to float: {}", repr_latin1(token));
    let text = without_underscores(stripped(token)).ok_or_else(invalid)?;
    // What is left is ASCII or is refused below; Rust reads the same grammar
    // (digits with an optional point and exponent, inf, infinity, nan) and
    // rounds as correctly.
    let text = std::str::from_utf8(&text).map_err(|_| invalid())?;
    if !text.is_ascii() {
        return Err(invalid());
    }
    text.parse::<f64>().map_err(|_| invalid())
}

/// The spelling `str(pathlib.Path(path))` gives a POSIX path: no empty or `.`
/// parts and no trailing slash; exactly two leading slashes stay two.
pub fn normalized_path(path: &[u8]) -> Vec<u8> {
    let slashes = path.iter().take_while(|&&byte| byte == b'/').count();
    let root: &[u8] = match slashes {
        0 => b"",
        2 => b"//",
        _ => b"/",
    };
    let parts: Vec<&[u8]> = path.split(|&byte| byte == b'/').filter(|part| !part.is_empty() && *part != b".").collect();
    let mut normalized = root.to_vec();
    normalized.extend_from_slice(&parts.join(&b'/'));
    if normalized.is_empty() {
        normalized.push(b'.');
    }
    normalized
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integers() {
        assert_eq!(parse_int(b"12"), Ok(12));
        assert_eq!(parse_int(b"+1_0"), Ok(10));
        assert_eq!(parse_int(b"-9223372036854775808"), Ok(i64::MIN));
        assert_eq!(parse_int(b"\xa0+5\x85"), Ok(5));
        assert_eq!(parse_int(b"000000000000000000000000000007"), Ok(7));
        assert_eq!(parse_int(b"9223372036854775808").unwrap_err(), "host input exceeds i64");
        assert_eq!(parse_int(b"1__0").unwrap_err(), "invalid literal for int() with base 10: '1__0'");
        assert_eq!(parse_int(b"\x1f12").unwrap_err(), "invalid literal for int() with base 10: '\\x1f12'");
        assert_eq!(parse_int(b"a'b").unwrap_err(), "invalid literal for int() with base 10: \"a'b\"");
        assert_eq!(parse_int(b"a'b\"c").unwrap_err(), "invalid literal for int() with base 10: 'a\\'b\"c'");
        assert_eq!(parse_int(b"\xe9").unwrap_err(), "invalid literal for int() with base 10: '\u{e9}'");
        assert!(parse_int(&[b'9'; 4301]).unwrap_err().starts_with("Exceeds the limit (4300 digits)"));
    }

    #[test]
    fn floats() {
        assert_eq!(parse_float(b"1_0.5"), Ok(10.5));
        assert_eq!(parse_float(b"-Infinity"), Ok(f64::NEG_INFINITY));
        assert_eq!(parse_float(b"1e1_0"), Ok(1e10));
        assert_eq!(parse_float(b".5"), Ok(0.5));
        assert_eq!(parse_float(b"5."), Ok(5.0));
        assert!(parse_float(b"+NaN").unwrap().is_nan());
        for refused in ["1_.5", ".", "1e", "0x1p3", "infi", "", "1e_3", "1.5f"] {
            assert_eq!(parse_float(refused.as_bytes()).unwrap_err(), format!("could not convert string to float: '{refused}'"));
        }
    }

    #[test]
    fn paths() {
        for (path, normalized) in [
            ("a//b/./c/", "a/b/c"),
            ("./a", "a"),
            ("/", "/"),
            ("//a", "//a"),
            ("///a", "/a"),
            ("", "."),
            ("a/..", "a/.."),
            ("./", "."),
            ("//", "//"),
            ("/./a", "/a"),
            ("..//b", "../b"),
        ] {
            assert_eq!(normalized_path(path.as_bytes()), normalized.as_bytes());
        }
    }
}
