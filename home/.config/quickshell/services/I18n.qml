pragma Singleton
import QtQuick
import Quickshell

// язык интерфейса Настроек: Settings.language ("en" | "ru").
// I18n.tr("English text") — перевод по словарю ниже; нет перевода — исходный текст.
// Строки вида «A   ·   B» переводятся по частям. Компоненты Настроек (SCard, SSection,
// SButton, SChoice, SDropdown, Page…) переводят свой текст сами.
Singleton {
    id: root

    readonly property string lang: Settings.language || "en"
    readonly property bool ru: lang === "ru"
    // локаль для дат и дней недели: Qt.locale(I18n.locale)
    readonly property string locale: ru ? "ru_RU" : "en_US"

    // число + форма слова: plural(5, "app", "apps", "приложение", "приложения", "приложений")
    function plural(n, one, many, ru1, ru2, ru5) {
        if (!ru) return n === 1 ? one : many;
        const a = Math.abs(n) % 100, b = a % 10;
        if (a > 10 && a < 20) return ru5;
        if (b === 1) return ru1;
        if (b >= 2 && b <= 4) return ru2;
        return ru5;
    }

    function tr(s) {
        if (!ru || s === undefined || s === null || s === "") return s;
        s = String(s);
        const hit = dict[s];
        if (hit !== undefined) return hit;
        const t = s.trim();
        if (dict[t] !== undefined) return s.replace(t, dict[t]);
        // составные подписи: «Dark   ·   dark, light…»
        if (s.indexOf(" · ") >= 0) return s.split(/(\s+·\s+)/).map(p => /·/.test(p) ? p : (dict[p.trim()] !== undefined ? p.replace(p.trim(), dict[p.trim()]) : p)).join("");
        return s;
    }

    readonly property var dict: ({
        // ── окно и разделы
        "Settings": "Настройки",
        "Find a setting": "Найти параметр",
        "Nothing found": "Ничего не найдено",
        "Local account": "Локальная учётная запись",
        "Hardware": "Оборудование",
        "Connections": "Подключения",
        "Look & feel": "Оформление",
        "System": "Система",
        "Display": "Экран",
        "Sound": "Звук",
        "Network & Internet": "Сеть и интернет",
        "Bluetooth": "Bluetooth",
        "Phone": "Телефон",
        "Printers & scanners": "Принтеры и сканеры",
        "Personalization": "Персонализация",
        "Widgets": "Виджеты",
        "Bar": "Бар",
        "Peripherals": "Периферия",
        "Keyboard shortcuts": "Сочетания клавиш",
        "Startup apps": "Автозагрузка",
        "Time & language": "Время и язык",
        "Power": "Питание",
        "Notifications": "Уведомления",
        "About": "О системе",
        "Plugins": "Плагины",

        // ── общее
        "Save": "Сохранить", "Rename": "Переименовать", "Copy": "Копировать", "Copied": "Скопировано",
        "Cancel": "Отмена", "Retry": "Повторить", "Apply": "Применить", "Reset": "Сбросить", "Revert": "Отменить",
        "Add": "Добавить", "Install": "Установить", "Open": "Открыть", "Start": "Запустить", "Stop": "Остановить",
        "Run": "Запустить", "Edit": "Изменить", "Hide": "Скрыть", "Done": "Готово", "Create": "Создать",
        "Change": "Изменить", "Test": "Проверить", "Connect": "Подключить", "Disconnect": "Отключить",
        "Pair": "Сопрячь", "Pairing…": "Сопряжение…", "Decline": "Отклонить", "Sync": "Синхронизировать",
        "Reload": "Обновить", "Rescan": "Пересканировать", "Search again": "Искать снова", "Choose…": "Выбрать…",
        "On": "Вкл", "Off": "Выкл", "Never": "Никогда", "Always": "Всегда", "Normal": "Обычная", "Hidden": "Скрыто",
        "Size": "Размер", "Font": "Шрифт", "Format": "Формат", "Monitor": "Монитор", "Background": "Фон",
        "Kind": "Вид", "Device": "Устройство", "Devices": "Устройства", "Available": "Доступные",
        "Connected": "Подключено", "Paired": "Сопряжено", "Disconnected": "Отключено", "Disabled": "Выключен",
        "Lock": "Блокировка", "Sleep": "Сон", "Screen": "Экран", "Style": "Стиль", "Layout": "Раскладка",
        "Height": "Высота", "Rules": "Правила", "Allow": "Разрешить", "Deny": "Запретить", "Media": "Медиа",
        "Calendar": "Календарь", "Clock": "Часы", "Weather": "Погода", "Battery": "Батарея", "Everything": "Всё",
        "Random": "Случайные", "Browse…": "Выбрать…", "Monday": "Понедельник", "Sunday": "Воскресенье",
        "Language": "Язык", "Account": "Учётная запись", "Shell": "Оболочка", "Service": "Сервис",

        // ── О системе
        "Administrator": "Администратор", "Standard user": "Обычный пользователь",
        "Device specifications": "Характеристики устройства", "Processor": "Процессор", "Graphics": "Видеокарта",
        "Memory": "Память", "Storage": "Накопитель", "Operating system": "Операционная система",
        "Kernel": "Ядро", "Uptime": "Время работы", "For developers": "Для разработчиков",
        "Developer mode": "Режим разработчика",
        "Shows the Plugins page: install and write your own plugins for the shell": "Показывает страницу «Плагины»: устанавливайте и пишите свои плагины для оболочки",

        // ── Автозагрузка
        "Apps and commands that start when you log in": "Приложения и команды, которые запускаются при входе",
        "From niri config": "Из конфига niri", "This shell — can't be turned off here": "Эта оболочка — здесь не отключается",
        "Added here": "Добавлено здесь", "Nothing yet — add an app or a command below": "Пока пусто — добавьте приложение или команду ниже",
        "Add an app": "Добавить приложение", "Choose an app…": "Выберите приложение…", "Add a command": "Добавить команду",
        "Any shell command, e.g. telegram-desktop -startintray": "Любая команда, например telegram-desktop -startintray",
        "Changes apply at the next login. Use «Run» to start something now.": "Изменения применятся при следующем входе. «Запустить» — запустить сейчас.",

        // ── Бар
        "Solid": "Сплошной", "Floating": "Плавающий", "Pills": "Плашки", "Show the bar on": "Показывать бар на",
        "main display": "основной экран", "Clock format": "Формат часов", "Shown in the center of the bar": "В центре бара",
        "Workspaces": "Рабочие столы", "How workspaces look on the left": "Как выглядят рабочие столы слева",
        "Dots": "Точки", "Numbers": "Номера", "Tray apps": "Приложения в трее",
        "In a menu behind a button; pinned apps stay in the bar (pin them in the menu)": "В меню за кнопкой; закреплённые остаются в баре (закрепляются в меню)",
        "All app icons right in the bar": "Все значки прямо в баре", "In the bar": "В баре", "In a menu": "В меню",
        "Modules": "Модули", "Control center": "Центр управления",
        "Quick toggles, volume, media and power in one menu": "Быстрые переключатели, громкость, медиа и питание в одном меню",
        "Active window": "Активное окно", "Title and icon of the focused window": "Заголовок и значок окна в фокусе",
        "Now playing": "Сейчас играет", "Track and play/pause; click opens the player": "Трек и пауза; клик открывает плеер",
        "Temperature next to the clock": "Температура рядом с часами", "CPU & RAM": "Процессор и память",
        "Load at a glance; click opens system stats": "Нагрузка одним взглядом; клик открывает статистику",
        "System updates": "Обновления системы", "Shows available pacman updates; click to update": "Показывает обновления pacman; клик — обновить",
        "Phone (Rexlink)": "Телефон (Rexlink)",
        "Battery and notifications of your phone; click for the phone menu": "Заряд и уведомления телефона; клик — меню телефона",
        "Hidden from screencast": "Скрыто с трансляции",
        "Shown while apps are hidden with Super+G; click for the list": "Виден, пока приложения скрыты через Super+G; клик — список",
        "System tray": "Системный трей", "App icons": "Значки приложений", "Keyboard layout": "Раскладка клавиатуры",
        "en / ru indicator": "Индикатор en / ru", "Volume": "Громкость", "Speaker and mixer": "Динамики и микшер",
        "Microphone": "Микрофон", "Mic level and mute": "Уровень микрофона и отключение", "Network": "Сеть",
        "Connection and speed": "Подключение и скорость", "Bell and notification list": "Колокольчик и список уведомлений",

        // ── Сочетания клавиш
        "Change, turn off or add shortcuts. Changes apply instantly.": "Меняйте, отключайте и добавляйте сочетания. Применяется сразу.",
        "Run a command…": "Выполнить команду…", "Close window": "Закрыть окно", "Fullscreen": "Во весь экран",
        "Maximize column": "Развернуть колонку", "Float / tile window": "Плавающее / в сетке", "Center column": "Колонку по центру",
        "Overview": "Обзор", "Screenshot (region)": "Скриншот (область)", "Screenshot (screen)": "Скриншот (экран)",
        "Screenshot (window)": "Скриншот (окно)", "Workspace up": "Рабочий стол выше", "Workspace down": "Рабочий стол ниже",
        "Focus left": "Фокус влево", "Focus right": "Фокус вправо", "Move window left": "Окно влево",
        "Move window right": "Окно вправо", "Cycle window width": "Сменить ширину окна", "Turn off screens": "Выключить экраны",
        "Show shortcuts overlay": "Показать подсказку сочетаний", "Add a shortcut": "Добавить сочетание",
        "Command, e.g. telegram-desktop": "Команда, например telegram-desktop", "Choose keys…": "Выбрать клавиши…",
        "Shortcuts": "Сочетания", "Search keys or actions": "Поиск по клавишам и действиям",
        "Press the new shortcut": "Нажмите новое сочетание",
        "Hold modifiers (Super, Ctrl, Alt, Shift) and press a key": "Зажмите модификаторы (Super, Ctrl, Alt, Shift) и нажмите клавишу",
        "Add a modifier — a single letter would block typing": "Добавьте модификатор — одна буква мешала бы печатать",
        "Looks good": "Подходит",

        // ── Bluetooth
        "Pair and connect devices": "Сопряжение и подключение устройств", "No Bluetooth adapter": "Нет адаптера Bluetooth",
        "This computer has no Bluetooth adapter, or the bluetooth service is not running.\nPlug in a USB adapter — it will show up here.": "На этом компьютере нет адаптера Bluetooth или служба bluetooth не запущена.\nПодключите USB-адаптер — он появится здесь.",
        "Search for devices": "Искать устройства", "Searching…": "Поиск…",
        "Make sure the device is in pairing mode": "Убедитесь, что устройство в режиме сопряжения",

        // ── Экран
        "Arrange monitors, resolution, refresh rate, scale and rotation": "Расположение мониторов, разрешение, частота, масштаб и поворот",
        "Keep changes": "Сохранить изменения", "Drag monitors to arrange them": "Перетаскивайте мониторы, чтобы расположить их",
        "Main display": "Основной экран",
        "Gets focus at login, shows notifications and desktop widgets by default. Menus open where your cursor is.": "Получает фокус при входе, показывает уведомления и виджеты. Меню открываются там, где курсор.",
        "Display resolution": "Разрешение экрана",
        "Pick the resolution; the highest refresh rate is chosen automatically": "Выберите разрешение; максимальная частота подставится сама",
        "(recommended)": "(рекомендуется)", "Refresh rate": "Частота обновления", "Higher is smoother": "Чем выше, тем плавнее",
        "Scale": "Масштаб", "Size of text and apps": "Размер текста и приложений", "(default)": "(по умолчанию)",
        "Rotation": "Поворот", "Variable refresh rate": "Переменная частота",
        "FreeSync / VRR — smoother games, less tearing": "FreeSync / VRR — плавнее в играх, меньше разрывов",
        "Use this display": "Использовать этот экран", "Turn the monitor off without unplugging it": "Выключить монитор, не отключая кабель",
        "You have unapplied changes": "Есть неприменённые изменения", "Night light": "Ночной свет",
        "Warmer colors that are easier on the eyes at night": "Тёплые цвета, мягче для глаз ночью",
        "Needs wlsunset — install it first": "Нужен wlsunset — сначала установите его", "Schedule": "Расписание",
        "Set a weather city to use sunset to sunrise": "Укажите город в погоде, чтобы включать от заката до рассвета",
        "Sunset → sunrise": "Закат → рассвет", "Warmth": "Теплота", "Lower is warmer": "Чем ниже, тем теплее",

        // ── Сеть
        "Connection status and firewall": "Состояние подключения и брандмауэр",
        "Automatic (from network / VPN)": "Автоматически (из сети / VPN)", "Custom…": "Свои…", "Connection": "Подключение",
        "No active connection": "Нет активного подключения", "no IPv4": "нет IPv4", "Gateway & DNS": "Шлюз и DNS",
        "No VPN interfaces up": "Нет активных VPN",
        "Wi-Fi adapter found — install iwd or NetworkManager to manage networks": "Найден Wi-Fi адаптер — установите iwd или NetworkManager для управления сетями",
        "No Wi-Fi adapter detected on this computer": "На этом компьютере нет Wi-Fi адаптера", "DNS server": "DNS-сервер",
        "Used for all connections. Changing it needs your password.": "Для всех подключений. Для смены нужен пароль.",
        "Custom servers": "Свои серверы", "e.g. 1.1.1.1 or 2606:4700::1111": "например 1.1.1.1 или 2606:4700::1111",
        "Encrypted DNS (DNS over TLS)": "Зашифрованный DNS (DNS over TLS)",
        "Hides your DNS queries from the provider": "Скрывает ваши DNS-запросы от провайдера", "In use now": "Сейчас используется",
        "Firewall (ufw)": "Брандмауэр (ufw)", "Firewall": "Брандмауэр",
        "Active — incoming connections are filtered": "Включён — входящие подключения фильтруются",
        "Viewing rules needs your password": "Для просмотра правил нужен пароль", "Show rules": "Показать правила",
        "No rules": "Правил нет", "Add rule": "Добавить правило",
        "Port or range with optional protocol: 22, 8080/tcp, 6000:6010/udp": "Порт или диапазон, можно с протоколом: 22, 8080/tcp, 6000:6010/udp",
        "AdGuard (blocks ads) — 94.140.14.14": "AdGuard (блокирует рекламу) — 94.140.14.14",

        // ── Уведомления
        "Pop-ups and Do not disturb": "Всплывающие и «Не беспокоить»", "Do not disturb": "Не беспокоить",
        "Hide pop-ups; critical notifications and reminders still show": "Скрыть всплывающие; важные и напоминания всё равно видны",
        "Pop-up duration": "Время показа", "When the app doesn't set its own": "Если приложение не задало своё",
        "Notification history": "История уведомлений", "Clear all": "Очистить всё", "Send a test notification": "Отправить тестовое",

        // ── Периферия
        "Keyboard, mouse, graphics tablet, gamepads, printers and scanners": "Клавиатура, мышь, графический планшет, геймпады, принтеры и сканеры",
        "Keyboard": "Клавиатура", "typing, layout switching": "набор текста, смена раскладки", "Mouse": "Мышь",
        "Pointer speed, buttons, scrolling": "Скорость указателя, кнопки, прокрутка", "Touchpad": "Тачпад",
        "Taps, scrolling, right click": "Касания, прокрутка, правый клик", "Graphics tablet": "Графический планшет",
        "Not connected": "Не подключён", "screen, orientation": "экран, ориентация", "Gamepads": "Геймпады",
        "None connected": "Не подключены", "test buttons and sticks": "проверка кнопок и стиков",
        "Add a printer, print a test page, scan documents": "Добавить принтер, тестовая страница, сканирование",
        "English (US)": "Английский (США)", "Russian": "Русский", "Ukrainian": "Украинский", "Belarusian": "Белорусский",
        "Kazakh": "Казахский", "German": "Немецкий", "French": "Французский", "Spanish": "Испанский", "Italian": "Итальянский",
        "Polish": "Польский", "Czech": "Чешский", "Turkish": "Турецкий", "English (UK)": "Английский (Великобритания)",
        "Japanese": "Японский", "Georgian": "Грузинский", "Add device": "Добавить устройство", "Layouts": "Раскладки",
        "Order matters: the first one is the default": "Порядок важен: первая — по умолчанию", "+ Add layout": "+ Добавить раскладку",
        "Switch layout with": "Переключать раскладку", "Typing": "Набор текста", "Repeat delay": "Задержка повтора",
        "How long to hold a key before it repeats": "Сколько держать клавишу до начала повтора", "Repeat rate": "Скорость повтора",
        "Characters per second while holding a key": "Символов в секунду при удержании", "Num Lock on startup": "Num Lock при запуске",
        "Change or add your own key bindings": "Изменить или добавить свои сочетания", "Pointer": "Указатель",
        "Pointer speed": "Скорость указателя", "Acceleration": "Ускорение",
        "Flat is best for games — speed doesn't depend on how fast you move": "Без ускорения лучше для игр — скорость не зависит от резкости движения",
        "Adaptive": "Адаптивное", "Flat": "Без ускорения", "Left-handed": "Для левши", "Swap left and right buttons": "Поменять левую и правую кнопки",
        "Focus follows mouse": "Фокус за курсором", "Focus windows by hovering them": "Окно получает фокус при наведении",
        "Scrolling and buttons": "Прокрутка и кнопки", "Natural scrolling": "Естественная прокрутка",
        "Content moves in the direction of the wheel": "Содержимое движется в сторону колёсика", "Scroll speed": "Скорость прокрутки",
        "How far one wheel step scrolls": "Насколько прокручивает один щелчок колёсика",
        "Middle click with both buttons": "Средний клик двумя кнопками",
        "Pressing left and right together acts as a middle click": "Нажатие левой и правой вместе — средний клик",
        "Turn it off completely": "Полностью отключить", "Tap to click": "Касание — клик", "Disable while typing": "Отключать при наборе",
        "Disable when a mouse is connected": "Отключать при подключённой мыши", "Right click": "Правый клик",
        "Bottom-right corner, or press with two fingers": "Нижний правый угол или нажатие двумя пальцами",
        "Corner": "Угол", "Two fingers": "Два пальца", "No graphics tablet connected": "Графический планшет не подключён",
        "Wacom, Huion, XP-Pen and other tablets work out of the box. Settings below apply when one is connected": "Wacom, Huion, XP-Pen и другие работают сразу. Параметры ниже применятся при подключении",
        "all screens": "все экраны", "Pen buttons: lower — right click, upper — middle click": "Кнопки пера: нижняя — правый клик, верхняя — средний",
        "Mapping": "Привязка", "Which monitor the tablet draws on": "На каком мониторе рисует планшет", "All monitors": "Все мониторы",
        "Orientation": "Ориентация",
        "Left-handed turns the tablet upside down; 90° for a portrait monitor": "«Для левши» переворачивает планшет; 90° — для вертикального монитора",
        "Left-handed turns the tablet upside down": "«Для левши» переворачивает планшет", "Keep proportions": "Сохранять пропорции",
        "Use part of the tablet so a circle on it is a circle on the screen": "Использовать часть планшета, чтобы круг на нём был кругом на экране",
        "Rotation by 90° and keeping proportions work only for pen displays: niri passes them to libinput, which ignores them for regular tablets.": "Поворот на 90° и пропорции работают только для планшетов-экранов: niri передаёт их в libinput, а тот игнорирует их для обычных планшетов.",
        "Tablet": "Планшет", "Turn the pen input off completely": "Полностью отключить перо", "No gamepads connected": "Геймпады не подключены",
        "Plug in by USB or pair over Bluetooth (hold the pairing button on the controller)": "Подключите по USB или сопрягите по Bluetooth (зажмите кнопку сопряжения на геймпаде)",
        "Press buttons and move the sticks": "Нажимайте кнопки и двигайте стики", "Games in Steam": "Игры в Steam",
        "Button layouts per game are set in Steam → Settings → Controller": "Раскладка кнопок для игр — в Steam → Настройки → Контроллер",
        "Wireless receiver": "Беспроводной приёмник", "Built-in": "Встроенное",

        // ── Персонализация
        "Colors, wallpaper, fonts, the bar and desktop widgets": "Цвета, обои, шрифты, бар и виджеты рабочего стола",
        "Colors": "Цвета", "Wallpaper": "Обои", "Pick a picture for the desktop": "Выберите картинку для рабочего стола",
        "Transparency": "Прозрачность", "blur": "размытие", "Fonts": "Шрифты", "Interface and terminal fonts": "Шрифты интерфейса и терминала",
        "Text size": "Размер текста", "bar and menus": "бар и меню", "clock, modules, tray": "часы, модули, трей",
        "clock, weather, phone…": "часы, погода, телефон…", "No wallpaper": "Без обоев", "From wallpaper": "Из обоев",
        "dark, light, Nord, Gruvbox, Rosé, from wallpaper": "тёмная, светлая, Nord, Gruvbox, Rosé, из обоев",
        "Colors follow the current wallpaper and update when you change it.": "Цвета берутся из обоев и обновляются при их смене.",
        "Transparency effects": "Эффекты прозрачности", "See-through bar, menus and settings window": "Прозрачные бар, меню и окно настроек",
        "Panel opacity": "Непрозрачность панелей", "Lower is more transparent": "Чем ниже, тем прозрачнее",
        "Blur behind panels": "Размытие под панелями", "Frosted glass look (niri background blur)": "Эффект матового стекла (размытие niri)",
        "Terminal opacity": "Непрозрачность терминала", "foot — applies to new terminal windows": "foot — для новых окон терминала",
        "Interface font": "Шрифт интерфейса", "Bar, menus, notifications and settings": "Бар, меню, уведомления и настройки",
        "Terminal font": "Шрифт терминала", "foot, Neovim and yazi — monospace fonts only": "foot, Neovim и yazi — только моноширинные",
        "Apps font": "Шрифт приложений", "GTK apps (Files, settings dialogs…)": "GTK-приложения (файлы, диалоги…)",
        "System default": "Системный",
        "Icons need a Nerd Font — if icons turn into boxes, pick a font with «Nerd Font» in the name.": "Значкам нужен Nerd Font — если вместо них квадраты, выберите шрифт с «Nerd Font» в названии.",
        "Scales fonts and icons in the bar and menus": "Масштаб шрифтов и значков в баре и меню",
        "Dark": "Тёмная", "Light": "Светлая",

        // ── Телефон
        "Rexlink — notifications, calls, files and clipboard from your Android devices": "Rexlink — уведомления, звонки, файлы и буфер обмена с Android-устройств",
        "Rexlink is not installed": "Rexlink не установлен", "Rexlink is running": "Rexlink запущен", "Rexlink is not running": "Rexlink не запущен",
        "Start it to connect your phone": "Запустите, чтобы подключить телефон", "Open app": "Открыть приложение",
        "Start with the system": "Запускать с системой", "Runs Rexlink in the background after login (rexlink.service)": "Запускает Rexlink в фоне после входа (rexlink.service)",
        "No devices yet — install Rexlink on your phone and pair it": "Устройств пока нет — установите Rexlink на телефон и сопрягите",
        "current": "текущий", "Make current": "Сделать текущим", "Phone notifications": "Уведомления телефона",
        "Get notifications from the phone": "Получать уведомления с телефона", "Show them on the desktop": "Показывать на рабочем столе",
        "As regular pop-up notifications": "Как обычные всплывающие уведомления", "Calls": "Звонки",
        "Incoming call card with Answer / Decline": "Карточка входящего звонка с «Ответить» / «Отклонить»",
        "Messages (SMS)": "Сообщения (SMS)", "Read and send SMS from the PC": "Читать и отправлять SMS с компьютера",
        "Shared clipboard": "Общий буфер обмена", "Copy on one device — paste on the other": "Копируйте на одном устройстве — вставляйте на другом",
        "Images in clipboard": "Картинки в буфере", "Also sync copied pictures": "Синхронизировать и скопированные картинки",
        "Phone media": "Медиа телефона", "Control what plays on the phone": "Управлять тем, что играет на телефоне",
        "PC media on phone": "Медиа компьютера на телефоне", "Control PC players from the phone": "Управлять плеерами компьютера с телефона",
        "Update the phone app": "Обновлять приложение на телефоне", "Install new app versions on devices automatically": "Ставить новые версии приложения на устройства автоматически",
        "Files & camera": "Файлы и камера", "Received files": "Полученные файлы", "Phone as webcam": "Телефон как веб-камера",
        "Needs v4l2loopback (see Rexlink docs)": "Нужен v4l2loopback (см. документацию Rexlink)", "Front": "Фронтальная", "Back": "Основная",
        "Webcam quality": "Качество веб-камеры", "Screen sharing": "Трансляция экрана",
        "Hide calls from screencast": "Скрывать звонки с трансляции",
        "Viewers see an empty spot instead of the incoming call card. You still see it": "Зрители видят пустое место вместо карточки звонка. Вы её видите",
        "Hide phone notifications from screencast": "Скрывать уведомления телефона с трансляции",
        "Phone notifications and the phone menu in the bar are blacked out for viewers": "Уведомления телефона и меню телефона в баре скрыты от зрителей",
        "In the shell": "В оболочке", "Phone in the bar": "Телефон в баре",
        "Battery and notifications; click for the phone menu, right-click to find it": "Заряд и уведомления; клик — меню телефона, правый клик — найти его",
        "Battery percent": "Процент заряда", "Show the number next to the battery icon": "Показывать число рядом со значком батареи",
        "Show when offline": "Показывать без подключения", "Keep the icon in the bar when the phone isn't connected": "Оставлять значок, когда телефон не подключён",
        "Incoming call card": "Карточка входящего звонка", "Answer or decline calls from the desktop": "Отвечать и отклонять звонки с компьютера",

        // ── Плагины
        "Extend the shell with your own modules — see README.md in the plugins folder": "Расширяйте оболочку своими модулями — см. README.md в папке плагинов",
        "Developer tools": "Инструменты разработчика", "Create a plugin": "Создать плагин",
        "Copies a ready template with a bar module, a service and a settings page": "Копирует готовый шаблон с модулем бара, сервисом и страницей настроек",
        "Plugin name": "Название плагина", "Plugins folder": "Папка плагинов",
        "Each plugin is a folder with plugin.json. See README.md there.": "Каждый плагин — папка с plugin.json. Подробнее в README.md.",
        "Rescan plugins after adding one; restart the shell after changing plugin code": "Пересканируйте после добавления; перезапустите оболочку после правки кода",
        "Restart shell": "Перезапустить оболочку", "Shell log": "Журнал оболочки",
        "Errors from plugins show up here (qs log)": "Здесь видны ошибки плагинов (qs log)", "IPC commands": "Команды IPC",
        "No plugins yet — create one above": "Плагинов пока нет — создайте выше",
        "Couldn't load the settings page — check the shell log": "Не удалось загрузить страницу настроек — смотрите журнал оболочки",

        // ── Питание
        "Screen, sleep and power mode": "Экран, сон и режим питания", "Screen & sleep": "Экран и сон",
        "Lock the screen after": "Блокировать экран через", "With swaylock": "Через swaylock",
        "Turn off the screens after": "Выключать экраны через", "They wake up on mouse or keyboard": "Включаются от мыши или клавиатуры",
        "Put the computer to sleep after": "Переводить в сон через", "Lock before sleep": "Блокировать перед сном",
        "Keep awake": "Не засыпать",
        "Pause all timers above (also: qs ipc call idle caffeine). Videos and games already keep the screen on.": "Приостановить все таймеры выше (также: qs ipc call idle caffeine). Видео и игры и так не дают экрану гаснуть.",
        "Power mode": "Режим питания", "Power profiles are not installed": "Профили питания не установлены",
        "power-profiles-daemon switches between Power saver, Balanced and Performance": "power-profiles-daemon переключает «Экономию», «Баланс» и «Производительность»",
        "Saver": "Экономия", "Balanced": "Баланс", "Performance": "Производительность", "Power menu…": "Меню питания…",

        // ── Принтеры
        "Printers": "Принтеры", "Add a printer": "Добавить принтер", "No printers yet": "Принтеров пока нет",
        "Connect a printer by USB or network and press «Add a printer»": "Подключите принтер по USB или сети и нажмите «Добавить принтер»",
        "default": "по умолчанию", "Set default": "По умолчанию", "Test page": "Тестовая страница", "Print queue": "Очередь печати",
        "Scanners": "Сканеры", "Scanner support is not installed": "Поддержка сканеров не установлена",
        "Installs SANE drivers and the Document Scanner app (needs your password)": "Установит драйверы SANE и «Сканер документов» (нужен пароль)",
        "Looking for scanners…": "Поиск сканеров…", "No scanners found": "Сканеры не найдены",
        "Make sure the scanner is on and connected": "Убедитесь, что сканер включён и подключён", "Scan": "Сканировать",
        "CUPS web interface": "Веб-интерфейс CUPS", "Advanced printer options at localhost:631": "Расширенные параметры принтеров на localhost:631",

        // ── Звук
        "Output and input devices, volume and per-app volume": "Устройства вывода и ввода, громкость, громкость приложений",
        "Output": "Вывод", "Input": "Ввод", "More sound settings": "Ещё настройки звука",
        "Open pavucontrol for profiles and advanced options": "Открыть pavucontrol: профили и расширенные параметры",

        // ── Система
        "Monitors": "Мониторы", "Devices and apps": "Устройства и приложения", "Keyboard, mouse, tablet, gamepads": "Клавиатура, мышь, планшет, геймпады",
        "About this PC": "Об этом компьютере", "Device name, account and specifications": "Имя устройства, учётная запись и характеристики",
        "Reload the bar and all menus": "Перезагрузить бар и все меню", "Open niri config": "Открыть конфиг niri",

        // ── Время и язык
        "Time zone, clock format and system language": "Часовой пояс, формат часов и язык системы",
        "English (United States)": "Английский (США)", "English (United Kingdom)": "Английский (Великобритания)",
        "Date & time": "Дата и время", "Time zone": "Часовой пояс", "Set time automatically": "Устанавливать время автоматически",
        "Synchronize with internet time servers (NTP)": "Синхронизация с серверами времени (NTP)", "Time format": "Формат времени",
        "Used by the bar clock": "Для часов в баре", "First day of week": "Первый день недели", "In the calendar": "В календаре",
        "System language": "Язык системы",
        "Language of apps and system messages. Takes effect after you log in again.": "Язык приложений и системных сообщений. Применится после повторного входа.",
        "Add a language": "Добавить язык", "Generates the language on this computer (needs your password)": "Генерирует язык на этом компьютере (нужен пароль)",
        "Keyboard layouts": "Раскладки клавиатуры", "24-hour": "24 часа", "12-hour": "12 часов", "Settings language": "Язык настроек",
        "Language of this Settings window": "Язык окна настроек",

        // ── Виджеты
        "Big time and date": "Крупные время и дата", "CPU, GPU and RAM rings": "Кольца процессора, видеокарты и памяти",
        "Now and next 3 days": "Сейчас и на 3 дня", "What's playing, with controls": "Что играет, с управлением",
        "Month view with notes": "Месяц с заметками", "Today's notes": "Заметки на сегодня",
        "Notes and reminders for today": "Заметки и напоминания на сегодня", "Quote of the day": "Цитата дня",
        "Changes daily, click for next": "Меняется каждый день, клик — следующая",
        "Editing — drag widgets on the desktop": "Редактирование — перетаскивайте виджеты на рабочем столе",
        "Arrange widgets": "Расставить виджеты",
        "Widgets float above windows while editing. Press Done to lock them in place.": "Во время правки виджеты поверх окон. Нажмите «Готово», чтобы закрепить.",
        "Edit layout": "Расставить", "Card behind the widget, or just content over the wallpaper": "Карточка под виджетом или только содержимое поверх обоев",
        "Same as interface": "Как в интерфейсе", "Show date": "Показывать дату", "Phone widgets": "Виджеты телефона",
        "Status & signal": "Состояние и сигнал", "Quick actions": "Быстрые действия", "Current device": "Текущее устройство",
        "(offline)": "(не в сети)", "Rexlink isn't running": "Rexlink не запущен",
        "Phone widgets show data from Rexlink — start it in Settings → Phone": "Виджеты телефона берут данные из Rexlink — запустите его в Настройки → Телефон",
        "Add a phone widget": "Добавить виджет телефона",
        "One per device and kind — e.g. tablet battery next to phone notifications": "По одному на устройство и вид — например, заряд планшета рядом с уведомлениями телефона",
        "unknown device": "неизвестное устройство", "current device": "текущее устройство",

        // ═══════════ оболочка: бар, меню, окна
        // календарь и часы
        "Mo": "Пн", "Tu": "Вт", "We": "Ср", "Th": "Чт", "Fr": "Пт", "Sa": "Сб", "Su": "Вс",
        "Today": "Сегодня", "No notes for today": "На сегодня заметок нет", "No notes\nadd one below": "Заметок нет\nдобавьте ниже",
        "Add a note…": "Добавить заметку…", "Player": "Плеер",
        // центр управления
        "Focus": "Фокус", "Awake": "Без сна", "Night": "Ночь", "Record": "Запись", "Snip": "Снимок", "Region": "Область",
        "Clipboard": "Буфер", "History": "История", "Find phone": "Найти телефон", "Offline": "Не в сети",
        "Wi-Fi": "Wi-Fi", "Ethernet": "Ethernet",
        // звук
        "INPUT DEVICE": "УСТРОЙСТВО ВВОДА", "OUTPUT DEVICE": "УСТРОЙСТВО ВЫВОДА", "APPS": "ПРИЛОЖЕНИЯ",
        "No app is using the microphone": "Микрофон никто не использует", "Nothing is playing": "Ничего не играет",
        "System audio": "Системный звук",
        // сеть
        "IPv4": "IPv4", "IPv6": "IPv6", "Gateway": "Шлюз", "Signal": "Сигнал", "Received": "Получено", "Sent": "Отправлено",
        // уведомления
        "All caught up": "Всё прочитано", "Clear": "Очистить", "No notifications": "Уведомлений нет",
        // трей и скрытие с трансляции
        "Tray": "Трей", "No apps in the tray": "В трее нет приложений",
        "Right-click — app menu. Pin — keep the icon in the bar.": "Правый клик — меню приложения. Булавка — оставить значок в баре.",
        "App menu": "Меню приложения", "Show": "Показать", "active window": "активное окно",
        "1 app is blacked out for viewers": "1 приложение скрыто от зрителей",
        "Super+G hides or shows the active app. Viewers see a black box in its place.": "Super+G скрывает или показывает активное приложение. Зрители видят на его месте чёрный прямоугольник.",
        // телефон
        "No paired devices": "Нет сопряжённых устройств", "Start Rexlink to connect your phone": "Запустите Rexlink, чтобы подключить телефон",
        "Send files": "Отправить файлы", "Get clipboard": "Взять буфер", "Webcam on": "Камера включена", "Send": "Отправить",
        "Call": "Звонок", "PHONE NOTIFICATIONS": "УВЕДОМЛЕНИЯ ТЕЛЕФОНА", "Find": "Найти", "Files": "Файлы", "Webcam": "Камера",
        "Messages": "Сообщения", "Charging": "Заряжается", "No device": "Нет устройства", "Rexlink is off": "Rexlink выключен",
        "Wi-Fi off": "Wi-Fi выкл", "Nothing new": "Ничего нового", "Device is offline": "Устройство не в сети",
        "Nothing playing": "Ничего не играет", "Temperature": "Температура", "Incoming call": "Входящий звонок",
        "phone": "телефон", "Silence": "Без звука", "Answer": "Ответить",
        // погода
        "Set your city in the clock menu → Weather": "Укажите город в меню часов → Погода", "Change city…": "Сменить город…",
        "Search city, e.g. London": "Поиск города, например Москва", "Find your city below": "Найдите свой город ниже",
        "updating…": "обновление…", "Unknown": "Неизвестно",
        "Clear sky": "Ясно", "Mostly clear": "Малооблачно", "Partly cloudy": "Переменная облачность", "Overcast": "Пасмурно",
        "Fog": "Туман", "Rime fog": "Изморозь", "Light drizzle": "Слабая морось", "Drizzle": "Морось", "Heavy drizzle": "Сильная морось",
        "Freezing drizzle": "Ледяная морось", "Light rain": "Небольшой дождь", "Rain": "Дождь", "Heavy rain": "Сильный дождь",
        "Freezing rain": "Ледяной дождь", "Light snow": "Небольшой снег", "Snow": "Снег", "Heavy snow": "Сильный снег",
        "Snow grains": "Снежная крупа", "Showers": "Ливень", "Heavy showers": "Сильный ливень", "Snow showers": "Снегопад",
        "Thunderstorm": "Гроза", "Thunderstorm, hail": "Гроза с градом",
        // виджеты рабочего стола
        "CPU": "ЦП", "GPU": "ГП", "RAM": "ОЗУ", "Drag widgets to move them": "Перетаскивайте виджеты, чтобы переместить",
        // буфер обмена
        "Search clipboard…": "Поиск в буфере…", "Confirm clear?": "Точно очистить?", "Clipboard is empty": "Буфер обмена пуст",
        "Enter — copy · Del — delete · Ctrl+Del — clear all": "Enter — копировать · Del — удалить · Ctrl+Del — очистить всё",
        // запуск приложений
        "Lock screen": "Заблокировать экран", "Power menu": "Меню питания", "Record screen": "Запись экрана",
        "Wallpapers": "Обои", "Clipboard history": "История буфера обмена", "Dark / light theme": "Тёмная / светлая тема",
        "Type a command…": "Введите команду…", "Runs in a terminal, stays open": "Выполнится в терминале, окно останется",
        "Web": "Интернет", "Type what to search…": "Что искать…", "Frequent": "Частые", "All apps": "Все приложения",
        "Calculator": "Калькулятор", "Apps": "Приложения", "Open in Settings": "Открыть в настройках",
        "Type to search…": "Начните вводить…", "Actions": "Действия", "actions": "действия", "Pinned": "Закреплённые",
        "No actions": "Нет действий", "Run in terminal": "Выполнить в терминале", "Search": "Найти",
        "Open settings": "Открыть настройки", "Do it": "Выполнить", "Command": "Команда", "Enter copies the result": "Enter копирует результат",
        "open": "открыть", "move": "выбор", "pin": "закрепить", "pinned": "закреплённые", "math": "калькулятор",
        "command": "команда", "web": "интернет", "run": "выполнить", "back": "назад", "close": "закрыть",
        "Pinned ": "Закреплено ",
        // окно polkit
        "Authentication required": "Требуется аутентификация", "Password": "Пароль",
        "Wrong password, try again": "Неверный пароль, попробуйте ещё раз", "Enter — confirm · Esc — cancel": "Enter — подтвердить · Esc — отмена",
        // меню питания
        "Suspend": "Сон", "Logout": "Выйти", "Reboot": "Перезагрузка", "Shutdown": "Выключение", "Confirm?": "Подтвердить?", "up": "работает",
        // запись экрана
        "Paused": "Пауза", "Recording": "Идёт запись", "no audio": "без звука", "system audio": "системный звук",
        "system + mic": "система + микрофон", "Source": "Источник", "Window": "Окно", "Audio": "Звук", "High": "Высокое",
        "Very high": "Очень высокое", "Ultra": "Максимальное", "Start recording": "Начать запись", "Instant replay": "Мгновенный повтор",
        "keeps the last moments in memory": "держит последние моменты в памяти", "Quality": "Качество",
        "Enter  start / stop   ·   P  pause   ·   R  save replay   ·   Esc  close": "Enter  старт / стоп   ·   P  пауза   ·   R  сохранить повтор   ·   Esc  закрыть",
        // обои
        "loading…": "загрузка…", "Search…": "Поиск…",
        "←/→  browse   ·   Enter  apply   ·   type to search   ·   Esc  close": "←/→  листать   ·   Enter  применить   ·   ввод — поиск   ·   Esc  закрыть",
        // цитаты
        "Simplicity is the ultimate sophistication.": "Простота — высшая степень изощрённости.", "Leonardo da Vinci": "Леонардо да Винчи",
        "Talk is cheap. Show me the code.": "Слова ничего не стоят. Покажи код.", "Linus Torvalds": "Линус Торвальдс",
        "Make it work, make it right, make it fast.": "Сначала чтобы работало, потом правильно, потом быстро.", "Kent Beck": "Кент Бек",
        "The best way to predict the future is to invent it.": "Лучший способ предсказать будущее — изобрести его.", "Alan Kay": "Алан Кэй",
        "Less is more.": "Меньше — значит больше.", "Ludwig Mies van der Rohe": "Людвиг Мис ван дер Роэ",
        "Stay hungry, stay foolish.": "Оставайтесь голодными, оставайтесь безрассудными.", "Steve Jobs": "Стив Джобс",
        "Programs must be written for people to read.": "Программы пишут для того, чтобы их читали люди.", "Harold Abelson": "Гарольд Абельсон",
        "Done is better than perfect.": "Сделанное лучше идеального.", "Sheryl Sandberg": "Шерил Сэндберг",
        "First, solve the problem. Then, write the code.": "Сначала реши задачу, потом пиши код.", "John Johnson": "Джон Джонсон",
        "Kaizen: a little better every day.": "Кайдзен: каждый день чуть лучше.", "Japanese proverb": "Японская пословица",
        // язык
        "App launcher": "Меню приложений", "Button at the very left that opens the app menu (Super+D)": "Кнопка в самом начале бара, открывает меню приложений (Super+D)",
        "running": "работает", "not running": "не запущен", "of": "из", "Full": "Весь",
        "Area follows the screen's shape, so a circle on the tablet is a circle on the screen": "Область повторяет форму экрана — круг на планшете будет кругом на экране",
        "Pen buttons, pressure curve and filters — in the driver's own app": "Кнопки пера, кривая нажима и фильтры — в приложении драйвера",
        "Updates": "Обновления", "Shell updates from GitHub and system packages": "Обновления оболочки с GitHub и пакеты системы",
        "Updating…": "Обновление…", "Checking for updates…": "Проверка обновлений…", "Not installed from git": "Установлено не из git",
        "Couldn't check for updates": "Не удалось проверить обновления", "You're up to date": "Установлена последняя версия",
        "Last checked": "Проверено", "Check": "Проверить", "Update": "Обновить",
        "The repository is empty for now": "Репозиторий пока пуст", "Couldn't reach the repository": "Нет связи с репозиторием",
        "You have local changes": "Есть локальные изменения", "New packages are needed": "Нужны новые пакеты",
        "Install packages": "Установить пакеты", "Install from git to get updates": "Чтобы получать обновления, установите из git",
        "What's new": "Что нового", "Update settings": "Настройки обновлений", "Check automatically": "Проверять автоматически",
        "A minute after login and every 6 hours; you get a notification when there's something new": "Через минуту после входа и каждые 6 часов; при новинках придёт уведомление",
        "Repository": "Репозиторий", "Branch": "Ветка", "System packages": "Пакеты системы",
        "Update checker is not installed": "Проверка обновлений не установлена", "Checking packages…": "Проверка пакетов…",
        "Packages are up to date": "Пакеты обновлены",
        "pacman-contrib (checkupdates) counts updates without touching the system": "pacman-contrib (checkupdates) считает обновления, не трогая систему",
        "Interface language": "Язык интерфейса", "Bar, menus, widgets and settings — the whole shell": "Бар, меню, виджеты и настройки — вся оболочка",
    })
}
