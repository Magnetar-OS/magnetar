/* Magnetar installer slideshow.
 *
 * Text over the theme colours rather than screenshots: screenshots of a
 * pre-1.0 desktop go stale between one ISO and the next, and a slideshow
 * showing a UI that no longer looks like that is worse than no slideshow.
 * Replace with images once the desktop settles.
 */

import QtQuick 2.15;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    property color bg:     "#1A1D21"
    property color fg:     "#EAF6FF"
    property color muted:  "#8FA6B8"
    property color accent: "#2AA9E0"

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 20000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Component {
        id: slideBody
        Rectangle { color: presentation.bg }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: presentation.bg
            Column {
                anchors.centerIn: parent
                spacing: 14
                width: parent.width * 0.8
                Text {
                    text: "Magnetar"
                    color: presentation.fg
                    font.pixelSize: 40; font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "The COSMIC desktop on the CachyOS base."
                    color: presentation.muted
                    font.pixelSize: 17
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }
            }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: presentation.bg
            Column {
                anchors.centerIn: parent
                spacing: 14
                width: parent.width * 0.8
                Text {
                    text: "Tuned, not just assembled"
                    color: presentation.accent
                    font.pixelSize: 30; font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "CachyOS's scheduler-patched kernel, hardware detection and "
                        + "CPU-optimised package repositories, kept exactly as they are. "
                        + "Magnetar adds a desktop, not a second opinion about your kernel."
                    color: presentation.muted
                    font.pixelSize: 17
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }
            }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: presentation.bg
            Column {
                anchors.centerIn: parent
                spacing: 14
                width: parent.width * 0.8
                Text {
                    text: "Applications you will not find elsewhere"
                    color: presentation.accent
                    font.pixelSize: 30; font.weight: Font.DemiBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "jump, a launcher with usage-weighted ranking and plugins. "
                        + "peek, previews any file with one keypress. "
                        + "grabit, actions on any selection. "
                        + "locket, secrets for the whole session. "
                        + "envelope, circle and slate for mail, contacts and calendar."
                    color: presentation.muted
                    font.pixelSize: 17
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }
            }
        }
    }
}
