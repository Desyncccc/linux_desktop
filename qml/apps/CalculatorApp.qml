import QtQuick
import Vitrum
import Vitrum.Core

// Calculator in the 2009-era desktop style: View/Edit/Help menu, pale blue
// display with an expression line, silver keys that glow amber on hover.
// The arithmetic lives in CalcEngine.
FocusScope {
    id: calc
    property var frame: null
    property string mode: "standard"     // "standard" | "scientific"
    property bool showHistory: false
    property string flashCmd: ""
    readonly property bool sci: mode === "scientific"
    property alias engine: eng
    property bool ready: false

    // ---- geometry (all in content pixels)
    readonly property int margin: 11
    readonly property int keyW: 34
    readonly property int keyH: 27
    readonly property int gap: 5
    readonly property int blockW: 5 * keyW + 4 * gap
    readonly property int blockGap: 12
    readonly property int menuH: 20
    readonly property int historyH: 104
    readonly property int displayH: 54 + (showHistory ? historyH : 0)
    readonly property int keysTop: menuH + 8 + displayH + 10
    readonly property int rightX: sci ? margin + blockW + blockGap : margin
    readonly property int contentW: sci ? 2 * margin + 2 * blockW + blockGap : 2 * margin + blockW
    readonly property int contentH: keysTop + 6 * keyH + 5 * gap + margin

    CalcEngine {
        id: eng
        scientific: calc.sci
    }

    readonly property string configDir: (Session.env("XDG_CONFIG_HOME") || Files.home + "/.config") + "/Vitrum"
    readonly property string settingsPath: configDir + "/calculator.json"

    Component.onCompleted: {
        try {
            const s = JSON.parse(Files.readText(settingsPath))
            if (s.mode === "scientific" || s.mode === "standard")
                mode = s.mode
            showHistory = s.history === true
            eng.grouping = s.grouping === true
        } catch (e) {
            // first run: defaults
        }
        eng.refresh()
        ready = true
        Qt.callLater(applySize)
        forceActiveFocus()
    }
    onFrameChanged: if (frame) { frame.internalTitle = "Calculator"; applySize() }
    onModeChanged: { eng.clearAll(); eng.refresh(); saveSettings() }
    onShowHistoryChanged: saveSettings()
    onContentWChanged: applySize()
    onContentHChanged: applySize()

    function applySize() {
        if (!frame)
            return
        frame.internalMinWidth = contentW
        frame.internalMinHeight = contentH
        frame.internalWidth = contentW
        frame.internalHeight = contentH
        // keep the window on screen when it grows
        const a = Shell.workArea
        if (frame.placed && frame.x + frame.width > a.x + a.width)
            frame.x = Math.max(a.x, a.x + a.width - frame.width)
        if (frame.placed && frame.y + frame.height > a.y + a.height)
            frame.y = Math.max(a.y, a.y + a.height - frame.height)
    }

    function saveSettings() {
        if (!ready)
            return
        if (!Files.exists(configDir))
            Files.makeFolder(Files.parentDir(configDir), "Vitrum")
        Files.writeText(settingsPath, JSON.stringify({ mode: mode, history: showHistory, grouping: eng.grouping }))
    }

    function press(cmd) {
        if (eng.error && !keyEnabledInError(cmd))
            return
        eng.press(cmd)
    }
    function flash(cmd) {
        flashCmd = cmd
        flashTimer.restart()
    }
    Timer { id: flashTimer; interval: 110; onTriggered: calc.flashCmd = "" }

    function keyEnabledInError(cmd) {
        return (cmd.length === 1 && cmd >= "0" && cmd <= "9") || ["c", "ce", "bs", ".", "=", "mc", "mr", "pi"].indexOf(cmd) >= 0
    }

    // ---- clipboard (through a hidden text editor)
    TextEdit { id: clipHelper; visible: false; width: 0; height: 0 }
    function copy() {
        if (eng.error)
            return
        clipHelper.text = eng.display.replace(/,/g, "")
        clipHelper.selectAll()
        clipHelper.copy()
        clipHelper.text = ""
    }
    function paste() {
        clipHelper.text = ""
        clipHelper.paste()
        const t = clipHelper.text.trim().replace(/,/g, "")
        clipHelper.text = ""
        if (!t.length)
            return
        if (/^-?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(t)) {
            eng.setValue(eng.snap(Number(t)))
            return
        }
        // otherwise replay it as keystrokes: "12+7=" works
        for (let i = 0; i < t.length; i++) {
            const cmd = charCommand(t.charAt(i))
            if (cmd !== "")
                press(cmd)
        }
    }

    function charCommand(ch) {
        if (ch >= "0" && ch <= "9")
            return ch
        switch (ch) {
        case ".": case ",": return "."
        case "+": case "-": case "*": case "/": case "%": case "=": return ch
        case "@": return "sqrt"
        case "r": case "R": return "recip"
        }
        if (!sci)
            return ""
        switch (ch) {
        case "(": case ")": return ch
        case "^": case "y": return "^"
        case "s": return "sin"
        case "o": return "cos"
        case "t": return "tan"
        case "n": return "ln"
        case "l": return "log"
        case "q": return "sq"
        case "#": return "cube"
        case "!": return "fact"
        case "p": return "pi"
        case "i": return "inv"
        case "x": return "exp"
        case "v": return "fe"
        case "m": return "dms"
        case ";": return "int"
        case "d": return "mod"
        }
        return ""
    }

    Keys.onPressed: (e) => {
        let cmd = ""
        if (e.modifiers & Qt.ControlModifier) {
            switch (e.key) {
            case Qt.Key_M: cmd = "ms"; break
            case Qt.Key_R: cmd = "mr"; break
            case Qt.Key_P: cmd = "m+"; break
            case Qt.Key_Q: cmd = "m-"; break
            case Qt.Key_L: cmd = "mc"; break
            case Qt.Key_B: if (sci) cmd = "cbrt"; break
            case Qt.Key_Y: if (sci) cmd = "yroot"; break
            case Qt.Key_G: if (sci) cmd = "tenx"; break
            case Qt.Key_C: copy(); e.accepted = true; return
            case Qt.Key_V: paste(); e.accepted = true; return
            case Qt.Key_H: showHistory = !showHistory; e.accepted = true; return
            case Qt.Key_D:
                if (e.modifiers & Qt.ShiftModifier) { eng.history = []; e.accepted = true }
                return
            }
        } else if (e.modifiers & Qt.AltModifier) {
            if (e.key === Qt.Key_1) { mode = "standard"; e.accepted = true }
            else if (e.key === Qt.Key_2) { mode = "scientific"; e.accepted = true }
            return
        } else {
            switch (e.key) {
            case Qt.Key_Return: case Qt.Key_Enter: cmd = "="; break
            case Qt.Key_Backspace: cmd = "bs"; break
            case Qt.Key_Escape: cmd = "c"; break
            case Qt.Key_Delete: cmd = "ce"; break
            case Qt.Key_F9: cmd = "neg"; break
            case Qt.Key_F3: if (sci) cmd = "deg"; break
            case Qt.Key_F4: if (sci) cmd = "rad"; break
            case Qt.Key_F5: if (sci) cmd = "grad"; break
            default: cmd = e.text.length === 1 ? charCommand(e.text) : ""
            }
        }
        if (cmd !== "") {
            press(cmd)
            flash(cmd)
            e.accepted = true
        }
    }

    // ---- background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.c("#e3ebf6") }
            GradientStop { position: 1; color: Theme.c("#d2deee") }
        }
    }

    // ---- menu bar
    Row {
        id: menuBar
        x: 2
        height: calc.menuH
        component MenuTitle: HoverItem {
            id: mtItem
            property string text: ""
            width: mt.implicitWidth + 14; height: parent.height
            radius: 2
            VText { id: mt; anchors.centerIn: parent; text: mtItem.text }
        }
        MenuTitle {
            text: "View"
            onClicked: { const g = mapToItem(Shell.root, 0, height); Shell.showMenu([
                { text: "Standard\tAlt+1", checked: !calc.sci, action: () => calc.mode = "standard" },
                { text: "Scientific\tAlt+2", checked: calc.sci, action: () => calc.mode = "scientific" },
                { text: "Programmer\tAlt+3", enabled: false },
                { text: "Statistics\tAlt+4", enabled: false },
                { separator: true },
                { text: "History\tCtrl+H", checked: calc.showHistory, action: () => calc.showHistory = !calc.showHistory },
                { text: "Digit grouping", checked: eng.grouping, action: () => { eng.grouping = !eng.grouping; eng.refresh(); calc.saveSettings() } }
            ], g.x, g.y) }
        }
        MenuTitle {
            text: "Edit"
            onClicked: { const g = mapToItem(Shell.root, 0, height); Shell.showMenu([
                { text: "Copy\tCtrl+C", enabled: !eng.error, action: () => calc.copy() },
                { text: "Paste\tCtrl+V", action: () => calc.paste() },
                { separator: true },
                { text: "Copy history", enabled: eng.history.length > 0, action: () => {
                    clipHelper.text = eng.history.map(h => h.expr + " = " + h.result).join("\n")
                    clipHelper.selectAll(); clipHelper.copy(); clipHelper.text = "" } },
                { text: "Clear history\tCtrl+Shift+D", enabled: eng.history.length > 0, action: () => eng.history = [] }
            ], g.x, g.y) }
        }
        MenuTitle {
            text: "Help"
            onClicked: { const g = mapToItem(Shell.root, 0, height); Shell.showMenu([
                { text: "View Help\tF1", enabled: false },
                { separator: true },
                { text: "About Calculator", action: () => Shell.openInternal("message", {
                    kind: "info", title: "About Calculator",
                    message: "Calculator\nVitrum " + Session.version + "\n\nStandard and scientific calculator for the Vitrum desktop." }) }
            ], g.x, g.y) }
        }
    }

    // ---- display
    Rectangle {
        id: display
        x: calc.margin
        y: calc.menuH + 8
        width: calc.width - 2 * calc.margin
        height: calc.displayH
        radius: 3
        border.color: Theme.c("#8b9fbd")
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.c("#f9fbfe") }
            GradientStop { position: 0.55; color: Theme.c("#edf3fb") }
            GradientStop { position: 1; color: Theme.c("#dbe6f4") }
        }
        Rectangle { // inner highlight
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.75)
        }

        // History list, newest at the bottom
        ListView {
            id: historyList
            visible: calc.showHistory
            x: 6; y: 4
            width: parent.width - 12
            height: calc.historyH - 10
            clip: true
            model: eng.history
            boundsBehavior: Flickable.StopAtBounds
            onCountChanged: positionViewAtEnd()
            delegate: HoverItem {
                id: hrow
                required property var modelData
                width: historyList.width
                height: 32
                Column {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 8
                    VText {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                        text: hrow.modelData.expr
                        color: Theme.c("#4b5a6e")
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    VText {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: "= " + hrow.modelData.result
                        font.bold: true
                    }
                }
                onClicked: eng.setValue(Number(hrow.modelData.result.replace(/,/g, "")))
            }
            VText {
                anchors.centerIn: parent
                visible: eng.history.length === 0
                text: "There's no history yet"
                color: Theme.c("#7d8899")
                font.italic: true
            }
        }
        Rectangle {
            visible: calc.showHistory
            x: 6; y: calc.historyH - 3
            width: parent.width - 12; height: 1
            color: Theme.c("#a9b9d0")
        }

        Item {
            id: readout
            y: calc.showHistory ? calc.historyH : 0
            width: parent.width
            height: 54
            VText {
                id: exprLine
                x: 22
                y: 5
                width: parent.width - x - 7
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: eng.expression
                color: Theme.c("#56637a")
                font.pixelSize: Theme.fontSizeSmall
            }
            VText {
                x: 6; y: 5
                visible: eng.parenDepth > 0
                text: "(=" + eng.parenDepth
                color: Theme.c("#56637a")
                font.pixelSize: Theme.fontSizeSmall
            }
            VText {
                x: 7
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                visible: eng.hasMemory
                text: "M"
                color: Theme.c("#2c3a4f")
                font.pixelSize: Theme.fontSize
            }
            Text {
                id: number
                x: 20
                y: 19
                width: parent.width - x - 7
                height: 30
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                text: eng.display
                font.family: Theme.font
                font.pixelSize: eng.error ? 16 : 24
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 11
                color: Theme.c("#101820")
                renderType: Text.NativeRendering
            }
        }
    }

    // ---- keys
    function keyModel() {
        const L = []
        function add(block, c, r, label, cmd, cs, rs, toggle, invLabel) {
            L.push({ x: block + c * (keyW + gap), y: keysTop + r * (keyH + gap),
                     w: (cs || 1) * keyW + ((cs || 1) - 1) * gap, h: (rs || 1) * keyH + ((rs || 1) - 1) * gap,
                     label: label, invLabel: invLabel || label, cmd: cmd, toggle: toggle || "" })
        }
        const R = rightX
        const std = [
            ["MC", "mc"], ["MR", "mr"], ["MS", "ms"], ["M+", "m+"], ["M-", "m-"],
            ["←", "bs"], ["CE", "ce"], ["C", "c"], ["±", "neg"], ["√", "sqrt"],
            ["7", "7"], ["8", "8"], ["9", "9"], ["/", "/"], ["%", "%"],
            ["4", "4"], ["5", "5"], ["6", "6"], ["*", "*"], ["1/x", "recip"],
            ["1", "1"], ["2", "2"], ["3", "3"], ["-", "-"]
        ]
        std.forEach((k, i) => add(R, i % 5, Math.floor(i / 5), k[0], k[1]))
        add(R, 4, 4, "=", "=", 1, 2)
        add(R, 0, 5, "0", "0", 2)
        add(R, 2, 5, ".", ".")
        add(R, 3, 5, "+", "+")
        if (sci) {
            const S = margin
            const sk = [ // column, row, label, command, toggle, label with Inv
                [1, 1, "Inv", "inv", "inv"], [2, 1, "ln", "ln", "", "eˣ"], [3, 1, "(", "("], [4, 1, ")", ")"],
                [0, 2, "Int", "int", "", "Frac"], [1, 2, "sinh", "sinh", "", "sinh⁻¹"], [2, 2, "sin", "sin", "", "sin⁻¹"],
                [3, 2, "x²", "sq"], [4, 2, "n!", "fact"],
                [0, 3, "dms", "dms", "", "deg"], [1, 3, "cosh", "cosh", "", "cosh⁻¹"], [2, 3, "cos", "cos", "", "cos⁻¹"],
                [3, 3, "xʸ", "^"], [4, 3, "ʸ√x", "yroot"],
                [0, 4, "π", "pi", "", "2π"], [1, 4, "tanh", "tanh", "", "tanh⁻¹"], [2, 4, "tan", "tan", "", "tan⁻¹"],
                [3, 4, "x³", "cube"], [4, 4, "∛x", "cbrt"],
                [0, 5, "F-E", "fe", "fe"], [1, 5, "Exp", "exp"], [2, 5, "Mod", "mod"], [3, 5, "log", "log"], [4, 5, "10ˣ", "tenx"]
            ]
            sk.forEach(k => add(S, k[0], k[1], k[2], k[3], 1, 1, k[4], k[5]))
        }
        return L
    }

    Repeater {
        model: calc.keyModel()
        delegate: Item {
            id: key
            required property var modelData
            readonly property string cmd: modelData.cmd
            readonly property bool toggled: modelData.toggle === "inv" ? eng.inv : modelData.toggle === "fe" ? eng.fe : false
            readonly property bool usable: !eng.error || calc.keyEnabledInError(cmd)
            readonly property bool down: (ma.pressed && ma.containsMouse) || calc.flashCmd === cmd
            readonly property bool hot: ma.containsMouse && usable
            x: modelData.x; y: modelData.y
            width: modelData.w; height: modelData.h
            opacity: usable ? 1 : 0.5

            Rectangle {
                anchors.fill: parent
                radius: 3
                border.color: Theme.c(key.down ? "#a0742a" : key.hot ? "#d8a443" : key.toggled ? "#8a7038" : "#8a9bb5")
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.c(key.down ? "#f9d98f" : key.hot ? "#fff9e3" : key.toggled ? "#f3dfae" : "#fbfcfe") }
                    GradientStop { position: 0.45; color: Theme.c(key.down ? "#f4c66a" : key.hot ? "#ffeab0" : key.toggled ? "#ecd08f" : "#eef3f9") }
                    GradientStop { position: 0.5; color: Theme.c(key.down ? "#eeb247" : key.hot ? "#ffd97a" : key.toggled ? "#e3bf6c" : "#dfe7f2") }
                    GradientStop { position: 1.0; color: Theme.c(key.down ? "#f6cd74" : key.hot ? "#ffe7a8" : key.toggled ? "#efd497" : "#e8eef6") }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 2
                    color: "transparent"
                    border.color: Qt.rgba(1, 1, 1, key.down ? 0.25 : 0.8)
                }
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: key.down ? 1 : 0
                text: eng.inv ? key.modelData.invLabel : key.modelData.label
                font.family: Theme.font
                font.pixelSize: text.length > 3 ? 11 : (text.length > 1 ? 12 : 14)
                color: Theme.c("#15233a")
                renderType: Text.NativeRendering
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                enabled: key.usable
                onPressed: calc.forceActiveFocus()
                onClicked: calc.press(key.cmd)
            }
        }
    }

    // ---- angle units (scientific)
    Rectangle {
        visible: calc.sci
        x: calc.margin
        y: calc.keysTop - 2
        width: calc.blockW
        height: calc.keyH + 4
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.35)
        border.color: Theme.c("#9fb1cb")
        Row {
            anchors.centerIn: parent
            spacing: 10
            Repeater {
                model: [["Degrees", "deg"], ["Radians", "rad"], ["Grads", "grad"]]
                delegate: Item {
                    id: radio
                    required property var modelData
                    readonly property bool on: eng.angle === modelData[1]
                    width: 16 + lbl.implicitWidth
                    height: 18
                    Rectangle {
                        width: 13; height: 13; radius: 6.5
                        anchors.verticalCenter: parent.verticalCenter
                        border.color: rma.containsMouse ? Theme.c("#3c7fb1") : Theme.c("#8e8f8f")
                        gradient: Gradient {
                            GradientStop { position: 0; color: rma.containsMouse ? Theme.c("#def9fa") : Theme.c("#ebebeb") }
                            GradientStop { position: 1; color: rma.containsMouse ? Theme.c("#a8dbf9") : Theme.c("#ffffff") }
                        }
                        Rectangle {
                            visible: radio.on
                            anchors.centerIn: parent
                            width: 7; height: 7; radius: 3.5
                            gradient: Gradient {
                                GradientStop { position: 0; color: Theme.c("#7ab4e8") }
                                GradientStop { position: 1; color: Theme.c("#1c5aa6") }
                            }
                        }
                    }
                    VText {
                        id: lbl
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: radio.modelData[0]
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    MouseArea {
                        id: rma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { calc.forceActiveFocus(); calc.press(radio.modelData[1]) }
                    }
                }
            }
        }
    }
}
