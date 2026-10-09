import QtQuick
import qs.services

// цитата дня (меняется раз в день, клик — следующая)
Column {
    id: root

    readonly property var quotes: [
        ["Simplicity is the ultimate sophistication.", "Leonardo da Vinci"],
        ["Talk is cheap. Show me the code.", "Linus Torvalds"],
        ["Make it work, make it right, make it fast.", "Kent Beck"],
        ["The best way to predict the future is to invent it.", "Alan Kay"],
        ["Less is more.", "Ludwig Mies van der Rohe"],
        ["Первая заповедь программиста: работает — не трогай.", "народная мудрость"],
        ["Тише едешь — дальше будешь.", "пословица"],
        ["Stay hungry, stay foolish.", "Steve Jobs"],
        ["Programs must be written for people to read.", "Harold Abelson"],
        ["Мы — то, что мы делаем постоянно.", "Аристотель"],
        ["Done is better than perfect.", "Sheryl Sandberg"],
        ["Не ошибается тот, кто ничего не делает.", "Теодор Рузвельт"],
        ["First, solve the problem. Then, write the code.", "John Johnson"],
        ["Kaizen: a little better every day.", "Japanese proverb"],
    ]
    property int index: Math.floor(Date.now() / 86400000) % quotes.length

    width: 360
    spacing: 8

    Text {
        width: parent.width
        text: `“${root.quotes[root.index][0]}”`
        wrapMode: Text.Wrap
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize + 5
        font.italic: true
    }
    Text {
        text: `— ${root.quotes[root.index][1]}`
        color: Theme.accent
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }

    TapHandler {
        onTapped: root.index = (root.index + 1) % root.quotes.length
    }
}
