import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.services

// карточка входа: аватар, имя, пароль — в стиле меню шелла
Item {
    id: root

    implicitWidth: card.width
    implicitHeight: card.height
    width: implicitWidth
    height: implicitHeight

    property bool shown: false
    Component.onCompleted: appear.start()
    Timer {
        id: appear
        interval: 150
        onTriggered: root.shown = true
    }

    // неверный пароль — карточка вздрагивает
    Connections {
        target: G
        function onShakesChanged() {
            shake.restart();
            pass.selectAll();
        }
        function onUserIndexChanged() { pass.text = ""; }
    }
    SequentialAnimation {
        id: shake
        loops: 1
        NumberAnimation { target: shift; property: "x"; to: -10; duration: 50 }
        NumberAnimation { target: shift; property: "x"; to: 9; duration: 70 }
        NumberAnimation { target: shift; property: "x"; to: -6; duration: 60 }
        NumberAnimation { target: shift; property: "x"; to: 3; duration: 50 }
        NumberAnimation { target: shift; property: "x"; to: 0; duration: 40 }
    }

    Rectangle {
        id: card
        width: 380 * G.scale
        height: col.implicitHeight + 56
        radius: G.radius + 6
        color: G.panel
        border.width: 1
        border.color: G.faint

        transform: Translate { id: shift }
        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: col
            anchors.top: parent.top
            anchors.topMargin: 32
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 56
            spacing: 0

            // ── аватар: картинка пользователя или первая буква имени
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 104 * G.scale
                implicitHeight: implicitWidth

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(G.accent.r, G.accent.g, G.accent.b, G.busy ? 0.9 : 0.35)
                    Behavior on border.color { ColorAnimation { duration: G.animSlow } }
                }
                Rectangle {
                    id: avatarBg
                    anchors.fill: parent
                    anchors.margins: 6
                    radius: width / 2
                    color: G.surfaceHi2

                    Text {
                        anchors.centerIn: parent
                        visible: avatarImg.status !== Image.Ready
                        text: (G.user?.display ?? "?").charAt(0).toUpperCase()
                        color: G.fg
                        font.family: G.font
                        font.pixelSize: parent.height * 0.42
                        font.bold: true
                    }
                }
                Image {
                    id: avatarImg
                    anchors.fill: avatarBg
                    source: G.user && G.user.name === G.t.user ? G.avatar : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    layer.enabled: true
                }
                Rectangle {
                    id: avatarMask
                    anchors.fill: avatarBg
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: avatarBg
                    visible: avatarImg.status === Image.Ready
                    source: avatarImg
                    maskEnabled: true
                    maskSource: avatarMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
            }

            // ── имя (несколько пользователей — стрелки)
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 18
                spacing: 14

                Arrow {
                    visible: G.users.length > 1
                    glyph: 0xF0141
                    onClicked: G.nextUser(-1)
                }
                Text {
                    text: G.user?.display ?? G.tr("No users", "Нет пользователей")
                    color: G.fg
                    font.family: G.font
                    font.pixelSize: G.fontSize + 7
                    font.bold: true
                }
                Arrow {
                    visible: G.users.length > 1
                    glyph: 0xF0142
                    onClicked: G.nextUser(1)
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                visible: !!G.user && G.user.display !== G.user.name
                text: G.user?.name ?? ""
                color: G.dim
                font.family: G.font
                font.pixelSize: G.fontSize - 1
            }

            // ── пароль
            Rectangle {
                id: field
                Layout.fillWidth: true
                Layout.topMargin: 24
                implicitHeight: 46 * G.scale
                radius: G.radius
                color: G.surfaceHi
                border.width: 1
                border.color: G.error ? G.urgent : pass.activeFocus ? Qt.rgba(G.accent.r, G.accent.g, G.accent.b, 0.55) : G.surfaceHi2
                Behavior on border.color { ColorAnimation { duration: G.animFast } }

                Text {
                    id: lockIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(G.asking ? 0xF0306 : 0xF033E)
                    color: pass.text ? G.fg : G.dim
                    font.family: G.font
                    font.pixelSize: G.iconSize + 2
                }

                TextInput {
                    id: pass
                    anchors.left: lockIcon.right
                    anchors.leftMargin: 12
                    anchors.right: go.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    enabled: !G.busy && !G.leaving
                    echoMode: G.asking ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: G.fg
                    selectionColor: Qt.rgba(G.accent.r, G.accent.g, G.accent.b, 0.35)
                    selectedTextColor: G.fg
                    font.family: G.font
                    font.pixelSize: G.fontSize + (echoMode === TextInput.Password && text ? 3 : 1)
                    font.letterSpacing: echoMode === TextInput.Password ? 2 : 0
                    clip: true
                    Component.onCompleted: forceActiveFocus()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !pass.text
                        text: G.asking ? G.tr("Answer", "Ответ") : G.tr("Password", "Пароль")
                        color: G.dim
                        font.family: G.font
                        font.pixelSize: G.fontSize + 1
                    }

                    onTextChanged: if (text && G.error && !G.asking) G.error = ""
                    Keys.onPressed: event => {
                        const k = event.key;
                        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                            G.login(pass.text);
                        } else if (k === Qt.Key_Up) {
                            G.nextUser(-1);
                        } else if (k === Qt.Key_Down) {
                            G.nextUser(1);
                        } else if (k === Qt.Key_Escape) {
                            pass.text = "";
                            G.error = "";
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }

                // кнопка «войти» / крутилка, пока проверяется пароль
                Rectangle {
                    id: go
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height - 12
                    height: width
                    radius: G.radius - 3
                    color: G.busy || G.leaving ? "transparent" : pass.text ? (goArea.containsMouse ? Qt.lighter(G.accent, 1.1) : G.accent) : G.surfaceHi2
                    Behavior on color { ColorAnimation { duration: G.animFast } }

                    Text {
                        id: goIcon
                        anchors.centerIn: parent
                        text: String.fromCodePoint(G.busy || G.leaving ? 0xF0772 : 0xF0054)
                        color: G.busy || G.leaving ? G.accent : pass.text ? G.bg : G.dim
                        font.family: G.font
                        font.pixelSize: G.iconSize + 2

                        RotationAnimation on rotation {
                            running: G.busy || G.leaving
                            from: 0
                            to: 360
                            duration: 1100
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) goIcon.rotation = 0
                        }
                    }
                    MouseArea {
                        id: goArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            G.login(pass.text);
                            pass.forceActiveFocus();
                        }
                    }
                }
            }

            // ── ошибка / вопрос PAM
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: G.error
                color: G.asking ? G.muted : G.urgent
                font.family: G.font
                font.pixelSize: G.fontSize - 1
                // место под строку есть всегда — карточка не прыгает
                Layout.minimumHeight: G.fontSize + 4
                opacity: G.error ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: G.animSlow } }
            }
        }
    }

    // после ответа на вопрос PAM поле очищается
    Connections {
        target: G
        function onAskingChanged() { if (G.asking) pass.text = ""; }
        function onBusyChanged() { if (!G.busy) pass.forceActiveFocus(); }
    }

    component Arrow: Text {
        id: arrow
        property int glyph: 0
        signal clicked
        text: String.fromCodePoint(glyph)
        color: arrowArea.containsMouse ? G.fg : G.dim
        font.family: G.font
        font.pixelSize: G.iconSize + 4
        Behavior on color { ColorAnimation { duration: G.animFast } }
        MouseArea {
            id: arrowArea
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: arrow.clicked()
        }
    }
}
