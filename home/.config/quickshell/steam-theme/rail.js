// Узкая панель иконок главного окна. Кнопки — настоящие элементы Steam, переставленные в theme.css;
// здесь им ставятся подсказки (их подписи спрятаны) и добавляется «Настройки»
// (у Steam такой кнопки нет, настройки открываются из меню Steam).
//
// Подменю вкладок (Магазин → Рекомендации, Список желаемого…) Steam открывает при наведении:
// в узкой панели оно ложится на соседние иконки и подсказки. Поэтому наведение их не открывает,
// а правый клик по иконке — открывает.
import { selectorOf, hostWindow } from "./qs-loader.js";

export function rail() {
    const host = hostWindow();
    const lang = /LANGUAGE=(\w+)/.exec(host.location.search || "");
    const settingsLabel = lang && lang[1] === "russian" ? "Настройки" : "Settings";

    const q = (key, sib) => {
        const sel = selectorOf(key, sib);
        return sel ? [...document.querySelectorAll(sel)] : [];
    };
    const tip = (el, text) => {
        text = (text || "").trim();
        if (el && text && el.getAttribute("data-qs-tip") !== text) el.setAttribute("data-qs-tip", text);
    };

    function ensure() {
        const bar = q("BottomBar", "AddGameButton")[0];
        if (bar && !bar.querySelector(".qs-settings")) {
            const item = document.createElement("div");
            item.className = "qs-rail-item qs-settings";
            item.addEventListener("click", () => host.SteamClient.URL.ExecuteSteamURL("steam://open/settings"));
            bar.appendChild(item);
        }
        const settings = bar && bar.querySelector(".qs-settings");
        tip(settings, settingsLabel);

        for (const m of q("SuperNavMenu")) tip(m, m.textContent);
        for (const b of q("AddGameButton")) tip(b, b.textContent);
        for (const b of q("FriendsButton")) tip(b, b.textContent);
        // у загрузок в подсказке и очередь, и прогресс («Загрузка 45%…»)
        for (const d of q("DownloadStatus", "AddGameButton")) tip(d, d.textContent);
    }

    // ── подменю вкладок: только по правому клику
    const navSel = selectorOf("SuperNavMenu");
    let allow = null;   // вкладка, у которой подменю сейчас разрешено

    function reactProps(node) {
        const k = Object.keys(node).find(k => k.startsWith("__reactProps"));
        return k ? node[k] : null;
    }
    // React читает обработчики из этого объекта при каждом событии — подменяем перед ним
    function gate(node) {
        const p = reactProps(node);
        if (!p) return;
        if (p.onMouseEnter && p.onMouseEnter !== node.__qsEnter) node.__qsEnter = p.onMouseEnter;
        p.onMouseEnter = node === allow ? node.__qsEnter : undefined;
    }
    function navOf(t) {
        return navSel && t instanceof Element ? t.closest(navSel) : null;
    }

    // слушатели на window в фазе захвата срабатывают раньше React
    for (const type of ["mouseover", "mouseout", "pointerover", "pointerout"]) {
        window.addEventListener(type, e => {
            for (const t of [e.target, e.relatedTarget]) {
                const n = navOf(t);
                if (n) gate(n);
            }
            // ушли с вкладки, у которой открывали подменю, — снова только по правому клику
            if (allow && e.type === "mouseout" && navOf(e.target) === allow && navOf(e.relatedTarget) !== allow)
                setTimeout(() => { const a = allow; allow = null; if (a) gate(a); }, 0);
        }, true);
    }
    window.addEventListener("contextmenu", e => {
        const n = navOf(e.target);
        if (!n) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        allow = n;
        gate(n);
        // «вход» мыши извне — React вызовет onMouseEnter, и Steam откроет подменю у этой вкладки
        const r = n.getBoundingClientRect();
        n.dispatchEvent(new MouseEvent("mouseover", {
            bubbles: true, relatedTarget: null, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2,
        }));
    }, true);

    // React может перерисовать элементы — тогда подсказки, пункт и запрет появятся снова
    function tick() {
        ensure();
        if (navSel) for (const n of document.querySelectorAll(navSel)) gate(n);
    }
    tick();
    setInterval(tick, 1500);
}
