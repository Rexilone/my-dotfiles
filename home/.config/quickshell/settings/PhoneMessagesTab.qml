import QtQuick
import QtQuick.Layouts
import qs.services

// Телефон → Сообщения: слева разговоры, справа переписка и поле ответа
RowLayout {
    id: tab

    property bool active: false
    property string query: ""

    readonly property var thread: Rexlink.sms.thread ?? ({})
    readonly property bool opened: thread.id !== undefined

    Layout.fillWidth: true
    spacing: 12

    onActiveChanged: if (active && Rexlink.online) Rexlink.smsRefresh()
    Connections {
        target: Rexlink
        function onOnlineChanged() { if (tab.active && Rexlink.online) Rexlink.smsRefresh(); }
        function onCurrentChanged() { if (tab.active && Rexlink.online) Rexlink.smsRefresh(); }
    }

    component Avatar: Rectangle {
        property string name: ""
        implicitWidth: 38
        implicitHeight: 38
        radius: 19
        color: Theme.surfaceHi2
        Text {
            anchors.centerIn: parent
            text: Rexlink.initials(parent.name)
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.bold: true
        }
    }

    // ── разговоры
    ColumnLayout {
        Layout.preferredWidth: 300
        Layout.maximumWidth: 300
        Layout.fillHeight: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            SField {
                icon: String.fromCodePoint(0xF0349)
                placeholder: "Search"
                onTextChanged: tab.query = text.toLowerCase()
            }
            SButton { icon: String.fromCodePoint(0xF0450); enabled: Rexlink.online; onClicked: Rexlink.smsRefresh() }
            SButton { icon: String.fromCodePoint(0xF0415); primary: true; enabled: Rexlink.online; onClicked: Rexlink.smsOpen("") }
        }

        ListView {
            id: threads
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: (Rexlink.sms.threads ?? []).filter(t => !tab.query || `${t.name} ${t.address} ${t.snippet}`.toLowerCase().includes(tab.query))

            delegate: Rectangle {
                id: th
                required property var modelData
                readonly property bool selected: String(tab.thread.id) === String(modelData.id)

                width: ListView.view.width
                height: 62
                radius: 10
                color: selected ? Theme.surfaceHi : thArea.containsMouse ? Theme.surface : "transparent"

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 12

                    Avatar { name: th.modelData.name || th.modelData.address }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: th.modelData.name || th.modelData.address
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: th.modelData.unread > 0
                            }
                            Text {
                                text: Rexlink.ago(th.modelData.date)
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: th.modelData.snippet ?? ""
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 3
                            }
                            Rectangle {
                                visible: th.modelData.unread > 0
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: Theme.accent
                            }
                        }
                    }
                }
                MouseArea {
                    id: thArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Rexlink.smsOpen(th.modelData.id)
                }
            }

            PhoneEmpty {
                anchors.centerIn: parent
                width: parent.width - 20
                visible: threads.count === 0
                icon: String.fromCodePoint(0xF0369)
                text: Rexlink.online ? "No messages" : "The device is not connected"
                hint: Rexlink.online ? "The app on the phone needs SMS access" : ""
            }
        }
    }

    // ── переписка
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: Theme.surface

        PhoneEmpty {
            anchors.centerIn: parent
            visible: !tab.opened
            icon: String.fromCodePoint(0xF0369)
            text: "Pick a conversation"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            visible: tab.opened

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                visible: !tab.thread.new

                Avatar { name: tab.thread.name || tab.thread.address || "" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: tab.thread.name || tab.thread.address || ""
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: tab.thread.name ? (tab.thread.address ?? "") : ""
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
                SButton {
                    visible: !!tab.thread.address
                    icon: String.fromCodePoint(0xF03F2)
                    onClicked: Rexlink.dial(tab.thread.address)
                }
            }
            SField {
                id: to
                visible: !!tab.thread.new
                icon: String.fromCodePoint(0xF03F2)
                placeholder: "Phone number"
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surfaceHi2 }

            ListView {
                id: msgs
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                verticalLayoutDirection: ListView.BottomToTop
                boundsBehavior: Flickable.StopAtBounds
                model: (Rexlink.sms.messages ?? []).slice().reverse()

                delegate: Item {
                    id: msg
                    required property var modelData
                    readonly property bool mine: modelData.type !== 1

                    width: ListView.view.width
                    height: bubble.height + 4

                    Rectangle {
                        id: bubble
                        anchors.right: msg.mine ? parent.right : undefined
                        anchors.left: msg.mine ? undefined : parent.left
                        width: Math.min(msg.width * 0.72, Math.max(bodyText.implicitWidth, timeText.implicitWidth) + 28)
                        height: bodyText.implicitHeight + timeText.implicitHeight + 22
                        radius: 12
                        color: msg.mine ? Theme.accent : Theme.surfaceHi2

                        Text {
                            id: bodyText
                            x: 14
                            y: 10
                            width: Math.min(implicitWidth, msg.width * 0.72 - 28)
                            text: msg.modelData.body ?? ""
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            color: msg.mine ? Theme.bg : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            id: timeText
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.top: bodyText.bottom
                            anchors.topMargin: 3
                            text: Rexlink.ago(msg.modelData.date) + (msg.modelData.type === 5 ? `   ·   ${I18n.tr("error")}` : msg.modelData.type === 4 || msg.modelData.type === 6 ? `   ·   ${I18n.tr("sending…")}` : "")
                            color: msg.mine ? Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.7) : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 4
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SField {
                    id: composer
                    multiline: true
                    placeholder: "SMS… (Enter — send, Shift+Enter — new line)"
                    function send() {
                        const addr = tab.thread.new ? to.text.trim() : tab.thread.address;
                        if (!text.trim() || !addr) return;
                        Rexlink.smsSend(addr, text);
                        text = "";
                    }
                    onAccepted: send()
                }
                SButton {
                    Layout.alignment: Qt.AlignBottom
                    icon: String.fromCodePoint(0xF048A)
                    primary: true
                    implicitHeight: 38
                    onClicked: composer.send()
                }
            }
        }
    }
}
