/* Vitrum installer slideshow, shown while files are copied. */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 9000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    component Card: Slide {
        property string title: ""
        property string body: ""
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#2f7fd0" }
                GradientStop { position: 1; color: "#0b2f63" }
            }
            Column {
                anchors.centerIn: parent
                width: parent.width * 0.8
                spacing: 18
                Text { width: parent.width; text: title; color: "white"; font.pixelSize: 30; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: body; color: "#dce9fb"; font.pixelSize: 16; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Card {
        title: "Installing Vitrum"
        body: "This will take a few minutes. Your computer will restart when it's done."
    }
    Card {
        title: "Everything where you expect it"
        body: "Start menu, taskbar, Windows Explorer and Control Panel work the way you're used to."
    }
    Card {
        title: "Run Windows programs"
        body: "Double-click a .exe or .msi file and it just runs. Installed programs appear in the Start menu."
    }
    Card {
        title: "Make it yours"
        body: "Choose Aero, Modern or Basic in Control Panel > Personalization, and pick your window color."
    }
}
