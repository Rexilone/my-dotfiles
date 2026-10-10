import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Обновления: окружение (git-репозиторий dots) и пакеты системы (pacman)
Page {
    id: page

    title: "Updates"
    subtitle: "Shell updates from GitHub and system packages"

    Component.onCompleted: {
        if (!Dotfiles.checking && Date.now() - Dotfiles.lastCheck > 60000) Dotfiles.check();
        if (!Updates.checking) Updates.refresh();
    }

    // ── главная карточка: версия и состояние
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hero.implicitHeight + 40
        radius: 12
        color: Theme.surface

        RowLayout {
            id: hero
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 18

            Rectangle {
                implicitWidth: 64
                implicitHeight: 64
                radius: 18
                color: Dotfiles.available ? Theme.accent : Theme.surfaceHi

                Text {
                    id: statusIcon
                    anchors.centerIn: parent
                    text: String.fromCodePoint(Dotfiles.checking || Dotfiles.updating ? 0xF0450 : Dotfiles.available ? 0xF01DA : 0xF012C)
                    color: Dotfiles.available ? Theme.bg : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 28

                    RotationAnimation on rotation {
                        running: Dotfiles.checking || Dotfiles.updating
                        from: 0
                        to: 360
                        duration: 1200
                        loops: Animation.Infinite
                        // после проверки — ровно (иначе стрелка/галочка застывает под углом)
                        onRunningChanged: if (!running) statusIcon.rotation = 0
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: Dotfiles.updating ? I18n.tr("Updating…")
                        : Dotfiles.checking ? I18n.tr("Checking for updates…")
                        : !Dotfiles.isRepo ? I18n.tr("Not installed from git")
                        : Dotfiles.available ? (I18n.ru ? `Доступно обновление: ${Dotfiles.behind} ${I18n.plural(Dotfiles.behind, "", "", "изменение", "изменения", "изменений")}`
                                                       : `Update available: ${Dotfiles.behind} new ${Dotfiles.behind === 1 ? "change" : "changes"}`)
                        : Dotfiles.error ? I18n.tr("Couldn't check for updates")
                        : I18n.tr("You're up to date")
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 4
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: `Rexilone Shell ${Dotfiles.version}${Dotfiles.commit ? "   ·   " + Dotfiles.commit + " · " + Dotfiles.commitDate : ""}`
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    Layout.fillWidth: true
                    visible: Dotfiles.lastCheck > 0
                    text: `${I18n.tr("Last checked")}: ${Qt.locale(I18n.locale).toString(new Date(Dotfiles.lastCheck), "d MMM, HH:mm")}`
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            SButton {
                text: "Check"
                icon: String.fromCodePoint(0xF0450)
                enabled: !Dotfiles.checking && !Dotfiles.updating
                onClicked: Dotfiles.check()
            }
            SButton {
                visible: Dotfiles.available
                text: "Update"
                primary: true
                enabled: !Dotfiles.updating && Dotfiles.dirty === 0
                onClicked: Dotfiles.update()
            }
        }
    }

    // ошибки и предупреждения
    SCard {
        visible: Dotfiles.error !== ""
        icon: String.fromCodePoint(0xF0026)
        title: Dotfiles.error.indexOf("couldn't find remote ref") >= 0 ? "The repository is empty for now" : "Couldn't reach the repository"
        desc: Dotfiles.error
    }
    SCard {
        visible: Dotfiles.dirty > 0 && Dotfiles.available
        icon: String.fromCodePoint(0xF0026)
        title: "You have local changes"
        desc: I18n.ru ? `Изменено файлов в ${Dotfiles.dir}: ${Dotfiles.dirty}. Закоммитьте или уберите их (git stash) — потом обновление.`
                      : `${Dotfiles.dirty} changed files in ${Dotfiles.dir}. Commit or stash them (git stash), then update.`
    }
    SCard {
        visible: Dotfiles.changedPackages.length > 0 || Dotfiles.missingPackages.length > 0
        icon: String.fromCodePoint(0xF03D7)
        title: "New packages are needed"
        desc: Dotfiles.missingPackages.length > 0
            ? (I18n.ru ? `Не установлено: ${Dotfiles.missingPackages.join(", ")}` : `Not installed: ${Dotfiles.missingPackages.join(", ")}`)
            : (I18n.ru ? `Изменились списки: ${Dotfiles.changedPackages.join(", ")}` : `Changed lists: ${Dotfiles.changedPackages.join(", ")}`)

        SButton {
            text: "Install packages"
            onClicked: Dotfiles.installPackages()
        }
    }
    SCard {
        visible: !Dotfiles.isRepo && !Dotfiles.checking
        icon: String.fromCodePoint(0xF02A2)
        title: "Install from git to get updates"
        desc: `git clone ${Dotfiles.repoUrl} ~/my-dotfiles && ~/my-dotfiles/install.sh`
    }

    // ── что нового
    SSection {
        visible: Dotfiles.incoming.length > 0
        text: I18n.tr("What's new")
    }

    Rectangle {
        Layout.fillWidth: true
        visible: Dotfiles.incoming.length > 0
        implicitHeight: changes.implicitHeight + 16
        radius: 10
        color: Theme.surface

        ColumnLayout {
            id: changes
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 0

            Repeater {
                model: Dotfiles.incoming

                RowLayout {
                    id: ch
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    spacing: 14

                    // точка на «линии времени»
                    Item {
                        Layout.preferredWidth: 20
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: ch.index === 0 ? parent.height / 2 : 0
                            width: 2
                            height: ch.index === 0 || ch.index === Dotfiles.incoming.length - 1 ? parent.height / 2 : parent.height
                            visible: Dotfiles.incoming.length > 1
                            color: Theme.surfaceHi2
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10
                            height: 10
                            radius: 5
                            color: ch.index === 0 ? Theme.accent : Theme.line
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: ch.modelData.subject
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            Layout.fillWidth: true
                            text: `${ch.modelData.hash}   ·   ${ch.modelData.author}   ·   ${ch.modelData.when}`
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
            }
        }
    }

    // вывод последнего обновления
    Rectangle {
        Layout.fillWidth: true
        visible: Dotfiles.log !== "" && Dotfiles.error !== ""
        implicitHeight: logText.implicitHeight + 24
        radius: 10
        color: Theme.surface

        Text {
            id: logText
            x: 14
            y: 12
            width: parent.width - 28
            text: Dotfiles.log
            wrapMode: Text.Wrap
            color: Theme.muted
            font.family: Settings.monoFont || Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
    }

    // ── настройки обновлений
    SSection { text: I18n.tr("Update settings") }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3

        SCard {
            icon: String.fromCodePoint(0xF0450)
            title: "Check automatically"
            desc: "A minute after login and every 6 hours; you get a notification when there's something new"

            SSwitch {
                checked: Settings.updateAuto ?? true
                onToggled: v => Settings.updateAuto = v
            }
        }

        // адрес репозитория
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 64
            radius: 10
            color: Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 16
                spacing: 16

                Text {
                    Layout.preferredWidth: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: String.fromCodePoint(0xF02A4)  // github
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 3
                }
                ColumnLayout {
                    Layout.preferredWidth: 180
                    spacing: 2
                    Text {
                        text: I18n.tr("Repository")
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        text: `${I18n.tr("Branch")}: ${Dotfiles.branch}`
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 9
                    color: Theme.surfaceHi
                    border.width: 1
                    border.color: repoInput.activeFocus ? Theme.line : Theme.surfaceHi2

                    TextInput {
                        id: repoInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        text: Dotfiles.repoUrl
                        color: Theme.fg
                        selectionColor: Theme.line
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        clip: true
                        // сохраняем по Enter или при уходе с поля; пусто — адрес по умолчанию
                        function save() {
                            const v = text.trim();
                            Settings.updateRepo = v === Dotfiles.defaultRepo ? "" : v;
                        }
                        onAccepted: { save(); focus = false; }
                        onActiveFocusChanged: if (!activeFocus) save()
                    }
                }
                SButton {
                    text: "Open"
                    onClicked: Qt.openUrlExternally(Dotfiles.repoUrl)
                }
            }
        }
    }

    // ── пакеты системы
    SSection { text: I18n.tr("System packages") }

    SCard {
        icon: String.fromCodePoint(0xF06B0)
        title: !Updates.installed ? "Update checker is not installed"
             : Updates.checking ? "Checking packages…"
             : Updates.count > 0 ? (I18n.ru ? `Доступно обновлений: ${Updates.count}` : `${Updates.count} package updates`)
             : "Packages are up to date"
        desc: !Updates.installed ? "pacman-contrib (checkupdates) counts updates without touching the system"
            : (Updates.list ?? []).slice(0, 5).map(u => String(u).split(" ")[0]).join(", ")

        SButton {
            visible: !Updates.installed
            text: "Install"
            onClicked: Updates.install()
        }
        SButton {
            visible: Updates.installed && Updates.count > 0
            text: "Update"
            primary: true
            onClicked: Updates.upgrade()
        }
    }
}
