"""Язык уведомлений и подсказок службы: как в шелле (Настройки → Время и язык).

Шелл передаёт его настройкой "lang" ("ru" | "en"). Строки в коде — русские шаблоны,
здесь — их английские версии; tr("{} подключён", имя).
"""
LANG = "ru"

EN = {
    "{} подключён": "{} connected",
    "Сопряжение: {}": "Pairing: {}",
    "Код: {}. Сверьте его с устройством.": "Code: {}. Check that it matches the device.",
    "Принять": "Accept",
    "Отклонить": "Decline",
    "Открыть": "Open",
    "Телефон": "Phone",
    "Неизвестный номер": "Unknown number",
    "Входящий звонок": "Incoming call",
    "Сбросить": "Decline",
    "Без звука": "Silence",
    "Пропущенный звонок": "Missed call",
    "Ответить": "Reply",
    "SMS отправлено": "SMS sent",
    "SMS не отправлено: {}": "SMS not sent: {}",
    "Файл получен": "File received",
    "Папка": "Folder",
    "Устройство не подключено": "The device is not connected",
    "Нет устройства v4l2loopback — показываю только превью": "No v4l2loopback device — preview only",
    "{}: приложение обновлено": "{}: app updated",
    "{}: обновить не вышло — {}": "{}: update failed — {}",
    "Без ADB — Android один раз спросит разрешение на устройстве": "Without ADB, Android asks for permission on the device once",
    "Экран: {}": "Screen: {}",
    "Нужны пакеты android-tools и scrcpy": "Needs the android-tools and scrcpy packages",
    "Включите на устройстве «Отладку по Wi-Fi»": "Turn on “Wireless debugging” on the device",
    "ADB: сопряжение выполнено": "ADB: paired",
    "ADB: {}": "ADB: {}",
    "ADB: не подключиться — нужно сопряжение по коду": "ADB: can't connect — pair with a code first",
    "{}: обновление через adb…": "{}: updating over adb…",
    "{}: обновление отправлено — подтвердите на устройстве, если спросит": "{}: update sent — confirm on the device if asked",
    "{}: старая версия обновляется только по adb (USB или «Отладка по Wi-Fi»)": "{}: this old version updates only over adb (USB or “Wireless debugging”)",
    "{}: обновление не установлено — {}": "{}: update not installed — {}",
}


def set_lang(lang):
    global LANG
    LANG = "en" if lang == "en" else "ru"


def tr(text, *args):
    if LANG == "en":
        text = EN.get(text, text)
    return text.format(*args) if args else text
