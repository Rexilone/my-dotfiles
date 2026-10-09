import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.settings

// страница приложения: значок, кнопки, скриншоты, описание, сведения о пакете
Flickable {
    id: page

    property string pkg: ""
    property bool aur: false
    signal back

    readonly property var app: Store.byPkg[pkg] ?? null
    readonly property var inf: Store.infoCache[pkg] ?? null
    readonly property bool isAur: aur || inf?.repo === "aur"
    readonly property bool installed: Store.isInstalled(pkg)
    readonly property string busy: Store.busyWith(pkg)

    onPkgChanged: {
        contentY = 0;
        if (pkg) Store.loadInfo(pkg);
    }
    Component.onCompleted: if (pkg) Store.loadInfo(pkg)

    contentHeight: col.implicitHeight + 56
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    component Chip: Rectangle {
        property string label
        property string value
        property color tint: Theme.fg
        visible: value !== ""
        implicitWidth: chipCol.implicitWidth + 28
        implicitHeight: 54
        radius: 10
        color: Theme.surface
        Column {
            id: chipCol
            anchors.centerIn: parent
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.parent.value
                color: parent.parent.tint
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr(parent.parent.label)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 4
            }
        }
    }

    ColumnLayout {
        id: col
        x: 36
        y: 24
        width: page.width - 72
        spacing: 14

        // назад
        Text {
            text: `‹  ${I18n.tr("Go back")}`
            color: backArea.containsMouse ? Theme.fg : Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            MouseArea {
                id: backArea
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.back()
            }
        }

        // ── шапка
        RowLayout {
            Layout.fillWidth: true
            spacing: 22

            StoreIcon {
                Layout.alignment: Qt.AlignTop
                pkg: page.pkg
                size: 96
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: page.app?.name || page.pkg
                    wrapMode: Text.Wrap
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 12
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: [page.app?.developer, page.pkg, page.isAur ? "AUR" : (page.inf?.repo || page.app?.repo || "")].filter(x => x).join("   ·   ")
                    elide: Text.ElideRight
                    color: page.isAur ? Theme.warn : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: text !== ""
                    text: page.app?.summary || page.inf?.desc || ""
                    wrapMode: Text.Wrap
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                RowLayout {
                    Layout.topMargin: 12
                    spacing: 8

                    ActionButton {
                        pkg: page.pkg
                        aur: page.isAur
                        implicitHeight: 38
                        Layout.minimumWidth: 140
                    }
                    SButton {
                        visible: page.installed && Store.hasUpdate(page.pkg) && !page.busy
                        text: "Update"
                        icon: String.fromCodePoint(0xF06B0)
                        implicitHeight: 38
                        onClicked: Store.upgradeAll()
                    }
                    SButton {
                        visible: page.installed && !page.busy
                        text: "Remove"
                        icon: Icons.trash
                        danger: true
                        implicitHeight: 38
                        onClicked: Store.remove(page.pkg)
                    }
                    SButton {
                        visible: !!(page.app?.homepage || page.inf?.url)
                        text: "Website"
                        icon: String.fromCodePoint(0xF059F)
                        implicitHeight: 38
                        onClicked: Qt.openUrlExternally(page.app?.homepage || page.inf?.url)
                    }
                }

                // ход установки этого пакета
                Text {
                    Layout.fillWidth: true
                    visible: !!page.busy && !!Store.current?.pkgs?.includes(page.pkg)
                    text: Store.current?.line ?? ""
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }

        // ── коротко
        Flow {
            Layout.fillWidth: true
            spacing: 8

            Chip { label: "Version"; value: page.installed && page.inf?.localVersion ? page.inf.localVersion : (page.inf?.version ?? "") }
            Chip { label: "Download"; value: page.inf?.download ?? "" }
            Chip { label: "Size"; value: page.inf?.installedSize || page.inf?.size || "" }
            Chip { label: "License"; value: (page.app?.license || page.inf?.license || "").split(/\s+(AND|OR)\s+|\s{2,}/)[0] ?? "" }
            Chip { label: "Votes"; value: page.inf?.votes !== undefined ? String(page.inf.votes) : "" }
            Chip { label: "Popularity"; value: page.inf?.popularity !== undefined ? Number(page.inf.popularity).toFixed(2) : "" }
            Chip { label: "Out of date"; value: page.inf?.outOfDate ? "!" : ""; tint: Theme.warn }
        }

        // ── AUR: собирается из чужого PKGBUILD
        Rectangle {
            visible: page.isAur
            Layout.fillWidth: true
            implicitHeight: aurRow.implicitHeight + 28
            radius: 10
            color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.5)

            RowLayout {
                id: aurRow
                x: 16
                y: 14
                width: parent.width - 32
                spacing: 14

                Text {
                    text: String.fromCodePoint(0xF0026)
                    color: Theme.warn
                    font.family: Theme.font
                    font.pixelSize: Theme.iconSize + 4
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: I18n.tr("AUR packages are made by users and built on your computer. Look at the PKGBUILD before installing.")
                        + (page.inf?.maintainer ? `   ${I18n.tr("Maintainer")}: ${page.inf.maintainer}` : "")
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                SButton {
                    visible: !!page.inf?.pkgbuild
                    text: "PKGBUILD"
                    onClicked: Qt.openUrlExternally(page.inf.pkgbuild)
                }
                SButton {
                    visible: !!page.inf?.aurPage
                    text: "AUR"
                    onClicked: Qt.openUrlExternally(page.inf.aurPage)
                }
            }
        }

        // ── скриншоты
        ListView {
            visible: (page.app?.screenshots ?? []).length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 250
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: page.app?.screenshots ?? []

            delegate: Rectangle {
                id: shot
                required property string modelData
                height: 250
                width: img.status === Image.Ready ? Math.min(560, img.implicitWidth * height / Math.max(1, img.implicitHeight)) : 380
                radius: 10
                color: Theme.surface
                clip: true

                Image {
                    id: img
                    anchors.fill: parent
                    source: shot.modelData
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: img.status !== Image.Ready
                    text: img.status === Image.Error ? I18n.tr("No connection") : I18n.tr("Loading…")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(shot.modelData)
                }
            }
        }

        // ── описание
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: page.app?.description || (page.app ? "" : page.inf?.desc ?? "")
            wrapMode: Text.Wrap
            lineHeight: 1.2
            textFormat: Text.PlainText
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }

        // ── сведения
        SSection { text: I18n.tr("Package") }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 24
            rowSpacing: 8

            Repeater {
                model: [
                    ["Package", page.pkg],
                    ["Repository", page.isAur ? "AUR" : (page.inf?.repo ?? "")],
                    ["Available version", page.inf?.version ?? ""],
                    ["Installed version", page.inf?.localVersion ?? ""],
                    ["Installed", page.inf?.installDate ?? ""],
                    ["Built", page.inf?.date ?? ""],
                    ["Packager", page.inf?.packager ?? ""],
                    ["Depends on", page.inf?.depends && page.inf.depends !== "None" ? page.inf.depends.split(/\s+/).filter(x => x).join(", ") : ""],
                ].filter(r => r[1])

                delegate: RowLayout {
                    required property var modelData
                    Layout.columnSpan: modelData[0] === "Depends on" ? 2 : 1
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        Layout.preferredWidth: 150
                        Layout.alignment: Qt.AlignTop
                        text: I18n.tr(parent.modelData[0])
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.modelData[1]
                        wrapMode: Text.Wrap
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }
        }

        Text {
            visible: !page.inf
            text: I18n.tr("Loading…")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }
}
