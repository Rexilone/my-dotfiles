pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// погода с Open-Meteo (без ключа); место выбирается поиском в дашборде
// последние данные кэшируются на диск и показываются сразу при запуске
Singleton {
    id: root

    readonly property string city: cfg.city
    readonly property string region: [cfg.admin1, cfg.country].filter(s => s).join(", ")
    readonly property real latitude: cfg.latitude
    readonly property real longitude: cfg.longitude
    readonly property bool configured: cfg.city !== "" && (cfg.latitude !== 0 || cfg.longitude !== 0)

    property var current: null           // { temp, feels, humidity, wind, code, isDay }
    property var daily: []               // [{ date, code, max, min }]
    property bool loading: false
    property string error: ""
    property real updatedAt: cfg.updatedAt

    // поиск мест
    property var results: []             // [{ name, admin1, country, lat, lon, population }]
    property bool searching: false

    function search(q) {
        q = q.trim();
        if (q.length < 2) {
            results = [];
            return;
        }
        searching = true;
        geo.command = ["curl", "-s", "-m", "10", "-G", "https://geocoding-api.open-meteo.com/v1/search",
            "--data-urlencode", `name=${q}`, "-d", "count=8", "-d", "language=ru"];
        geo.running = true;
    }

    function choose(r) {
        cfg.city = r.name;
        cfg.admin1 = r.admin1 ?? "";
        cfg.country = r.country ?? "";
        cfg.latitude = r.lat;
        cfg.longitude = r.lon;
        cfg.cache = "";
        cfg.updatedAt = 0;
        file.writeAdapter();
        current = null;
        daily = [];
        results = [];
        refresh();
    }

    function refresh() {
        if (!configured) return;
        loading = true;
        forecast.command = ["curl", "-s", "-m", "10", "-G", "https://api.open-meteo.com/v1/forecast",
            "-d", `latitude=${cfg.latitude}`, "-d", `longitude=${cfg.longitude}`,
            "-d", "current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day",
            "-d", "daily=weather_code,temperature_2m_max,temperature_2m_min",
            "-d", "wind_speed_unit=ms", "-d", "timezone=auto", "-d", "forecast_days=5"];
        forecast.running = true;
    }

    function apply(d) {
        const c = d.current;
        current = {
            temp: Math.round(c.temperature_2m),
            feels: Math.round(c.apparent_temperature),
            humidity: c.relative_humidity_2m,
            wind: Math.round(c.wind_speed_10m),
            code: c.weather_code,
            isDay: c.is_day === 1,
        };
        daily = d.daily.time.map((t, i) => ({
            date: new Date(t + "T12:00:00"),
            code: d.daily.weather_code[i],
            max: Math.round(d.daily.temperature_2m_max[i]),
            min: Math.round(d.daily.temperature_2m_min[i]),
        }));
    }

    function ago() {
        if (!updatedAt) return "";
        const min = Math.floor((Date.now() - updatedAt) / 60000);
        if (I18n.ru) return min < 1 ? "только что" : min < 60 ? `${min} мин назад` : `${Math.floor(min / 60)} ч назад`;
        return min < 1 ? "just now" : min < 60 ? `${min} min ago` : `${Math.floor(min / 60)} h ago`;
    }

    // WMO-код -> { icon, text }
    function info(code, isDay) {
        const g = c => String.fromCodePoint(c);
        const map = {
            0: [0xF0599, 0xF0594, "Clear sky"],
            1: [0xF0599, 0xF0594, "Mostly clear"],
            2: [0xF0595, 0xF0F31, "Partly cloudy"],
            3: [0xF0590, 0xF0590, "Overcast"],
            45: [0xF0591, 0xF0591, "Fog"],
            48: [0xF0591, 0xF0591, "Rime fog"],
            51: [0xF0597, 0xF0597, "Light drizzle"],
            53: [0xF0597, 0xF0597, "Drizzle"],
            55: [0xF0597, 0xF0597, "Heavy drizzle"],
            56: [0xF067F, 0xF067F, "Freezing drizzle"],
            57: [0xF067F, 0xF067F, "Freezing drizzle"],
            61: [0xF0597, 0xF0597, "Light rain"],
            63: [0xF0597, 0xF0597, "Rain"],
            65: [0xF0596, 0xF0596, "Heavy rain"],
            66: [0xF067F, 0xF067F, "Freezing rain"],
            67: [0xF067F, 0xF067F, "Freezing rain"],
            71: [0xF0598, 0xF0598, "Light snow"],
            73: [0xF0598, 0xF0598, "Snow"],
            75: [0xF0F36, 0xF0F36, "Heavy snow"],
            77: [0xF0598, 0xF0598, "Snow grains"],
            80: [0xF0597, 0xF0597, "Showers"],
            81: [0xF0596, 0xF0596, "Showers"],
            82: [0xF0596, 0xF0596, "Heavy showers"],
            85: [0xF0598, 0xF0598, "Snow showers"],
            86: [0xF0F36, 0xF0F36, "Snow showers"],
            95: [0xF0593, 0xF0593, "Thunderstorm"],
            96: [0xF067E, 0xF067E, "Thunderstorm, hail"],
            99: [0xF067E, 0xF067E, "Thunderstorm, hail"],
        };
        const m = map[code] ?? [0xF0590, 0xF0590, "—"];
        return { icon: g(isDay === false ? m[1] : m[0]), text: I18n.tr(m[2]) };
    }

    FileView {
        id: file
        path: Quickshell.statePath("weather.json")
        blockLoading: true
        printErrors: false
        // пишем явно одним вызовом: автозапись на каждое поле теряет значения

        JsonAdapter {
            id: cfg
            property string city: ""
            property string admin1: ""
            property string country: ""
            property real latitude: 0
            property real longitude: 0
            property string cache: ""      // последний ответ API
            property real updatedAt: 0
        }
    }

    Component.onCompleted: {
        try {
            if (cfg.cache) apply(JSON.parse(cfg.cache));
        } catch (e) {}
    }

    Process {
        id: geo
        stdout: StdioCollector {
            onStreamFinished: {
                root.searching = false;
                try {
                    root.results = (JSON.parse(text).results ?? []).map(r => ({
                        name: r.name,
                        admin1: r.admin1 ?? "",
                        country: r.country ?? "",
                        lat: r.latitude,
                        lon: r.longitude,
                        population: r.population ?? 0,
                    }));
                } catch (e) {
                    root.results = [];
                }
            }
        }
    }

    Process {
        id: forecast
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const d = JSON.parse(text);
                    if (!d.current) throw "bad";
                    root.apply(d);
                    cfg.cache = text;
                    cfg.updatedAt = Date.now();
                    file.writeAdapter();
                    root.error = "";
                } catch (e) {
                    root.error = "offline";
                }
            }
        }
    }

    Timer {
        interval: 20 * 60 * 1000
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
