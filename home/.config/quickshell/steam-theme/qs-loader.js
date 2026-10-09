// Загрузчик темы Rexilone для Millennium.
// Классы Steam зашифрованы (_3Z7VQ1IMk4E3HsHvrkLNgo) и меняются с каждым обновлением,
// поэтому CSS темы пишется с понятными именами: `.%TopBar%` или `.%Container@GameListHomeAndSearch%`
// (Container из того модуля, где есть и GameListHomeAndSearch). Здесь эти имена заменяются
// на настоящие классы из webpack-модулей Steam. Файлы опрашиваются, поэтому смена темы
// в шелле (colors.css) и правки CSS применяются без перезапуска Steam.

const BASE = new URL(".", import.meta.url).href;
const STYLE_ID = "qs-steam-theme";
const POLL_MS = 2000;

function hostWindow() {
    try {
        if (window.opener && window.opener.webpackChunksteamui) return window.opener;
    } catch (e) {}
    return window;
}

// все CSS-модули Steam: [{ ключ: "класс" }, …]; кэш общий на все окна
function webpackRequire(host) {
    if (host.__qsSteamReq) return host.__qsSteamReq;
    const chunks = host.webpackChunksteamui;
    if (!chunks) return null;
    chunks.push([[Symbol("qs-steam")], {}, r => { host.__qsSteamReq = r; }]);
    return host.__qsSteamReq || null;
}

function moduleCount(host) {
    const req = webpackRequire(host);
    return req ? Object.keys(req.m).length : 0;
}

function cssModules(host) {
    const req = webpackRequire(host);
    if (!req) return [];
    const count = Object.keys(req.m).length;
    if (host.__qsSteamMods && host.__qsSteamMods.count === count) return host.__qsSteamMods.list;
    const re = /^\s*\(?\w+\)?\s*=>\s*\{\s*(?:"use strict";)?\s*\w+\.exports\s*=\s*\{([\s\S]*)\}\s*\}\s*$/;
    const list = [];
    for (const id in req.m) {
        let src;
        try { src = Function.prototype.toString.call(req.m[id]); } catch (e) { continue; }
        if (src.length > 100000 || src.indexOf("exports={") < 0) continue;
        const m = src.match(re);
        if (!m) continue;
        const o = {};
        let n = 0;
        for (const p of m[1].matchAll(/([\w$]+):"([^"\\]+)"/g)) { o[p[1]] = p[2]; n++; }
        if (n) list.push(o);
    }
    host.__qsSteamMods = { count, list };
    return list;
}

function compile(css, mods, missing) {
    return css.replace(/\.%([\w$-]+)(?:@([\w$-]+))?%/g, (all, key, sib) => {
        const set = new Set();
        for (const o of mods) {
            if (!(key in o) || (sib && !(sib in o))) continue;
            for (const c of o[key].split(" ")) set.add(c);
        }
        if (!set.size) {
            missing.add(sib ? `${key}@${sib}` : key);
            return ".qs-missing";
        }
        const cls = [...set].map(c => "." + CSS.escape(c));
        return cls.length === 1 ? cls[0] : `:is(${cls.join(",")})`;
    });
}

export function load(files) {
    // Millennium может подключить в одно окно оба загрузчика (основной и для друзей):
    // работает один, второй только добавляет свои файлы
    if (window.__qsSteamLoader) {
        window.__qsSteamLoader.add(files);
        return;
    }

    const host = hostWindow();
    const list = [];
    const texts = {};
    let modCount = -1;
    let style = null;

    function add(more) {
        let added = false;
        for (const f of more) if (!list.includes(f)) { list.push(f); added = true; }
        // colors.css всегда первым, остальное по порядку подключения
        list.sort((a, b) => (b === "colors.css") - (a === "colors.css"));
        if (added) poll();
    }
    window.__qsSteamLoader = { add };

    function apply() {
        const mods = cssModules(host);
        modCount = host.__qsSteamMods ? host.__qsSteamMods.count : 0;
        const missing = new Set();
        const css = list.map(f => compile(texts[f] || "", mods, missing)).join("\n");
        window.__qsSteamMissing = [...missing];
        if (missing.size && window === host.__qsSteamMain)
            console.warn("[rexilone] нет классов:", [...missing].join(", "));
        if (!style) {
            style = document.createElement("style");
            style.id = STYLE_ID;
        }
        if (style.textContent !== css) style.textContent = css;
        // светлая схема шелла: для неё в теме свои правила (html.qs-light)
        document.documentElement.classList.toggle("qs-light", /--qs-light:\s*1/.test(texts["colors.css"] || ""));
        keepLast();
    }

    // наш стиль должен идти последним, иначе стили Steam, добавленные позже, его перебьют.
    // Не чаще 20 раз в секунду: если кто-то ещё борется за последнее место, не зависаем
    let moves = 0;
    setInterval(() => { moves = 0; }, 1000);
    function keepLast() {
        if (!document.head || !style) return;
        if (document.head.lastElementChild === style) return;
        if (++moves > 20) return;
        document.head.appendChild(style);
    }

    let busy = false;
    async function poll() {
        if (busy) return;
        busy = true;
        let changed = false;
        try {
            await Promise.all(list.map(async f => {
                try {
                    const r = await fetch(BASE + f, { cache: "no-store" });
                    if (!r.ok) return;
                    const t = await r.text();
                    if (texts[f] !== t) { texts[f] = t; changed = true; }
                } catch (e) {}
            }));
            // Steam догрузил новые модули (например, открыли настройки) — пересобираем
            if (changed || !style || moduleCount(host) !== modCount) apply();
        } finally {
            busy = false;
        }
    }

    if (document.title === "Steam") host.__qsSteamMain = window;
    document.documentElement.classList.add("qs-steam");
    add(files);
    setInterval(poll, POLL_MS);
    new MutationObserver(keepLast).observe(document.head, { childList: true });
}

// настоящие классы Steam по понятному имени (как `.%Key@Sib%` в CSS) — для скриптов темы
export function classesOf(key, sib) {
    const set = new Set();
    for (const o of cssModules(hostWindow())) {
        if (!(key in o) || (sib && !(sib in o))) continue;
        for (const c of o[key].split(" ")) set.add(c);
    }
    return [...set];
}

export function selectorOf(key, sib) {
    const cls = classesOf(key, sib);
    return cls.length ? cls.map(c => "." + CSS.escape(c)).join(",") : null;
}

export { hostWindow };
