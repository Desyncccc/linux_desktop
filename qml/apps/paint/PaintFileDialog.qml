import QtQuick
import Qt.labs.folderlistmodel
import Vitrum
import Vitrum.Core

// Save As / Open dialog in the style of the 2009 common file dialog:
// address bar, favourites pane, details list, file name and type.
PaintDialog {
    id: fd
    property string mode: "save"            // "save" | "open"
    property string folder: Files.pictures
    // [{ label, exts: ["png"] }]; for "open" the first entry is usually "all pictures"
    property var types: []
    property int typeIndex: 0
    property string fileName: ""
    property string selectedPath: ""
    property string confirmPath: ""
    property string search: ""
    signal accepted(string path, int typeIndex)

    title: mode === "save" ? "Save As" : "Open"
    clientWidth: 640
    clientHeight: 420

    function show(m, dir, name, tIndex) {
        mode = m
        folder = dir && Files.isDir(dir) ? dir : Files.pictures
        if (!Files.isDir(folder))
            folder = Files.home
        typeIndex = tIndex || 0
        fileName = name || ""
        nameField.text = fileName
        selectedPath = ""
        confirmPath = ""
        search = ""
        searchField.text = ""
        open = true
        nameField.input.forceActiveFocus()
        nameField.input.selectAll()
    }
    function close() { open = false; confirmPath = "" }
    onRejected: close()

    function extFor(i) { const t = types[i]; return t && t.exts.length ? t.exts[0] : "" }
    function navigate(dir) {
        if (!Files.isDir(dir))
            return
        folder = dir
        selectedPath = ""
    }
    function commit() {
        let n = nameField.text.trim()
        if (n.length === 0)
            return
        let p = n.indexOf("/") === 0 ? n : (n.indexOf("~/") === 0 ? Files.home + n.substring(1) : folder + "/" + n)
        if (Files.isDir(p)) {
            navigate(p)
            nameField.text = ""
            return
        }
        if (mode === "save") {
            const t = types[typeIndex]
            const dot = Files.fileName(p).lastIndexOf(".")
            const ext = dot > 0 ? Files.fileName(p).substring(dot + 1).toLowerCase() : ""
            if (t && t.exts.indexOf(ext) < 0)
                p += "." + t.exts[0]
            if (Files.exists(p) && confirmPath !== p) {
                confirmPath = p
                return
            }
            close()
            accepted(p, typeIndex)
        } else {
            if (!Files.exists(p))
                return
            close()
            accepted(p, typeIndex)
        }
    }

    FolderListModel {
        id: model
        folder: Files.toUrl(fd.folder)
        showDirsFirst: true
        showHidden: false
        sortField: FolderListModel.Name
        nameFilters: {
            const t = fd.types[fd.typeIndex]
            const f = t ? t.exts.map(e => e === "*" ? "*" : "*." + e) : ["*"]
            if (fd.search.length === 0)
                return f
            return ["*" + fd.search + "*"]
        }
        caseSensitive: false
    }

    // ---- address bar
    Rectangle {
        id: navBar
        width: parent.width; height: 34
        gradient: Gradient {
            GradientStop { position: 0; color: "#f2f7fd" }
            GradientStop { position: 1; color: "#dce7f5" }
        }
        Row {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Rectangle {
                width: 25; height: 25; radius: 12.5
                anchors.verticalCenter: parent.verticalCenter
                border.color: "#2b5c97"
                gradient: Gradient {
                    GradientStop { position: 0; color: upMa.containsMouse ? "#bfe4ff" : "#9ccaf0" }
                    GradientStop { position: 0.5; color: upMa.containsMouse ? "#4ea3ef" : "#3d7fc8" }
                    GradientStop { position: 1; color: upMa.containsMouse ? "#7cc6ff" : "#2f68ad" }
                }
                Image { anchors.centerIn: parent; width: 13; height: 13; sourceSize: Qt.size(26, 26); source: Theme.icon("arrow-up") }
                MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; onClicked: if (fd.folder !== "/") fd.navigate(Files.parentDir(fd.folder)) }
            }
            TextField7 {
                id: addr
                width: navBar.width - 230
                anchors.verticalCenter: parent.verticalCenter
                text: fd.folder
                iconName: Theme.icon("refresh")
                onAccepted: fd.navigate(text)
            }
            TextField7 {
                id: searchField
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "Search " + Files.fileName(fd.folder)
                iconName: Theme.icon("search")
                onTextChanged: fd.search = text
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#b6c6da" }
    }
    // ---- command bar
    Rectangle {
        id: cmdBar
        y: navBar.height
        width: parent.width; height: 28
        gradient: Gradient {
            GradientStop { position: 0; color: "#f5f9fd" }
            GradientStop { position: 1; color: "#e3ebf6" }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#c6d3e3" }
        Row {
            x: 6; height: parent.height
            HoverItem {
                width: nf.implicitWidth + 16; height: 22
                anchors.verticalCenter: parent.verticalCenter
                VText { id: nf; anchors.centerIn: parent; text: "New folder"; color: "#1e395b" }
                onClicked: {
                    const p = Files.makeFolder(fd.folder)
                    if (p.length)
                        fd.selectedPath = p
                }
            }
        }
    }
    // ---- favourites
    Rectangle {
        id: navPane
        y: cmdBar.y + cmdBar.height
        width: 150
        height: parent.height - y - bottom.height
        color: "white"
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#d6e1ee" }
        Column {
            x: 4; y: 6
            width: parent.width - 8
            component Place: HoverItem {
                id: pl
                property string label: ""
                property string icon: ""
                property string target: ""
                width: parent.width; height: 22
                selected: fd.folder === target
                AppIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; size: 16; name: Theme.icon(pl.icon) }
                VText { x: 38; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 40; text: pl.label }
                onClicked: fd.navigate(target)
            }
            component Head: VText { x: 4; height: 22; verticalAlignment: Text.AlignVCenter; color: "#1e395b"; font.bold: true }
            Head { text: "Favorites" }
            Place { label: "Desktop"; icon: "desktop-folder"; target: Files.desktop }
            Place { label: "Downloads"; icon: "folder-downloads"; target: Files.downloads }
            Item { width: 1; height: 6 }
            Head { text: "Libraries" }
            Place { label: "Documents"; icon: "folder-documents"; target: Files.documents }
            Place { label: "Pictures"; icon: "folder-pictures"; target: Files.pictures }
            Place { label: "Music"; icon: "folder-music"; target: Files.music }
            Place { label: "Videos"; icon: "folder-videos"; target: Files.videos }
            Item { width: 1; height: 6 }
            Head { text: "Computer" }
            Place { label: "Home"; icon: "user-home"; target: Files.home }
            Place { label: "File System"; icon: "drive"; target: "/" }
        }
    }
    // ---- file list
    Item {
        id: listArea
        x: navPane.width
        y: navPane.y
        width: parent.width - x
        height: navPane.height
        Rectangle { anchors.fill: parent; color: "white" }
        Rectangle {
            id: header
            width: parent.width; height: 24
            gradient: Gradient {
                GradientStop { position: 0; color: "#ffffff" }
                GradientStop { position: 1; color: "#f1f5fb" }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#dde4ee" }
            Repeater {
                model: [["Name", 8], ["Date modified", 230], ["Type", 345], ["Size", 420]]
                Item {
                    required property var modelData
                    x: modelData[1]; height: header.height; width: 100
                    VText { x: 4; anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: "#4c607a" }
                    Rectangle { x: -3; width: 1; height: parent.height; color: "#e3e8f0"; visible: modelData[1] > 10 }
                }
            }
        }
        ListView {
            id: list
            y: header.height
            width: parent.width
            height: parent.height - y
            clip: true
            model: model
            boundsBehavior: Flickable.StopAtBounds
            delegate: HoverItem {
                id: row
                required property string fileName
                required property string filePath
                required property bool fileIsDir
                required property var fileModified
                required property var fileSize
                required property string fileSuffix
                width: list.width - 4
                x: 2
                height: 22
                selected: fd.selectedPath === filePath
                AppIcon {
                    x: 6; anchors.verticalCenter: parent.verticalCenter; size: 16
                    name: row.fileIsDir ? Theme.icon("folder") : Files.isImage(row.filePath) ? Theme.icon("image-file") : Theme.icon("app-generic")
                }
                VText { x: 28; width: 196; anchors.verticalCenter: parent.verticalCenter; text: row.fileName }
                VText { x: 234; width: 108; anchors.verticalCenter: parent.verticalCenter; color: Theme.textMuted; text: Qt.formatDateTime(row.fileModified, "yyyy-MM-dd hh:mm") }
                VText { x: 349; width: 70; anchors.verticalCenter: parent.verticalCenter; color: Theme.textMuted; text: row.fileIsDir ? "File folder" : (row.fileSuffix.toUpperCase() + " File") }
                VText { x: 424; width: 60; anchors.verticalCenter: parent.verticalCenter; color: Theme.textMuted; text: row.fileIsDir ? "" : Files.formatSize(row.fileSize); horizontalAlignment: Text.AlignRight }
                onClicked: {
                    fd.selectedPath = row.filePath
                    if (!row.fileIsDir)
                        nameField.text = row.fileName
                }
                onDoubleClicked: {
                    if (row.fileIsDir) {
                        fd.navigate(row.filePath)
                    } else {
                        nameField.text = row.fileName
                        fd.commit()
                    }
                }
            }
            ScrollIndicator7 { flickable: list }
        }
        VText {
            visible: list.count === 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: header.height + 14
            text: fd.search.length ? "No items match your search." : "This folder is empty."
            color: Theme.textMuted
        }
    }
    // ---- name / type / buttons
    Rectangle {
        id: bottom
        anchors.bottom: parent.bottom
        width: parent.width; height: 92
        color: Theme.face
        Rectangle { width: parent.width; height: 1; color: "#d5dfe5" }
        VText { x: 14; y: 14; width: 90; text: "File name:"; horizontalAlignment: Text.AlignRight }
        TextField7 {
            id: nameField
            x: 112; y: 10
            width: parent.width - 126
            onAccepted: fd.commit()
            onTextChanged: fd.confirmPath = ""
        }
        VText { x: 14; y: 41; width: 90; text: fd.mode === "save" ? "Save as type:" : "Files of type:"; horizontalAlignment: Text.AlignRight }
        PaintCombo {
            x: 112; y: 37
            width: parent.width - 126
            model: fd.types.map(t => t.label)
            currentIndex: fd.typeIndex
            onActivated: (i) => {
                fd.typeIndex = i
                if (fd.mode === "save") {
                    const n = nameField.text
                    const dot = n.lastIndexOf(".")
                    if (dot > 0)
                        nameField.text = n.substring(0, dot + 1) + fd.extFor(i)
                }
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 64
            spacing: 8
            Button7 { text: fd.mode === "save" ? "Save" : "Open"; isDefault: true; onClicked: fd.commit() }
            Button7 { text: "Cancel"; onClicked: fd.close() }
        }
    }
    // ---- replace confirmation
    Rectangle {
        visible: fd.confirmPath.length > 0
        anchors.centerIn: parent
        width: 380; height: 120
        color: "white"
        border.color: "#8a9bb0"
        radius: 3
        VText {
            x: 16; y: 14; width: parent.width - 32
            wrapMode: Text.Wrap
            maximumLineCount: 3
            color: "#003399"
            font.pixelSize: 14
            text: Files.fileName(fd.confirmPath) + " already exists.\nDo you want to replace it?"
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.margins: 1
            x: 1
            width: parent.width - 2; height: 40
            color: Theme.face
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Button7 { text: "Yes"; isDefault: true; onClicked: fd.commit() }
                Button7 { text: "No"; onClicked: fd.confirmPath = "" }
            }
        }
    }
}
