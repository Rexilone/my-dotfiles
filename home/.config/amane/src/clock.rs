// часы: формат как в Qt (Настройки → Бар → «dddd HH:mm»), дни и месяцы по-русски или по-английски

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use amane::Service;

use crate::settings::Settings;

const DAYS_EN: [&str; 7] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const DAYS_RU: [&str; 7] = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"];
const DAYS_RU_SHORT: [&str; 7] = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"];
const MONTHS_EN: [&str; 12] = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
    "December",
];
// в дате («17 октября») — родительный падеж, отдельно — именительный
const MONTHS_RU_GEN: [&str; 12] = [
    "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря",
];
const MONTHS_RU: [&str; 12] = [
    "январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь",
];
const MONTHS_RU_SHORT: [&str; 12] = ["янв.", "февр.", "мар.", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Civil {
    pub year: i64,
    pub month: u32,   // 1..12
    pub day: u32,     // 1..31
    pub weekday: u32, // 0 = понедельник
    pub hour: u32,
    pub minute: u32,
    pub second: u32,
}

// секунды Unix + смещение пояса → календарь (алгоритм Хиннанта)
pub fn civil(unix: i64, offset: i64) -> Civil {
    let t = unix + offset;
    let days = t.div_euclid(86400);
    let rem = t.rem_euclid(86400);
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = yoe + era * 400 + if month <= 2 { 1 } else { 0 };
    Civil {
        year,
        month,
        day,
        // 1970-01-01 — четверг
        weekday: (days + 3).rem_euclid(7) as u32,
        hour: (rem / 3600) as u32,
        minute: (rem / 60 % 60) as u32,
        second: (rem % 60) as u32,
    }
}

// «+0700» → 25200
pub fn parse_offset(s: &str) -> i64 {
    let s = s.trim();
    let (sign, rest) = match s.as_bytes().first() {
        Some(b'-') => (-1, &s[1..]),
        Some(b'+') => (1, &s[1..]),
        _ => (1, s),
    };
    if rest.len() != 4 || !rest.bytes().all(|b| b.is_ascii_digit()) {
        return 0;
    }
    let h: i64 = rest[..2].parse().unwrap_or(0);
    let m: i64 = rest[2..].parse().unwrap_or(0);
    sign * (h * 3600 + m * 60)
}

fn cap(s: &str) -> String {
    let mut c = s.chars();
    c.next().map(|f| f.to_uppercase().chain(c).collect()).unwrap_or_default()
}

// подмножество QDateTime::toString: d dd ddd dddd M MM MMM MMMM yy yyyy h hh H HH m mm s ss AP ap, 'текст'
pub fn format(fmt: &str, t: &Civil, ru: bool) -> String {
    let chars: Vec<char> = fmt.chars().collect();
    let twelve = fmt.contains("AP") || fmt.contains("ap");
    let with_day = fmt.replace("ddd", "").contains('d');
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\'' {
            // 'текст' — как есть, '' — апостроф
            let mut j = i + 1;
            if chars.get(j) == Some(&'\'') {
                out.push('\'');
                i += 2;
                continue;
            }
            while j < chars.len() && chars[j] != '\'' {
                out.push(chars[j]);
                j += 1;
            }
            i = j + 1;
            continue;
        }
        let mut n = 1;
        while chars.get(i + n) == Some(&c) {
            n += 1;
        }
        let h12 = if t.hour % 12 == 0 { 12 } else { t.hour % 12 };
        let piece = match (c, n) {
            ('d', 1) => t.day.to_string(),
            ('d', 2) => format!("{:02}", t.day),
            ('d', 3) => {
                if ru { DAYS_RU_SHORT[t.weekday as usize].into() } else { DAYS_EN[t.weekday as usize][..3].into() }
            }
            ('d', _) => {
                if ru { DAYS_RU[t.weekday as usize].into() } else { DAYS_EN[t.weekday as usize].into() }
            }
            ('M', 1) => t.month.to_string(),
            ('M', 2) => format!("{:02}", t.month),
            ('M', 3) => {
                let m = (t.month - 1) as usize;
                if ru { MONTHS_RU_SHORT[m].into() } else { MONTHS_EN[m][..3].into() }
            }
            ('M', _) => {
                let m = (t.month - 1) as usize;
                if !ru {
                    MONTHS_EN[m].into()
                } else if with_day {
                    MONTHS_RU_GEN[m].into()
                } else {
                    cap(MONTHS_RU[m])
                }
            }
            ('y', 2) | ('y', 3) => format!("{:02}", t.year.rem_euclid(100)),
            ('y', _) if n >= 4 => t.year.to_string(),
            ('h', 1) => (if twelve { h12 } else { t.hour }).to_string(),
            ('h', _) => format!("{:02}", if twelve { h12 } else { t.hour }),
            ('H', 1) => t.hour.to_string(),
            ('H', _) => format!("{:02}", t.hour),
            ('m', 1) => t.minute.to_string(),
            ('m', _) => format!("{:02}", t.minute),
            ('s', 1) => t.second.to_string(),
            ('s', _) => format!("{:02}", t.second),
            ('A', _) if chars.get(i + 1) == Some(&'P') => {
                i += 2;
                out.push_str(if t.hour < 12 { "AM" } else { "PM" });
                continue;
            }
            ('a', _) if chars.get(i + 1) == Some(&'p') => {
                i += 2;
                out.push_str(if t.hour < 12 { "am" } else { "pm" });
                continue;
            }
            _ => std::iter::repeat_n(c, n).collect(),
        };
        out.push_str(&piece);
        i += n;
    }
    out
}

pub fn unix_now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub struct Clock {
    pub unix: i64,
    pub offset: i64,
}

impl Clock {
    pub fn now(&self) -> Civil {
        civil(self.unix, self.offset)
    }

    pub fn text(&self, fmt: &str, ru: bool) -> String {
        format(fmt, &self.now(), ru)
    }
}

impl Service for Clock {
    fn new() -> Self {
        Clock { unix: unix_now(), offset: parse_offset(&amane::output("date +%z")) }
    }

    fn interval() -> Duration {
        Duration::from_millis(500)
    }

    // окно перерисовывается раз в минуту, а с секундами в формате — раз в секунду
    fn update(&mut self) -> bool {
        let now = unix_now();
        let seconds = Settings::read().c.clock_format.contains('s');
        let changed = if seconds { now != self.unix } else { now / 60 != self.unix / 60 };
        if now / 60 != self.unix / 60 {
            // смена часового пояса (поездка, переход на летнее время)
            self.offset = parse_offset(&amane::output("date +%z"));
        }
        self.unix = now;
        changed
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civil_dates() {
        // 2026-10-17 04:34:56 UTC — суббота
        let t = civil(1792211696, 0);
        assert_eq!((t.year, t.month, t.day, t.hour, t.minute, t.second), (2026, 10, 17, 4, 34, 56));
        assert_eq!(t.weekday, 5);
        // смещение +07:00 переносит на тот же день 11:34
        let t = civil(1792211696, 7 * 3600);
        assert_eq!((t.day, t.hour), (17, 11));
        // 1970-01-01 — четверг; 2000-02-29 — високосный
        assert_eq!(civil(0, 0).weekday, 3);
        let t = civil(951782400, 0);
        assert_eq!((t.year, t.month, t.day), (2000, 2, 29));
        // до 1970
        let t = civil(-1, 0);
        assert_eq!((t.year, t.month, t.day, t.hour), (1969, 12, 31, 23));
    }

    #[test]
    fn offsets() {
        assert_eq!(parse_offset("+0700"), 25200);
        assert_eq!(parse_offset("-0330\n"), -12600);
        assert_eq!(parse_offset("UTC"), 0);
        assert_eq!(parse_offset(""), 0);
    }

    #[test]
    fn qt_formats() {
        let t = civil(1792211696, 7 * 3600); // сб 17.10.2026 11:34:56
        assert_eq!(format("dddd HH:mm", &t, false), "Saturday 11:34");
        assert_eq!(format("dddd HH:mm", &t, true), "суббота 11:34");
        assert_eq!(format("ddd, d MMMM", &t, true), "сб, 17 октября");
        assert_eq!(format("ddd, d MMMM", &t, false), "Sat, 17 October");
        assert_eq!(format("MMMM yyyy", &t, true), "Октябрь 2026");
        assert_eq!(format("dd.MM.yy H:m:s", &t, false), "17.10.26 11:34:56");
        assert_eq!(format("h:mm AP", &t, false), "11:34 AM");
        assert_eq!(format("hh:mm ap", &civil(1792211696, 12 * 3600), false), "04:34 pm");
        assert_eq!(format("HH:mm 'Uhr'", &t, false), "11:34 Uhr");
        assert_eq!(format("HH''mm", &t, false), "11'34");
    }

    #[test]
    fn midnight_is_twelve_in_12h() {
        let t = civil(1792195200, 0); // 00:00
        assert_eq!(format("h AP", &t, false), "12 AM");
        assert_eq!(format("H", &t, false), "0");
    }
}

// секундные часы — для видов, где идут секунды (Время и язык)
pub struct Seconds {
    pub unix: i64,
}

impl Service for Seconds {
    fn new() -> Self {
        Seconds { unix: unix_now() }
    }

    fn interval() -> Duration {
        Duration::from_millis(250)
    }

    fn update(&mut self) -> bool {
        let now = unix_now();
        let changed = now != self.unix;
        self.unix = now;
        changed
    }
}
