// погода с Open-Meteo (без ключа), как services/Weather.qml; место — поиском, последний ответ кэшируется
// в том же weather.json, что у Quickshell

use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use amane::Service;

use crate::json::Json;

#[derive(Debug, Clone, PartialEq)]
pub struct Current {
    pub temp: i64,
    pub feels: i64,
    pub humidity: i64,
    pub wind: i64,
    pub code: i64,
    pub is_day: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Day {
    pub date: String, // ГГГГ-ММ-ДД
    pub code: i64,
    pub max: i64,
    pub min: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Place {
    pub name: String,
    pub admin1: String,
    pub country: String,
    pub lat: f64,
    pub lon: f64,
    pub population: f64,
}

#[derive(Default)]
pub struct Weather {
    pub cfg: Json,
    pub current: Option<Current>,
    pub daily: Vec<Day>,
    pub loading: bool,
    pub error: String,
    pub results: Vec<Place>,
    pub searching: bool,
}

pub fn path() -> PathBuf {
    crate::settings::path().with_file_name("weather.json")
}

fn load_cfg() -> Json {
    fs::read_to_string(path()).ok().and_then(|t| Json::parse(&t)).unwrap_or(Json::Obj(Vec::new()))
}

impl Weather {
    pub fn city(&self) -> String {
        self.cfg.get("city").str_or("")
    }
    pub fn region(&self) -> String {
        [self.cfg.get("admin1").str_or(""), self.cfg.get("country").str_or("")].into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join(", ")
    }
    pub fn lat(&self) -> f64 {
        self.cfg.get("latitude").num_or(0.0)
    }
    pub fn lon(&self) -> f64 {
        self.cfg.get("longitude").num_or(0.0)
    }
    pub fn configured(&self) -> bool {
        !self.city().is_empty() && (self.lat() != 0.0 || self.lon() != 0.0)
    }
    pub fn updated_at(&self) -> f64 {
        self.cfg.get("updatedAt").num_or(0.0)
    }
}

pub fn parse_forecast(d: &Json) -> Option<(Current, Vec<Day>)> {
    let c = d.get("current");
    if c.is_null() {
        return None;
    }
    let cur = Current {
        temp: c.get("temperature_2m").num_or(0.0).round() as i64,
        feels: c.get("apparent_temperature").num_or(0.0).round() as i64,
        humidity: c.get("relative_humidity_2m").num_or(0.0) as i64,
        wind: c.get("wind_speed_10m").num_or(0.0).round() as i64,
        code: c.get("weather_code").num_or(0.0) as i64,
        is_day: c.get("is_day").num_or(1.0) == 1.0,
    };
    let dl = d.get("daily");
    let days = dl
        .get("time")
        .arr()
        .iter()
        .enumerate()
        .map(|(i, t)| Day {
            date: t.str_or(""),
            code: dl.get("weather_code").at(i).num_or(0.0) as i64,
            max: dl.get("temperature_2m_max").at(i).num_or(0.0).round() as i64,
            min: dl.get("temperature_2m_min").at(i).num_or(0.0).round() as i64,
        })
        .collect();
    Some((cur, days))
}

pub fn parse_places(text: &str) -> Vec<Place> {
    Json::parse(text)
        .map(|j| {
            j.get("results")
                .arr()
                .iter()
                .map(|r| Place {
                    name: r.get("name").str_or(""),
                    admin1: r.get("admin1").str_or(""),
                    country: r.get("country").str_or(""),
                    lat: r.get("latitude").num_or(0.0),
                    lon: r.get("longitude").num_or(0.0),
                    population: r.get("population").num_or(0.0),
                })
                .collect()
        })
        .unwrap_or_default()
}

// WMO-код → (значок, описание)
pub fn info(code: i64, is_day: bool) -> (u32, &'static str) {
    let (d, n, t) = match code {
        0 => (0xF0599, 0xF0594, "Clear sky"),
        1 => (0xF0599, 0xF0594, "Mostly clear"),
        2 => (0xF0595, 0xF0F31, "Partly cloudy"),
        3 => (0xF0590, 0xF0590, "Overcast"),
        45 => (0xF0591, 0xF0591, "Fog"),
        48 => (0xF0591, 0xF0591, "Rime fog"),
        51 => (0xF0597, 0xF0597, "Light drizzle"),
        53 => (0xF0597, 0xF0597, "Drizzle"),
        55 => (0xF0597, 0xF0597, "Heavy drizzle"),
        56 | 57 => (0xF067F, 0xF067F, "Freezing drizzle"),
        61 => (0xF0597, 0xF0597, "Light rain"),
        63 => (0xF0597, 0xF0597, "Rain"),
        65 => (0xF0596, 0xF0596, "Heavy rain"),
        66 | 67 => (0xF067F, 0xF067F, "Freezing rain"),
        71 => (0xF0598, 0xF0598, "Light snow"),
        73 => (0xF0598, 0xF0598, "Snow"),
        75 => (0xF0F36, 0xF0F36, "Heavy snow"),
        77 => (0xF0598, 0xF0598, "Snow grains"),
        80 => (0xF0597, 0xF0597, "Showers"),
        81 => (0xF0596, 0xF0596, "Showers"),
        82 => (0xF0596, 0xF0596, "Heavy showers"),
        85 => (0xF0598, 0xF0598, "Snow showers"),
        86 => (0xF0F36, 0xF0F36, "Snow showers"),
        95 => (0xF0593, 0xF0593, "Thunderstorm"),
        96 | 99 => (0xF067E, 0xF067E, "Thunderstorm, hail"),
        _ => (0xF0590, 0xF0590, "—"),
    };
    (if is_day { d } else { n }, t)
}

pub fn ago(updated_ms: f64, now_ms: f64, ru: bool) -> String {
    if updated_ms <= 0.0 {
        return String::new();
    }
    let min = ((now_ms - updated_ms) / 60000.0).floor() as i64;
    if ru {
        if min < 1 { "только что".into() } else if min < 60 { format!("{min} мин назад") } else { format!("{} ч назад", min / 60) }
    } else if min < 1 {
        "just now".into()
    } else if min < 60 {
        format!("{min} min ago")
    } else {
        format!("{} h ago", min / 60)
    }
}

fn save_cfg(cfg: &Json) {
    let _ = fs::write(path(), cfg.pretty());
}

// обновить прогноз (в фоне)
pub fn refresh() {
    std::thread::spawn(|| {
        let (lat, lon, ok) = {
            let w = Weather::read();
            (w.lat(), w.lon(), w.configured())
        };
        if !ok {
            return;
        }
        Weather::write().loading = true;
        let text = amane::output(&format!(
            "curl -s -m 10 -G https://api.open-meteo.com/v1/forecast -d latitude={lat} -d longitude={lon} -d current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day -d daily=weather_code,temperature_2m_max,temperature_2m_min -d wind_speed_unit=ms -d timezone=auto -d forecast_days=5"
        ));
        let mut w = Weather::write();
        w.loading = false;
        match Json::parse(&text).as_ref().and_then(parse_forecast) {
            Some((c, d)) => {
                w.current = Some(c);
                w.daily = d;
                w.error.clear();
                w.cfg.set("cache", Json::Str(text));
                w.cfg.set("updatedAt", Json::Num(crate::clock::unix_now() as f64 * 1000.0));
                save_cfg(&w.cfg);
            }
            None => w.error = "offline".into(),
        }
    });
}

// поиск мест (в фоне)
pub fn search(q: &str) {
    let q = q.trim().to_string();
    if q.chars().count() < 2 {
        Weather::write().results.clear();
        return;
    }
    Weather::write().searching = true;
    std::thread::spawn(move || {
        let text = amane::output(&format!(
            "curl -s -m 10 -G https://geocoding-api.open-meteo.com/v1/search --data-urlencode {} -d count=8 -d language=ru",
            crate::niri::sh_quote(&format!("name={q}"))
        ));
        let mut w = Weather::write();
        w.searching = false;
        w.results = parse_places(&text);
    });
}

pub fn choose(p: &Place) {
    {
        let mut w = Weather::write();
        for (k, v) in [
            ("city", Json::Str(p.name.clone())),
            ("admin1", Json::Str(p.admin1.clone())),
            ("country", Json::Str(p.country.clone())),
            ("latitude", Json::Num(p.lat)),
            ("longitude", Json::Num(p.lon)),
            ("cache", Json::Str(String::new())),
            ("updatedAt", Json::Num(0.0)),
        ] {
            w.cfg.set(k, v);
        }
        save_cfg(&w.cfg);
        w.current = None;
        w.daily.clear();
        w.results.clear();
    }
    refresh();
}

impl Service for Weather {
    fn new() -> Self {
        let cfg = load_cfg();
        let mut w = Weather { cfg, ..Default::default() };
        if let Some((c, d)) = Json::parse(&w.cfg.get("cache").str_or("")).as_ref().and_then(parse_forecast) {
            w.current = Some(c);
            w.daily = d;
        }
        w
    }

    fn listen() {
        loop {
            if Weather::read().configured() {
                refresh();
            }
            std::thread::sleep(Duration::from_secs(20 * 60));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn forecast_parsing() {
        let j = Json::parse(r#"{"current":{"temperature_2m":7.4,"apparent_temperature":4.6,"relative_humidity_2m":81,"weather_code":3,"wind_speed_10m":3.6,"is_day":0},
            "daily":{"time":["2026-10-17","2026-10-18"],"weather_code":[3,61],"temperature_2m_max":[9.6,11.2],"temperature_2m_min":[2.1,4.5]}}"#).unwrap();
        let (c, d) = parse_forecast(&j).unwrap();
        assert_eq!((c.temp, c.feels, c.wind, c.is_day), (7, 5, 4, false));
        assert_eq!(d.len(), 2);
        assert_eq!(d[1], Day { date: "2026-10-18".into(), code: 61, max: 11, min: 5 });
        assert!(parse_forecast(&Json::parse("{}").unwrap()).is_none());
    }

    #[test]
    fn places_and_codes() {
        let p = parse_places(r#"{"results":[{"name":"Новосибирск","admin1":"Новосибирская область","country":"Россия","latitude":55.04,"longitude":82.93,"population":1419007}]}"#);
        assert_eq!(p[0].name, "Новосибирск");
        assert!(parse_places("broken").is_empty());
        assert_eq!(info(0, false), (0xF0594, "Clear sky"));
        assert_eq!(info(99, true).1, "Thunderstorm, hail");
        assert_eq!(info(1234, true).1, "—");
    }

    #[test]
    fn ago_text() {
        assert_eq!(ago(0.0, 1e6, false), "");
        assert_eq!(ago(1e6, 1e6 + 30_000.0, true), "только что");
        assert_eq!(ago(1e6, 1e6 + 5.0 * 60_000.0, false), "5 min ago");
        assert_eq!(ago(1e6, 1e6 + 130.0 * 60_000.0, true), "2 ч назад");
    }
}
