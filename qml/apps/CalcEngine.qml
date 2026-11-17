import QtQuick

// Calculator logic, kept free of UI so it can be checked headlessly (see
// selfTest(), run by the demo). Standard mode executes each operator as soon
// as the next one is pressed, like the classic desktop calculator; scientific
// mode honours operator precedence and brackets. Every input goes through
// press(command).
QtObject {
    id: eng

    // ---- settings
    property bool scientific: false
    property string angle: "deg"        // "deg" | "rad" | "grad"
    property bool inv: false
    property bool fe: false             // force exponential display
    property bool grouping: false       // digit grouping (1,234,567)

    // ---- outputs (refreshed after every press)
    property string display: "0"
    property string expression: ""
    property bool error: false
    property bool hasMemory: false
    property int parenDepth: 0
    property var history: []            // [{ expr, result }]

    // ---- internal state
    property real memory: 0
    property real cur: 0                // value shown (or being typed)
    property string entry: "0"          // digits while typing
    property bool typing: false
    property bool afterOp: false        // an operator was just pressed
    property string curExpr: ""         // how the current operand reads in the expression line
    property var levels: [{ vals: [], ops: [], expr: [] }]   // one per open bracket
    property string lastOp: ""          // for repeated "="
    property real lastOperand: 0
    property var lastReduce: null
    property string errorText: ""

    readonly property int maxDigits: 16

    function newLevel() { return { vals: [], ops: [], expr: [] } }

    // ------------------------------------------------------------ formatting
    function group(intPart) {
        if (!grouping)
            return intPart
        const neg = intPart.charAt(0) === "-"
        let s = neg ? intPart.substring(1) : intPart
        let out = ""
        while (s.length > 3) {
            out = "," + s.substring(s.length - 3) + out
            s = s.substring(0, s.length - 3)
        }
        return (neg ? "-" : "") + s + out
    }

    // Number -> display text: up to 16 significant digits, exponent form
    // ("1.5e+20") for very large or small magnitudes.
    function fmt(x) {
        if (x === 0 || Object.is(x, -0))
            return fe ? "0.e+0" : "0"
        const neg = x < 0
        const a = Math.abs(x)
        // Whole numbers show all 16 digits; fractions show 15 significant
        // digits, the most a double gets right (2/3 -> 0.666666666666667).
        const sig = Number.isInteger(a) && a < 1e16 ? maxDigits : maxDigits - 1
        let parts = a.toExponential(sig - 1).split("e")
        let exp = parseInt(parts[1])
        if (!fe && exp < 0 && exp >= -9) {
            // fixed notation with small numbers: keep the total width bounded
            parts = a.toExponential(Math.max(0, Math.min(sig - 1, maxDigits + exp))).split("e")
            exp = parseInt(parts[1])
        }
        const digits = parts[0].replace(".", "").replace(/0+$/, "") || "0"
        let s
        if (fe || exp >= maxDigits || exp < -9) {
            s = digits.charAt(0) + "." + digits.substring(1) + "e" + (exp < 0 ? "-" : "+") + Math.abs(exp)
        } else if (exp >= 0) {
            let intPart = digits.substring(0, exp + 1)
            while (intPart.length < exp + 1)
                intPart += "0"
            const frac = digits.substring(exp + 1)
            s = group(intPart) + (frac.length ? "." + frac : "")
        } else {
            s = "0." + "0".repeat(-exp - 1) + digits
        }
        return (neg ? "-" : "") + s
    }

    // Text typed so far, as shown on the display.
    function fmtEntry(t) {
        const e = t.indexOf("e")
        const mant = e >= 0 ? t.substring(0, e) : t
        const dot = mant.indexOf(".")
        let shown = dot >= 0 ? group(mant.substring(0, dot)) + mant.substring(dot) : group(mant)
        if (e >= 0)
            shown = (dot >= 0 ? shown : shown + ".") + t.substring(e)
        return shown
    }

    // Binary floating point turns 0.1 + 0.2 into 0.30000000000000004. When a
    // result is a short decimal plus noise in the last digit or two, keep the
    // short decimal; genuinely long results (1/3) keep their full precision
    // so that 1/3*3 still gives 1.
    function snap(x) {
        if (x === 0 || !isFinite(x))
            return x
        const r = Number(x.toPrecision(15))
        const sig = r.toExponential(14).split("e")[0].replace(/[-.]/g, "").replace(/0+$/, "").length
        return sig <= 13 ? r : x
    }

    function fail(msg) { throw { calcError: msg } }
    function check(v) {
        if (isNaN(v))
            fail("Invalid input")
        if (!isFinite(v))
            fail("Overflow")
        return snap(v)
    }

    // ------------------------------------------------------------ arithmetic
    function prec(o) {
        if (!scientific)
            return 1
        if (o === "+" || o === "-")
            return 1
        if (o === "*" || o === "/" || o === "mod")
            return 2
        return 3 // ^, yroot
    }
    function sym(o) {
        return o === "mod" ? "Mod" : o === "yroot" ? "yroot" : o
    }
    function apply(a, o, b) {
        switch (o) {
        case "+": return check(a + b)
        case "-": return check(a - b)
        case "*": return check(a * b)
        case "/":
            if (b === 0)
                fail(a === 0 ? "Result is undefined" : "Cannot divide by zero")
            return check(a / b)
        case "mod":
            if (b === 0)
                fail("Result is undefined")
            return check(a % b)
        case "^": return check(Math.pow(a, b))
        case "yroot":
            if (b === 0)
                fail("Invalid input")
            if (a < 0 && Math.abs(b % 2) === 1)
                return check(-Math.pow(-a, 1 / b))
            return check(Math.pow(a, 1 / b))
        }
        return b
    }
    function reduce(L, p) {
        while (L.ops.length > 0 && prec(L.ops[L.ops.length - 1]) >= p) {
            const o = L.ops.pop()
            const b = L.vals.pop()
            const a = L.vals.pop()
            L.vals.push(apply(a, o, b))
            lastReduce = { op: o, b: b }
        }
    }

    function toRad(x) { return angle === "deg" ? x * Math.PI / 180 : angle === "grad" ? x * Math.PI / 200 : x }
    function fromRad(x) { return angle === "deg" ? x * 180 / Math.PI : angle === "grad" ? x * 200 / Math.PI : x }
    function tiny(v) { return Math.abs(v) < 1e-15 ? 0 : v }
    function gamma(z) {
        if (z < 0.5)
            return Math.PI / (Math.sin(Math.PI * z) * gamma(1 - z))
        const g = 7
        const c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
                   -176.61503916999185, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]
        z -= 1
        let x = c[0]
        for (let i = 1; i < g + 2; i++)
            x += c[i] / (z + i)
        const t = z + g + 0.5
        return Math.sqrt(2 * Math.PI) * Math.pow(t, z + 0.5) * Math.exp(-t) * x
    }
    function factorial(x) {
        if (x < 0 && Number.isInteger(x))
            fail("Invalid input")
        if (x > 170)
            fail("Overflow")
        if (Number.isInteger(x)) {
            let r = 1
            for (let i = 2; i <= x; i++)
                r *= i
            return r
        }
        return gamma(x + 1)
    }
    function quarterTurn(x) { // tan is undefined at 90 degrees and friends
        const q = angle === "deg" ? 90 : angle === "grad" ? 100 : -1
        return q > 0 && Math.abs(x % (2 * q)) === q
    }
    function dms(x) {
        const neg = x < 0
        x = Math.abs(x)
        const d = Math.floor(x)
        const mFull = (x - d) * 60
        const m = Math.floor(mFull + 1e-9)
        const s = (mFull - m) * 60
        return (neg ? -1 : 1) * (d + m / 100 + s / 10000)
    }
    function degrees(x) {
        const neg = x < 0
        x = Math.abs(x)
        const d = Math.floor(x)
        const m = Math.floor((x - d) * 100 + 1e-9)
        const s = ((x - d) * 100 - m) * 100
        return (neg ? -1 : 1) * (d + m / 60 + s / 3600)
    }

    // name in the expression line, function
    function unaryDef(cmd) {
        const a = angle === "deg" ? "d" : angle === "grad" ? "g" : "r"
        switch (cmd) {
        case "neg": return ["negate", x => -x]
        case "sqrt": return ["sqrt", x => { if (x < 0) fail("Invalid input"); return Math.sqrt(x) }]
        case "recip": return ["reciproc", x => { if (x === 0) fail("Cannot divide by zero"); return 1 / x }]
        case "sq": return ["sqr", x => x * x]
        case "cube": return ["cube", x => x * x * x]
        case "cbrt": return ["cuberoot", x => Math.cbrt(x)]
        case "fact": return ["fact", x => factorial(x)]
        case "tenx": return ["powten", x => Math.pow(10, x)]
        case "ln":
            return inv ? ["powe", x => Math.exp(x)]
                       : ["ln", x => { if (x <= 0) fail("Invalid input"); return Math.log(x) }]
        case "log":
            return inv ? ["powten", x => Math.pow(10, x)]
                       : ["log", x => { if (x <= 0) fail("Invalid input"); return Math.log10(x) }]
        case "sin": return inv ? ["asin" + a, x => fromRad(Math.asin(x))] : ["sin" + a, x => tiny(Math.sin(toRad(x)))]
        case "cos": return inv ? ["acos" + a, x => fromRad(Math.acos(x))] : ["cos" + a, x => tiny(Math.cos(toRad(x)))]
        case "tan":
            return inv ? ["atan" + a, x => fromRad(Math.atan(x))]
                       : ["tan" + a, x => { if (quarterTurn(x)) fail("Invalid input"); return tiny(Math.tan(toRad(x))) }]
        case "sinh": return inv ? ["asinh", x => Math.asinh(x)] : ["sinh", x => Math.sinh(x)]
        case "cosh": return inv ? ["acosh", x => Math.acosh(x)] : ["cosh", x => Math.cosh(x)]
        case "tanh": return inv ? ["atanh", x => Math.atanh(x)] : ["tanh", x => Math.tanh(x)]
        case "int": return inv ? ["frac", x => x - Math.trunc(x)] : ["int", x => Math.trunc(x)]
        case "dms": return inv ? ["degrees", x => degrees(x)] : ["dms", x => dms(x)]
        }
        return null
    }

    // ------------------------------------------------------------ input
    function setError(e) {
        if (e && e.calcError !== undefined) {
            errorText = e.calcError
            error = true
            typing = false
        } else {
            throw e
        }
    }

    function clearAll() {
        levels = [newLevel()]
        cur = 0
        entry = "0"
        typing = false
        afterOp = false
        curExpr = ""
        lastOp = ""
        lastOperand = 0
        error = false
        errorText = ""
        inv = false
    }

    function clearEntry() {
        if (error) {
            clearAll()
            return
        }
        cur = 0
        entry = "0"
        typing = false
        afterOp = false
        curExpr = ""
    }

    function startEntry() {
        if (!typing) {
            entry = "0"
            typing = true
            curExpr = ""
            afterOp = false
        }
    }

    function digit(d) {
        if (error)
            clearAll()
        startEntry()
        const e = entry.indexOf("e")
        if (e >= 0) {
            let ex = entry.substring(e + 2)
            if (ex.length >= 4)
                return
            ex = ex === "0" ? d : ex + d
            entry = entry.substring(0, e + 2) + ex
        } else {
            if (entry.replace(/[-.]/g, "").length >= maxDigits && entry !== "0" && entry !== "-0")
                return
            entry = entry === "0" ? d : entry === "-0" ? "-" + d : entry + d
        }
        cur = Number(entry)
    }

    function decimal() {
        if (error)
            clearAll()
        startEntry()
        if (entry.indexOf(".") < 0 && entry.indexOf("e") < 0)
            entry += "."
    }

    function backspace() {
        if (error) {
            clearAll()
            return
        }
        if (!typing)
            return
        const e = entry.indexOf("e")
        if (e >= 0) {
            const ex = entry.substring(e + 2)
            entry = ex.length > 1 ? entry.slice(0, -1) : ex === "0" ? entry.substring(0, e) : entry.substring(0, e + 2) + "0"
        } else {
            entry = entry.slice(0, -1)
            if (entry === "" || entry === "-" || entry === "-0")
                entry = "0"
        }
        cur = Number(entry.replace(/\.(e|$)/, "$1"))
    }

    function exponent() {
        if (error)
            return
        if (!typing) {
            entry = fmt(cur).replace(/,/g, "")
            if (entry.indexOf("e") >= 0)
                entry = entry.substring(0, entry.indexOf("e"))
            typing = true
            curExpr = ""
            afterOp = false
        }
        if (entry.indexOf("e") < 0)
            entry = entry + (entry.indexOf(".") < 0 ? "." : "") + "e+0"
        cur = Number(entry)
    }

    function negate() {
        if (error)
            return
        if (typing) {
            const e = entry.indexOf("e")
            if (e >= 0)
                entry = entry.substring(0, e + 1) + (entry.charAt(e + 1) === "+" ? "-" : "+") + entry.substring(e + 2)
            else if (entry !== "0")
                entry = entry.charAt(0) === "-" ? entry.substring(1) : "-" + entry
            cur = Number(entry)
            return
        }
        unary("neg")
    }

    function unary(cmd) {
        if (error)
            return
        const def = unaryDef(cmd)
        const x = cur
        curExpr = def[0] + "(" + (curExpr.length ? curExpr : fmt(x)) + ")"
        typing = false
        afterOp = false
        try {
            cur = check(def[1](x))
        } catch (e) {
            setError(e)
        }
        if (cmd !== "neg")
            inv = false
    }

    function commitOperand(L) {
        L.vals.push(cur)
        L.expr.push(curExpr.length ? curExpr : fmt(cur))
        curExpr = ""
    }

    function binary(o) {
        if (error)
            return
        const L = levels[levels.length - 1]
        if (afterOp && L.ops.length > 0) { // changed their mind: swap the operator
            L.ops[L.ops.length - 1] = o
            L.expr[L.expr.length - 1] = sym(o)
            return
        }
        commitOperand(L)
        try {
            reduce(L, prec(o))
        } catch (e) {
            setError(e)
            return
        }
        L.ops.push(o)
        L.expr.push(sym(o))
        cur = L.vals[L.vals.length - 1]
        typing = false
        afterOp = true
        inv = false
    }

    function openParen() {
        if (error || !scientific)
            return
        levels.push(newLevel())
        typing = false
        afterOp = false
        curExpr = ""
    }

    function closeParen() {
        if (error || levels.length < 2)
            return
        const L = levels[levels.length - 1]
        commitOperand(L)
        try {
            reduce(L, 0)
        } catch (e) {
            setError(e)
            return
        }
        levels.pop()
        cur = L.vals[0]
        curExpr = "(" + L.expr.join(" ") + ")"
        typing = false
        afterOp = false
    }

    function equals() {
        if (error) {
            clearAll()
            return
        }
        try {
            while (levels.length > 1)
                closeParen()
            if (error)
                return
            const L = levels[0]
            if (L.ops.length === 0) {
                if (lastOp !== "") {
                    const a = cur
                    const text = (curExpr.length ? curExpr : fmt(a)) + " " + sym(lastOp) + " " + fmt(lastOperand)
                    cur = apply(a, lastOp, lastOperand)
                    addHistory(text, cur)
                }
            } else {
                commitOperand(L)
                const text = L.expr.join(" ")
                lastReduce = null
                reduce(L, 0)
                cur = L.vals[0]
                if (lastReduce) {
                    lastOp = lastReduce.op
                    lastOperand = lastReduce.b
                }
                addHistory(text, cur)
            }
        } catch (e) {
            setError(e)
            return
        }
        levels = [newLevel()]
        curExpr = ""
        typing = false
        afterOp = false
        inv = false
    }

    function addHistory(text, value) {
        history = history.concat([{ expr: text, result: fmt(value) }])
    }

    function percent() {
        if (error)
            return
        const L = levels[levels.length - 1]
        const base = L.ops.length > 0 ? L.vals[L.vals.length - 1] : 0
        try {
            cur = check(base * cur / 100)
        } catch (e) {
            setError(e)
            return
        }
        curExpr = fmt(cur)
        typing = false
        afterOp = false
    }

    function constant(v) {
        if (error)
            clearAll()
        cur = snap(v)
        curExpr = ""
        typing = false
        afterOp = false
        inv = false
    }

    function memoryOp(cmd) {
        if (error && cmd !== "mc" && cmd !== "mr")
            return
        switch (cmd) {
        case "mc": memory = 0; hasMemory = false; return
        case "mr":
            if (error)
                clearAll()
            cur = memory
            curExpr = ""
            typing = false
            afterOp = false
            return
        case "ms": memory = cur; hasMemory = true; break
        case "m+": memory = snap(memory + cur); hasMemory = true; break
        case "m-": memory = snap(memory - cur); hasMemory = true; break
        }
        typing = false
    }

    // Recall a value (history entry, pasted number) as the current operand.
    function setValue(v) {
        if (error)
            clearAll()
        cur = v
        curExpr = ""
        typing = false
        afterOp = false
        refresh()
    }

    function refresh() {
        display = error ? errorText : typing ? fmtEntry(entry) : fmt(cur)
        let ex = levels.map((L, i) => (i > 0 ? "(" : "") + L.expr.join(" ")).join(" ")
        if (curExpr.length && !typing)
            ex = (ex.length ? ex + " " : "") + curExpr
        expression = ex
        parenDepth = levels.length - 1
    }

    // Single entry point for buttons, keys and pasted text.
    function press(cmd) {
        if (cmd.length === 1 && cmd >= "0" && cmd <= "9")
            digit(cmd)
        else switch (cmd) {
        case ".": decimal(); break
        case "+": case "-": case "*": case "/": case "mod": case "^": case "yroot": binary(cmd); break
        case "=": equals(); break
        case "%": percent(); break
        case "(": openParen(); break
        case ")": closeParen(); break
        case "bs": backspace(); break
        case "ce": clearEntry(); break
        case "c": clearAll(); break
        case "neg": negate(); break
        case "mc": case "mr": case "ms": case "m+": case "m-": memoryOp(cmd); break
        case "pi": constant(inv ? 2 * Math.PI : Math.PI); break
        case "exp": exponent(); break
        case "inv": inv = !inv; break
        case "fe": fe = !fe; typing = false; break
        case "deg": case "rad": case "grad": angle = cmd; break
        default:
            if (unaryDef(cmd))
                unary(cmd)
            else
                return false
        }
        refresh()
        return true
    }

    // ------------------------------------------------------------ testing
    // Feed a sequence: single characters, or [command] for named keys,
    // e.g. "2+3*4=" or "9[sqrt]". Returns the display.
    function run(seq) {
        const tokens = seq.match(/\[[^\]]+\]|\S/g) || []
        for (const t of tokens)
            press(t.charAt(0) === "[" ? t.substring(1, t.length - 1) : t)
        return display
    }

    function selfTest() {
        const cases = [
            // [scientific, sequence, expected display, expected expression (optional)]
            [false, "2+3*4=", "20"],
            [false, "2+3*", "5", "2 + 3 *"],
            [false, "5+=", "10"],
            [false, "5+==", "15"],
            [false, "2+3===", "11"],
            [false, "2+3=4=", "7"],
            [false, "10-4==", "2"],
            [false, "50+10%", "5", "50 + 5"],
            [false, "50+10%=", "55"],
            [false, "200*15%=", "6000"],
            [false, "10%", "0"],
            [false, "1/3*3=", "1"],
            [false, "1/3=", "0.333333333333333"],
            [false, "2/3=", "0.666666666666667"],
            [false, "0.1+0.2=", "0.3"],
            [false, "0.1+0.2-0.3=", "0"],
            [false, "0.1*3=", "0.3"],
            [false, "1.1*1.1=", "1.21"],
            [false, "1/0=", "Cannot divide by zero"],
            [false, "0/0=", "Result is undefined"],
            [false, "1/0=[c]", "0"],
            [false, "1/0=7", "7"],
            [false, "0[recip]", "Cannot divide by zero"],
            [false, "4[neg][sqrt]", "Invalid input"],
            [false, "9[sqrt]", "3", "sqrt(9)"],
            [false, "5+9[sqrt]=", "8"],
            [false, "2[sqrt][sqrt]", "1.18920711500272", "sqrt(sqrt(2))"],
            [false, "8[recip]", "0.125"],
            [false, "12[neg]", "-12"],
            [false, "12=[neg]", "-12", "negate(12)"],
            [false, "5+-", "5", "5 -"],
            [false, "5+-3=", "2"],
            [false, "123[bs]", "12"],
            [false, "7[bs]", "0"],
            [false, "1.50", "1.50"],
            [false, "1..5", "1.5"],
            [false, "000", "0"],
            [false, "12345678901234567", "1234567890123456"],
            [false, "99999999*99999999*1000=", "9.9999998e+18"],
            [false, "12345679*9=", "111111111"],
            [false, "5+3[ce]2=", "7"],
            [false, "5+3[c]2=", "2"],
            [false, "7[ms][c][mr]+1=", "8"],
            [false, "7[ms]3[m+][mr]", "10"],
            [false, "7[ms]3[m-][mr]", "4"],
            [false, "7[ms][mc][mr]", "0"],
            [false, "2*[neg]", "-2", "2 * negate(2)"],
            [false, "0.000001/1000=", "0.000000001"],
            [false, "0.000001/10000=", "1.e-10"],
            [false, "3.5*2=", "7"],
            // scientific: precedence, brackets, functions
            [true, "2+3*4=", "14"],
            [true, "2*3+4=", "10"],
            [true, "(2+3)*4=", "20"],
            [true, "2*(3+4)=", "14"],
            [true, "2*(3+4", "4", "2 * (3 +"],
            [true, "2[^]10=", "1024"],
            [true, "2+3[^]2=", "11"],
            [true, "27[yroot]3=", "3"],
            [true, "17[mod]5=", "2"],
            [true, "30[sin]", "0.5", "sind(30)"],
            [true, "60[cos]", "0.5"],
            [true, "45[tan]", "1"],
            [true, "90[tan]", "Invalid input"],
            [true, "180[sin]", "0"],
            [true, "[rad][pi][cos]", "-1"],
            [true, "0.5[inv][sin]", "30"],
            [true, "5[fact]", "120"],
            [true, "0[fact]", "1"],
            [true, "3[sq]", "9"],
            [true, "3[cube]", "27"],
            [true, "27[cbrt]", "3"],
            [true, "100[log]", "2"],
            [true, "2[tenx]", "100"],
            [true, "1[inv][ln]", "2.71828182845905"],
            [true, "[pi]", "3.14159265358979"],
            [true, "2[exp]5", "2.e+5"],
            [true, "2[exp]5+1=", "200001"],
            [true, "2[exp]5[neg]", "2.e-5"],
            [true, "1234[fe]", "1.234e+3"],
            [true, "3.5[int]", "3"],
            [true, "3.5[inv][int]", "0.5"],
            [true, "2+3=*4=", "20"]
        ]
        // run on a scratch engine so this one keeps its state and bindings
        const t = Qt.createQmlObject("import Vitrum\nCalcEngine {}", eng, "CalcEngineSelfTest")
        const failures = []
        for (const c of cases) {
            t.scientific = c[0]
            t.angle = "deg"
            t.fe = false
            t.memory = 0
            t.hasMemory = false
            t.clearAll()
            const got = t.run(c[1])
            if (got !== c[2] || (c.length > 3 && t.expression.trim() !== c[3]))
                failures.push((c[0] ? "sci " : "std ") + c[1] + " -> " + got + " [" + t.expression + "], expected " + c[2]
                              + (c.length > 3 ? " [" + c[3] + "]" : ""))
        }
        t.grouping = true
        t.clearAll()
        if (t.run("1234567") !== "1,234,567")
            failures.push("grouping: " + t.display)
        t.destroy()
        return { total: cases.length + 1, failures: failures }
    }
}
