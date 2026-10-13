// SPDX-License-Identifier: GPL-3.0-or-later
// Fundido a negro al cerrar sesión (Estación).
// Lo lanza estacion-cerrar-sesion justo antes de parar la sesión.
// Salvaguarda: se cierra solo a los 4 s, para que nunca quede una capa negra sobre una sesión viva
// si el cierre de sesión fallara después.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "estacion-fundido"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}   // no captura el ratón: los clics pasan a la sesión

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0

                NumberAnimation on opacity {
                    from: 0
                    to: 1
                    duration: 400
                    easing.type: Easing.InCubic
                }
            }
        }
    }

    Timer {
        interval: 4000
        running: true
        onTriggered: Qt.quit()
    }
}
