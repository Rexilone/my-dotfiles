# Плагины Rexilone Shell

Плагин — это папка в `~/.config/quickshell/plugins/<id>/` с файлом `plugin.json`
и QML-файлами. Плагины видны на странице **Настройки → Plugins**, которая появляется
после включения **Настройки → About → Developer mode**.

Плагин — это обычный код QML/JavaScript, который выполняется внутри шелла с твоими правами.
Поэтому все плагины по умолчанию **выключены**: включай только те, которым доверяешь.

## Быстрый старт

1. Настройки → About → включи **Developer mode**.
2. Настройки → Plugins → **Create a plugin**, введи название → **Create**.
   Появится папка `plugins/<id>/` с готовым шаблоном.
3. Включи плагин переключателем. В баре появится его модуль, а в Настройках — страница.
4. Нажми **Edit**: откроется Neovim в папке плагина. После правок нажми **Restart shell**.

Для примера есть готовый плагин `hello-world`: счётчик кликов в баре,
IPC-команда `qs ipc call hello greet` и страница настроек.

## plugin.json

```json
{
    "id": "my-plugin",
    "name": "My plugin",
    "version": "1.0.0",
    "author": "Rexilone",
    "description": "Что делает плагин",
    "bar": "Bar.qml",
    "service": "Main.qml",
    "settings": "Settings.qml"
}
```

| Поле          | Обязательно | Что это                                                               |
|---------------|-------------|-----------------------------------------------------------------------|
| `id`          | да          | латиница в нижнем регистре, цифры, `-`; **совпадает с именем папки**   |
| `name`        | да          | название в настройках и в уведомлениях                                |
| `version`, `author`, `description` | нет | показываются в списке плагинов                      |
| `bar`         | нет         | QML-файл модуля в баре                                                |
| `service`     | нет         | QML-файл фоновой части                                                |
| `settings`    | нет         | QML-файл страницы настроек                                            |

Любую из трёх частей можно не указывать.

## Части плагина

### `bar` — модуль в баре

Корневой элемент — видимый `Item`, например `BarText` (текст или иконка с hover-эффектом и кликами)
или `Row`. Модуль встаёт справа в баре, перед треем.

```qml
import QtQuick
import qs.services
import qs.modules

BarText {
    property var plugin      // шелл передаст сюда API плагина
    property var screen      // и экран бара (если свойство объявлено)

    text: "󰀄 hi"
    onClicked: mouse => plugin.notify("My plugin", "clicked!")
}
```

### `service` — фоновая часть

Работает всё время, пока плагин включён. Корень — `Scope` (или любой `QtObject`/`Item`).
Здесь удобно держать таймеры, процессы, IPC-команды и свои окна (`PanelWindow`, `FloatingWindow`).

```qml
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    property var plugin

    IpcHandler {
        target: "my-plugin"                       // qs ipc call my-plugin ping
        function ping(): void { plugin.notify("My plugin", "pong"); }
    }

    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: plugin.set("lastTick", Date.now())
    }
}
```

### `settings` — страница настроек

Показывается в Настройки → Plugins → **Settings** у включённого плагина.
Корень — `ColumnLayout`. Бери готовые элементы Настроек, и страница будет выглядеть как родная:

```qml
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.settings

ColumnLayout {
    property var plugin
    spacing: 3

    SCard {
        title: "Show seconds"
        desc: "Описание под названием"
        SSwitch {
            checked: plugin ? plugin.get("seconds", false) : false
            onToggled: v => plugin.set("seconds", v)
        }
    }
}
```

## API плагина (`plugin`)

Объявляй в корне любой части `property var plugin`, и шелл заполнит его после загрузки.
До этого момента свойство пустое, поэтому в привязках проверяй `plugin ? … : …`.

| Функция / поле                 | Что делает                                                        |
|--------------------------------|-------------------------------------------------------------------|
| `plugin.get(key, default)`     | прочитать сохранённое значение (переживает перезапуск)            |
| `plugin.set(key, value)`       | сохранить значение (любое, что сериализуется в JSON)              |
| `plugin.notify(title, body)`   | показать уведомление                                              |
| `plugin.run(["cmd", "arg"])`   | запустить команду (массив аргументов, без shell)                  |
| `plugin.openSettings()`        | открыть Настройки → Plugins                                       |
| `plugin.id`, `plugin.name`, `plugin.version`, `plugin.dir` | данные из plugin.json и путь к папке   |

`get()` можно использовать в привязках: при `set()` из любой части плагина
(например, со страницы настроек) модуль в баре обновится сам.

Данные всех плагинов лежат в `~/.local/state/quickshell/by-shell/*/plugins.json`.

## Что ещё доступно из шелла

`import qs.services` открывает все сервисы шелла:

- `Theme` — цвета (`Theme.fg`, `Theme.accent`, `Theme.surface`, …), шрифт, размеры;
- `Settings` — настройки шелла;
- `Niri` — воркспейсы, окна, раскладка, `Niri.action([...])`;
- `Notifs`, `Weather`, `SysStats`, `Net`, `Recorder`, `Wallpapers`, `Power`, `NightLight`, `Notes`, `Ui` — всё, что видно в меню.

`import qs.modules` — готовые элементы бара и меню: `BarText`, `MenuHeader`, `Slider`, `StatRing`, `DashTile`…

`import qs.settings` — элементы Настроек: `SCard`, `SSwitch`, `SChoice`, `SDropdown`, `SSlider`, `SButton`, `SSection`.

Также доступны все модули Quickshell: `Quickshell.Io` (Process, FileView, IpcHandler),
`Quickshell.Services.Mpris`, `Quickshell.Services.Pipewire` и другие.

## Отладка

- **Ошибки в `plugin.json`** (битый JSON, неправильный `id`) видны прямо в списке плагинов красным.
- **Ошибки QML** пишутся в лог шелла: Настройки → Plugins → **Shell log** или `qs log -f` в терминале.
- **После правки кода** нажми **Restart shell**. После добавления новой папки хватит **Rescan**
  (или `qs ipc call plugins reload`).
- **Если плагин ломает бар,** выключи его в Настройках или удали его папку и перезапусти шелл.

## Советы

- Не блокируй интерфейс долгими операциями: для команд используй `Process` из `Quickshell.Io`.
- Храни настройки через `plugin.set/get`, а не в своих файлах: так они переживут перезапуски.
- Цвета бери из `Theme`, тогда плагин будет меняться вместе с темой (светлая, тёмная, «под обои»).
