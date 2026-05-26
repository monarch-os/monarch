// Monarch Welcome — panel UI.
//
// Renders a centered modal with a header + four step cards. Each card spawns
// the corresponding Monarch command. The panel is opened via the official
// Noctalia IPC: `qs ipc call plugin openPanel monarch-welcome`.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons

Item {
  id: root

  property var pluginApi: null
  readonly property var main: pluginApi.mainInstance

  // SmartPanel host integration (required for the plugin host to render us).
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true
  property real contentPreferredWidth: 640 * Style.uiScaleRatio
  property real contentPreferredHeight: 560 * Style.uiScaleRatio

  anchors.fill: parent

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    anchors.margins: Style.marginL
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mOutline
    border.width: Style.borderS

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // -- Header ----------------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        spacing: 4

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: "Welcome to Monarch"
          color: Color.mOnSurface
          font.pixelSize: 28 * Style.uiScaleRatio
          font.bold: true
        }
        Text {
          Layout.alignment: Qt.AlignHCenter
          text: "A few steps to get you started."
          color: Color.mOnSurface
          opacity: 0.7
          font.pixelSize: 14 * Style.uiScaleRatio
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Color.mOutline
        opacity: 0.4
      }

      // -- Step cards ------------------------------------------------------
      Repeater {
        model: [
          {
            "glyph": "",
            "title": "Keybindings cheatsheet",
            "body": "Super+K cheatsheet · Super+Space launcher · Super+Alt+Space menu",
            "actionLabel": "Open cheatsheet",
            "command": "monarch-menu-keybindings",
            "done": false
          },
          {
            "glyph": "󰖩",
            "title": "Wi-Fi",
            "body": root.main && root.main.online ? "You're online." : "Connect to a network.",
            "actionLabel": root.main && root.main.online ? "Manage Wi-Fi" : "Open Wi-Fi picker",
            "command": "monarch-launch-wifi",
            "done": !!(root.main && root.main.online)
          },
          {
            "glyph": "",
            "title": "System update",
            "body": "Refresh packages and the AUR.",
            "actionLabel": "Update now",
            "command": "monarch-launch-floating-terminal-with-presentation monarch-update",
            "done": false
          },
          {
            "glyph": "",
            "title": "Voice dictation (Voxtype)",
            "body": (root.main && root.main.voxtypeInstalled)
                      ? "Voxtype is installed."
                      : "Optional — install voice-to-text for Monarch.",
            "actionLabel": (root.main && root.main.voxtypeInstalled) ? "Already installed" : "Install Voxtype",
            "command": "monarch-launch-floating-terminal-with-presentation monarch-voxtype-install",
            "done": !!(root.main && root.main.voxtypeInstalled)
          }
        ]

        delegate: Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 76 * Style.uiScaleRatio
          radius: Style.radiusM
          color: Color.mSurfaceVariant !== undefined ? Color.mSurfaceVariant : Color.mSurface
          border.color: Color.mOutline
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            Text {
              text: modelData.glyph
              color: Color.mPrimary
              font.pixelSize: 22 * Style.uiScaleRatio
              Layout.preferredWidth: 28 * Style.uiScaleRatio
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              RowLayout {
                spacing: 6
                Text {
                  text: modelData.title
                  color: Color.mOnSurface
                  font.pixelSize: 15 * Style.uiScaleRatio
                  font.bold: true
                }
                Text {
                  visible: modelData.done
                  text: "✓"
                  color: Color.mPrimary
                  font.pixelSize: 14 * Style.uiScaleRatio
                }
              }
              Text {
                text: modelData.body
                color: Color.mOnSurface
                opacity: 0.7
                font.pixelSize: 12 * Style.uiScaleRatio
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
              }
            }

            Button {
              text: modelData.actionLabel
              enabled: !modelData.done
              onClicked: {
                if (root.main && root.main.spawnHelper)
                  root.main.spawnHelper(modelData.command)
              }
            }
          }
        }
      }

      Item { Layout.fillHeight: true }

      // -- Footer ----------------------------------------------------------
      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 6
        Text {
          text: "Re-open later with"
          color: Color.mOnSurface
          opacity: 0.6
          font.pixelSize: 12 * Style.uiScaleRatio
        }
        Text {
          text: "monarch welcome"
          color: Color.mOnSurface
          opacity: 0.9
          font.pixelSize: 12 * Style.uiScaleRatio
          font.family: "monospace"
        }
      }
    }
  }
}
