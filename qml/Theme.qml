pragma Singleton
import QtQuick
import Vitrum.Core

// Visual constants. Geometry takes after the 2009-era glass desktops; colours
// derive from the user's accent colour ("Window Color" in Settings).
QtObject {
    // "aero" (glass), "modern" (flat acrylic) or "basic" (opaque)
    readonly property string style: ["aero", "modern", "basic"].indexOf(Prefs.theme) >= 0 ? Prefs.theme : "aero"
    readonly property bool isAero: style === "aero"
    readonly property bool isModern: style === "modern"
    readonly property bool isBasic: style === "basic"

    readonly property color accent: Prefs.accentColor
    readonly property bool transparency: Prefs.transparency
    readonly property real intensity: Prefs.colorIntensity
    readonly property string font: Session.fontFamily

    // Typography
    readonly property int fontSize: 12
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeLarge: 15
    readonly property int fontSizeTitle: 20

    // Window frame
    readonly property int frameBorder: isModern ? 1 : 7
    readonly property int titleHeight: isModern ? 32 : 29
    readonly property int titleHeightMaximized: isModern ? 32 : 22
    readonly property int frameRadius: isModern ? 8 : 6
    readonly property int captionHeight: isModern ? 32 : 19
    readonly property bool titleGlow: isAero && transparency
    readonly property color titleText: isModern ? "#1a1a1a" : "#000000"
    readonly property color titleTextInactive: isModern ? "#8a8a8a" : "#444444"

    // Taskbar
    readonly property int taskbarHeight: Prefs.smallTaskbarIcons ? 30 : (isModern ? 46 : 40)
    readonly property int taskbarIconSize: Prefs.smallTaskbarIcons ? 16 : 24
    readonly property int taskButtonWidth: Prefs.smallTaskbarIcons ? 40 : 56

    // Neutral palette
    readonly property color text: "#1e1e1e"
    readonly property color textMuted: "#5a5a5a"
    readonly property color textDisabled: "#9a9a9a"
    readonly property color textOnGlass: "#ffffff"
    readonly property color window: "#ffffff"
    readonly property color face: "#f0f0f0"
    readonly property color faceBorder: "#a0a0a0"
    readonly property color link: "#0066cc"
    readonly property color hoverFill: "#e5f3fb"
    readonly property color hoverBorder: "#70c0e7"
    readonly property color selectFill: "#cce8ff"
    readonly property color selectBorder: "#99d1ff"
    readonly property color focusBorder: "#3399ff"
    readonly property color danger: "#c42b1c"

    // Glass parameters
    function glassIntensity(active) {
        if (!transparency)
            return 0.92
        return active ? intensity : intensity * 0.55
    }
    readonly property real glassSaturation: 0.55
    readonly property color taskbarTint: Qt.darker(accent, 1.9)
    readonly property real taskbarIntensity: transparency ? Math.min(0.8, intensity + 0.12) : 0.95

    // Modern: light mica windows, dark acrylic panels
    function modernTint(role, active) {
        if (role === "window")
            return active ? Qt.tint("#f3f3f3", Qt.rgba(accent.r, accent.g, accent.b, 0.06)) : "#f7f7f7"
        return "#1f1f1f"
    }
    function modernIntensity(role) {
        if (!transparency)
            return 1.0
        return role === "window" ? 0.88 : 0.80
    }
    // Basic: opaque light-blue window faces; panels in a solid accent shade
    function basicTop(role, active) {
        if (role === "window")
            return active ? "#d3e1f3" : "#e6ecf3"
        return Qt.darker(accent, 1.15)
    }
    function basicBottom(role, active) {
        if (role === "window")
            return active ? "#b4c9e6" : "#d5dde8"
        return Qt.darker(accent, 1.7)
    }

    function anim(ms) { return Prefs.animations ? ms : 0 }
    function icon(name) { return "qrc:/qt/qml/Vitrum/icons/" + name + ".svg" }
    function themeIcon(name, fallback) {
        if (!name || name.length === 0)
            name = fallback || "application-x-executable"
        if (name.indexOf("/") === 0 || name.indexOf("qrc:") === 0)
            return name.indexOf("qrc:") === 0 ? name : "image://icon/" + name
        return "image://icon/" + name + "|" + (fallback || "application-x-executable")
    }
}
