import QtQuick
import Vitrum
import Vitrum.Core

// Standard calculator with keyboard support.
FocusScope {
    id: calc
    property var frame: null
    property string display: "0"
    property real acc: 0
    property string op: ""
    property bool fresh: true
    property real memory: 0
    property string history: ""

    Component.onCompleted: forceActiveFocus()

    function fmt(v) {
        if (!isFinite(v)) return "Cannot divide by zero"
        let s = String(Math.round(v * 1e12) / 1e12)
        return s.length > 16 ? v.toPrecision(10) : s
    }
    function digit(d) {
        if (fresh || display === "0" || isNaN(Number(display))) { display = d === "." ? "0." : d; fresh = false; return }
        if (d === "." && display.indexOf(".") >= 0) return
        if (display.length < 16) display += d
    }
    function apply(a, b, o) {
        switch (o) {
        case "+": return a + b
        case "−": return a - b
        case "×": return a * b
        case "÷": return b === 0 ? Infinity : a / b
        }
        return b
    }
    function operator(o) {
        const v = Number(display)
        if (op && !fresh) {
            acc = apply(acc, v, op)
            display = fmt(acc)
        } else if (!op) {
            acc = v
        }
        op = o
        history = fmt(acc) + " " + o
        fresh = true
    }
    function equals() {
        if (!op) return
        const v = Number(display)
        history = fmt(acc) + " " + op + " " + fmt(v) + " ="
        acc = apply(acc, v, op)
        display = fmt(acc)
        op = ""
        fresh = true
    }
    function unary(f) {
        const v = Number(display)
        let r = v
        switch (f) {
        case "neg": r = -v; break
        case "sqrt": r = v < 0 ? NaN : Math.sqrt(v); break
        case "pct": r = op ? acc * v / 100 : v / 100; break
        case "inv": r = v === 0 ? Infinity : 1 / v; break
        case "sq": r = v * v; break
        }
        display = isNaN(r) ? "Invalid input" : fmt(r)
        fresh = f !== "neg"
    }
    function clearAll() { display = "0"; acc = 0; op = ""; fresh = true; history = "" }

    Keys.onPressed: (e) => {
        const t = e.text
        if (t >= "0" && t <= "9") digit(t)
        else if (t === "." || t === ",") digit(".")
        else if (t === "+") operator("+")
        else if (t === "-") operator("−")
        else if (t === "*") operator("×")
        else if (t === "/") operator("÷")
        else if (t === "%") unary("pct")
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || t === "=") equals()
        else if (e.key === Qt.Key_Escape) clearAll()
        else if (e.key === Qt.Key_Backspace) { if (!fresh) display = display.length > 1 ? display.slice(0, -1) : "0" }
        else if (e.key === Qt.Key_Delete) { display = "0"; fresh = true }
        else return
        e.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#e4ecf7" }
            GradientStop { position: 1; color: "#d5e1f2" }
        }
    }
    Rectangle {
        id: screen
        x: 10; y: 10
        width: parent.width - 20
        height: 64
        radius: 2
        border.color: "#8e9fb6"
        gradient: Gradient {
            GradientStop { position: 0; color: "#f9fbfe" }
            GradientStop { position: 1; color: "#e7eef8" }
        }
        VText {
            anchors.right: parent.right; anchors.rightMargin: 8
            y: 6
            text: calc.history
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
        }
        VText {
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 4
            width: parent.width - 16
            horizontalAlignment: Text.AlignRight
            text: calc.display
            font.pixelSize: calc.display.length > 12 ? 20 : 28
        }
        VText {
            x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            visible: calc.memory !== 0
            text: "M"
            color: Theme.textMuted
        }
    }
    Grid {
        id: keys
        x: 10
        anchors.top: screen.bottom
        anchors.topMargin: 10
        columns: 5
        spacing: 6
        readonly property real kw: (calc.width - 20 - 4 * spacing) / 5
        readonly property real kh: (calc.height - screen.height - 40 - 5 * spacing) / 6
        component Key: Button7 {
            property bool accent: false
            width: keys.kw; height: keys.kh
            implicitWidth: keys.kw
        }
        Key { text: "MC"; onClicked: calc.memory = 0 }
        Key { text: "MR"; onClicked: { calc.display = calc.fmt(calc.memory); calc.fresh = true } }
        Key { text: "MS"; onClicked: calc.memory = Number(calc.display) }
        Key { text: "M+"; onClicked: calc.memory += Number(calc.display) }
        Key { text: "M−"; onClicked: calc.memory -= Number(calc.display) }
        Key { text: "←"; onClicked: if (!calc.fresh) calc.display = calc.display.length > 1 ? calc.display.slice(0, -1) : "0" }
        Key { text: "CE"; onClicked: { calc.display = "0"; calc.fresh = true } }
        Key { text: "C"; onClicked: calc.clearAll() }
        Key { text: "±"; onClicked: calc.unary("neg") }
        Key { text: "√"; onClicked: calc.unary("sqrt") }
        Key { text: "7"; onClicked: calc.digit("7") }
        Key { text: "8"; onClicked: calc.digit("8") }
        Key { text: "9"; onClicked: calc.digit("9") }
        Key { text: "÷"; onClicked: calc.operator("÷") }
        Key { text: "%"; onClicked: calc.unary("pct") }
        Key { text: "4"; onClicked: calc.digit("4") }
        Key { text: "5"; onClicked: calc.digit("5") }
        Key { text: "6"; onClicked: calc.digit("6") }
        Key { text: "×"; onClicked: calc.operator("×") }
        Key { text: "1/x"; onClicked: calc.unary("inv") }
        Key { text: "1"; onClicked: calc.digit("1") }
        Key { text: "2"; onClicked: calc.digit("2") }
        Key { text: "3"; onClicked: calc.digit("3") }
        Key { text: "−"; onClicked: calc.operator("−") }
        Key { text: "x²"; onClicked: calc.unary("sq") }
        Key { text: "0"; onClicked: calc.digit("0") }
        Key { text: "00"; onClicked: { calc.digit("0"); calc.digit("0") } }
        Key { text: "."; onClicked: calc.digit(".") }
        Key { text: "+"; onClicked: calc.operator("+") }
        Key { text: "="; isDefault: true; onClicked: calc.equals() }
    }
}
