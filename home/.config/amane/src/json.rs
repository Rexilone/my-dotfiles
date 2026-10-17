// небольшой JSON: читать настройки Quickshell и ответы niri (у шелла amane нет serde)

use std::fmt::Write;

#[derive(Debug, Clone, PartialEq, Default)]
pub enum Json {
    #[default]
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    // порядок ключей сохраняется — запись настроек не перемешивает файл
    Obj(Vec<(String, Json)>),
}

static NULL: Json = Json::Null;

impl Json {
    pub fn parse(text: &str) -> Option<Json> {
        let mut p = Parser { s: text.as_bytes(), i: 0 };
        let v = p.value()?;
        p.ws();
        (p.i == p.s.len()).then_some(v)
    }

    // нет ключа или не объект — Null, так цепочки get().get() не падают
    pub fn get(&self, key: &str) -> &Json {
        match self {
            Json::Obj(items) => items.iter().find(|(k, _)| k == key).map(|(_, v)| v).unwrap_or(&NULL),
            _ => &NULL,
        }
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut Json> {
        match self {
            Json::Obj(items) => items.iter_mut().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn at(&self, i: usize) -> &Json {
        match self {
            Json::Arr(items) => items.get(i).unwrap_or(&NULL),
            _ => &NULL,
        }
    }

    pub fn at_mut(&mut self, i: usize) -> Option<&mut Json> {
        match self {
            Json::Arr(items) => items.get_mut(i),
            _ => None,
        }
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Json::Null)
    }

    pub fn str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn num(&self) -> Option<f64> {
        match self {
            Json::Num(n) => Some(*n),
            _ => None,
        }
    }

    pub fn bool(&self) -> Option<bool> {
        match self {
            Json::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn arr(&self) -> &[Json] {
        match self {
            Json::Arr(items) => items,
            _ => &[],
        }
    }

    pub fn obj(&self) -> &[(String, Json)] {
        match self {
            Json::Obj(items) => items,
            _ => &[],
        }
    }

    pub fn str_or(&self, def: &str) -> String {
        self.str().unwrap_or(def).to_string()
    }

    pub fn num_or(&self, def: f64) -> f64 {
        self.num().unwrap_or(def)
    }

    pub fn bool_or(&self, def: bool) -> bool {
        self.bool().unwrap_or(def)
    }

    // заменить или добавить ключ (объект создаётся, если тут было не оно)
    pub fn set(&mut self, key: &str, value: Json) {
        if !matches!(self, Json::Obj(_)) {
            *self = Json::Obj(Vec::new());
        }
        if let Json::Obj(items) = self {
            match items.iter_mut().find(|(k, _)| k == key) {
                Some((_, v)) => *v = value,
                None => items.push((key.to_string(), value)),
            }
        }
    }

    // как пишет Quickshell: отступ 4 пробела
    pub fn pretty(&self) -> String {
        self.pretty_with(4)
    }

    // как JSON.stringify(v, null, n) + перевод строки
    pub fn pretty_with(&self, unit: usize) -> String {
        let mut out = String::new();
        self.write(&mut out, 0, unit);
        out.push('\n');
        out
    }

    fn write(&self, out: &mut String, depth: usize, unit: usize) {
        let pad = |out: &mut String, d: usize| out.extend(std::iter::repeat_n(' ', d * unit));
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Json::Num(n) => {
                if n.fract() == 0.0 && n.abs() < 1e15 {
                    let _ = write!(out, "{}", *n as i64);
                } else {
                    let _ = write!(out, "{n}");
                }
            }
            Json::Str(s) => quote(s, out),
            Json::Arr(items) => {
                out.push('[');
                for (i, v) in items.iter().enumerate() {
                    out.push_str(if i == 0 { "\n" } else { ",\n" });
                    pad(out, depth + 1);
                    v.write(out, depth + 1, unit);
                }
                out.push('\n');
                pad(out, depth);
                out.push(']');
            }
            Json::Obj(items) => {
                if items.is_empty() {
                    out.push_str("{}");
                    return;
                }
                out.push('{');
                for (i, (k, v)) in items.iter().enumerate() {
                    out.push_str(if i == 0 { "\n" } else { ",\n" });
                    pad(out, depth + 1);
                    quote(k, out);
                    out.push_str(": ");
                    v.write(out, depth + 1, unit);
                }
                out.push('\n');
                pad(out, depth);
                out.push('}');
            }
        }
    }
}

fn quote(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.s.len() && matches!(self.s[self.i], b' ' | b'\n' | b'\r' | b'\t') {
            self.i += 1;
        }
    }

    fn eat(&mut self, word: &str) -> bool {
        if self.s[self.i..].starts_with(word.as_bytes()) {
            self.i += word.len();
            true
        } else {
            false
        }
    }

    fn value(&mut self) -> Option<Json> {
        self.ws();
        match *self.s.get(self.i)? {
            b'{' => self.object(),
            b'[' => self.array(),
            b'"' => self.string().map(Json::Str),
            b't' => self.eat("true").then_some(Json::Bool(true)),
            b'f' => self.eat("false").then_some(Json::Bool(false)),
            b'n' => self.eat("null").then_some(Json::Null),
            _ => self.number(),
        }
    }

    fn object(&mut self) -> Option<Json> {
        self.i += 1;
        let mut items = Vec::new();
        self.ws();
        if self.s.get(self.i) == Some(&b'}') {
            self.i += 1;
            return Some(Json::Obj(items));
        }
        loop {
            self.ws();
            if self.s.get(self.i) != Some(&b'"') {
                return None;
            }
            let key = self.string()?;
            self.ws();
            if self.s.get(self.i) != Some(&b':') {
                return None;
            }
            self.i += 1;
            let v = self.value()?;
            items.push((key, v));
            self.ws();
            match self.s.get(self.i)? {
                b',' => self.i += 1,
                b'}' => {
                    self.i += 1;
                    return Some(Json::Obj(items));
                }
                _ => return None,
            }
        }
    }

    fn array(&mut self) -> Option<Json> {
        self.i += 1;
        let mut items = Vec::new();
        self.ws();
        if self.s.get(self.i) == Some(&b']') {
            self.i += 1;
            return Some(Json::Arr(items));
        }
        loop {
            items.push(self.value()?);
            self.ws();
            match self.s.get(self.i)? {
                b',' => self.i += 1,
                b']' => {
                    self.i += 1;
                    return Some(Json::Arr(items));
                }
                _ => return None,
            }
        }
    }

    fn hex4(&mut self) -> Option<u32> {
        let h = std::str::from_utf8(self.s.get(self.i..self.i + 4)?).ok()?;
        self.i += 4;
        u32::from_str_radix(h, 16).ok()
    }

    fn string(&mut self) -> Option<String> {
        self.i += 1;
        let mut out = Vec::new();
        loop {
            let c = *self.s.get(self.i)?;
            self.i += 1;
            match c {
                b'"' => return String::from_utf8(out).ok(),
                b'\\' => {
                    let e = *self.s.get(self.i)?;
                    self.i += 1;
                    let ch = match e {
                        b'"' => '"',
                        b'\\' => '\\',
                        b'/' => '/',
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'n' => '\n',
                        b'r' => '\r',
                        b't' => '\t',
                        b'u' => {
                            let hi = self.hex4()?;
                            let code = if (0xD800..0xDC00).contains(&hi) && self.eat("\\u") {
                                let lo = self.hex4()?;
                                0x10000 + ((hi - 0xD800) << 10) + (lo.checked_sub(0xDC00)? & 0x3FF)
                            } else {
                                hi
                            };
                            char::from_u32(code).unwrap_or('\u{FFFD}')
                        }
                        _ => return None,
                    };
                    let mut buf = [0; 4];
                    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                }
                c => out.push(c),
            }
        }
    }

    fn number(&mut self) -> Option<Json> {
        let start = self.i;
        while self.i < self.s.len() && matches!(self.s[self.i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') {
            self.i += 1;
        }
        std::str::from_utf8(&self.s[start..self.i]).ok()?.parse().ok().map(Json::Num)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_settings_like_quickshell_writes() {
        let j = Json::parse(r#"{ "barStyle": "pills", "barHeight": 32, "uiScale": 1.25,
            "barModules": { "tray": true, "media": false }, "barScreens": ["DP-1"], "x": null }"#)
        .unwrap();
        assert_eq!(j.get("barStyle").str(), Some("pills"));
        assert_eq!(j.get("barHeight").num(), Some(32.0));
        assert_eq!(j.get("uiScale").num(), Some(1.25));
        assert_eq!(j.get("barModules").get("media").bool(), Some(false));
        assert_eq!(j.get("barScreens").at(0).str(), Some("DP-1"));
        assert!(j.get("x").is_null());
        assert!(j.get("missing").get("deeper").is_null());
    }

    #[test]
    fn escapes_and_unicode() {
        let j = Json::parse(r#"["a\"b\\c\n", "Привет", "😀", "日本"]"#).unwrap();
        assert_eq!(j.at(0).str(), Some("a\"b\\c\n"));
        assert_eq!(j.at(1).str(), Some("Привет"));
        assert_eq!(j.at(2).str(), Some("😀"));
        assert_eq!(j.at(3).str(), Some("日本"));
    }

    #[test]
    fn numbers() {
        let j = Json::parse("[-1.5e2, 0, 42, 3.25]").unwrap();
        assert_eq!(j.at(0).num(), Some(-150.0));
        assert_eq!(j.at(2).num(), Some(42.0));
    }

    #[test]
    fn rejects_broken() {
        for bad in ["", "{", "[1,", r#"{"a" 1}"#, r#"{"a":1,}"#, "tru", "[1] x", r#""\q""#] {
            assert!(Json::parse(bad).is_none(), "{bad}");
        }
    }

    #[test]
    fn round_trip_keeps_order() {
        let src = r#"{"b":1,"a":[true,null,"x"],"c":{"d":2.5},"e":{}}"#;
        let j = Json::parse(src).unwrap();
        let again = Json::parse(&j.pretty()).unwrap();
        assert_eq!(j, again);
        assert!(j.pretty().starts_with("{\n    \"b\": 1,\n    \"a\": ["));
    }

    #[test]
    fn set_replaces_and_appends() {
        let mut j = Json::parse(r#"{"a":1}"#).unwrap();
        j.set("a", Json::Num(2.0));
        j.set("b", Json::Str("x".into()));
        assert_eq!(j.get("a").num(), Some(2.0));
        assert_eq!(j.obj().len(), 2);
    }
}

#[cfg(test)]
mod real_files {
    // настройки шелла из репозитория (state/quickshell) и живые — должны читаться целиком
    #[test]
    fn parses_quickshell_settings_files() {
        let mut files = vec![];
        if let Ok(rd) = std::fs::read_dir(concat!(env!("HOME"), "/.local/state/quickshell/by-shell")) {
            for d in rd.flatten() {
                files.push(d.path().join("settings.json"));
            }
        }
        for f in files.iter().filter(|f| f.exists()) {
            let text = std::fs::read_to_string(f).unwrap();
            assert!(super::Json::parse(&text).is_some(), "{}", f.display());
        }
    }
}
