// Monarch Welcome — panel UI.
//
// Renders a centered modal with a header + four step cards. Each card spawns
// the corresponding Monarch command and the panel can be reopened any time
// with `monarch welcome`.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  readonly property var main: pluginApi.mainInstance

  // Suggested size for the panel host.
  property real contentPreferredWidth: 640 * Style.uiScaleRatio
  property real contentPreferredHeight: 560 * Style.uiScaleRatio

  anchors.fill: parent

  // Steps definition — bound to live status from Main.qml.
  readonly property var steps: [
    {
      icon: "keyboard",
      title: "Keybindings cheatsheet",
      body: "Super+K cheatsheet · Super+Space launcher · Super+Alt+Space menu",
      actionLabel: "Open cheatsheet",
      command: "monarch-menu-keybindings",
      done: false
    },
    {
      icon: "wifi",
      title: "Wi-Fi",
      body: root.main.online ? "You're online — Wi-Fi is set up." : "Connect to a network.",
      actionLabel: root.main.online ? "Manage Wi-Fi" : "Open Wi-Fi picker",
      command: "monarch-launch-wifi",
      done: root.main.online
    },
    {
      icon: "download",
      title: "System update",
      body: "Refresh packages and the AUR.",
      actionLabel: "Update now",
      command: "monarch-launch-floating-terminal-with-presentation monarch-update",
      done: false
    },
    {
      icon: "mic",
      title: "Voice dictation (Voxtype)",
      body: root.main.voxtypeInstalled
              ? "Voxtype is installed."
              : "Optional — install voice-to-text for Monarch.",
      actionLabel: root.main.voxtypeInstalled ? "Already installed" : "Install Voxtype",
      command: "monarch-launch-floating-terminal-with-presentation monarch-voxtype-install",
      done: root.main.voxtypeInstalled
    }
  ]

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    // Header
    ColumnLayout {
      Layout.alignment: Qt.AlignHCenter
      Layout.fillWidth: true
      spacing: Style.marginXS

      NLabel {
        Layout.alignment: Qt.AlignHCenter
        text: "Welcome to Monarch"
        font.pixelSize: Style.fontSizeXL
        font.bold: true
      }
      NLabel {
        Layout.alignment: Qt.AlignHCenter
        text: "A few steps to get you started."
        opacity: 0.75
      }
    }

    NDivider { Layout.fillWidth: true }

    // Step cards
    Repeater {
      model: root.steps

      delegate: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 84 * Style.uiScaleRatio
        radius: Style.radiusM
        color: Color.mSurfaceContainerHighest

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            icon: modelData.icon
            font.pixelSize: Style.fontSizeXL
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
              spacing: Style.marginS
              NLabel {
                text: modelData.title
                font.bold: true
              }
              NLabel {
                visible: modelData.done
                text: "✓"
                color: Color.mPrimary
                opacity: 0.9
              }
            }
            NLabel {
              text: modelData.body
              opacity: 0.75
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }
          }

          NButton {
            text: modelData.actionLabel
            enabled: !modelData.done
            onClicked: root.main.spawnHelper(modelData.command)
          }
        }
      }
    }

    Item { Layout.fillHeight: true }

    // Footer
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.marginS
      NLabel { text: "Re-open later with"; opacity: 0.6 }
      NLabel {
        text: "monarch welcome"
        opacity: 0.85
        font.family: Style.fontFamilyMono !== undefined ? Style.fontFamilyMono : "monospace"
      }
    }
  }
}
