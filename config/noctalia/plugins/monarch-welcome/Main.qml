// Monarch Welcome — background logic + IPC handler.
//
// The Panel renders the steps; this file owns:
//   - live status (online?, Voxtype installed?) refreshed on open
//   - IPC entry points triggered by `monarch-welcome` and the first-run hook
//   - a single Process used to spawn the action commands

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  // Injected by Noctalia's PluginService
  property var pluginApi: null

  // Live state — bound by Panel.qml
  property bool online: false
  property bool voxtypeInstalled: false

  function refreshState() {
    pingProc.running = true
    voxProc.running = true
  }

  // Spawn a Monarch helper (fire-and-forget) for the panel actions.
  function spawnHelper(cmd) {
    helperProc.command = ["sh", "-c", cmd]
    helperProc.running = true
  }

  Process {
    id: pingProc
    command: ["sh", "-c", "ping -c1 -W1 1.1.1.1 >/dev/null 2>&1"]
    onExited: function (code) { root.online = (code === 0) }
  }

  Process {
    id: voxProc
    command: ["sh", "-c", "command -v voxtype >/dev/null 2>&1"]
    onExited: function (code) { root.voxtypeInstalled = (code === 0) }
  }

  Process {
    id: helperProc
    running: false
  }

  Component.onCompleted: refreshState()

  IpcHandler {
    target: "plugin:monarch-welcome"

    function open() {
      Logger.i("MonarchWelcome", "Opening welcome panel")
      root.refreshState()
      if (root.pluginApi && root.pluginApi.openPanel) {
        root.pluginApi.openPanel()
      } else if (root.pluginApi && root.pluginApi.togglePanel) {
        root.pluginApi.togglePanel()
      }
    }

    function close() {
      if (root.pluginApi && root.pluginApi.closePanel) {
        root.pluginApi.closePanel()
      }
    }

    function refresh() {
      root.refreshState()
    }
  }
}
