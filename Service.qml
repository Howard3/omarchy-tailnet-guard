import QtQuick
import Quickshell
import Quickshell.Io

// Keep the fail-closed daemon running. Policy itself lives in
// bin/tailnet-guard so it still applies if the shell restarts.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property string omarchyPath: ""

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    if (u.indexOf("file://") === 0) u = u.substring(7)
    while (u.length > 1 && u.charAt(u.length - 1) === "/") u = u.substring(0, u.length - 1)
    return decodeURIComponent(u)
  }

  readonly property string script: root.pluginDir + "/bin/tailnet-guard"
  property bool systemdActive: false
  property bool childFallback: false

  function ensureDaemon() {
    if (activeCheck.running || installProc.running) return
    activeCheck.running = true
  }

  Process {
    id: activeCheck
    running: false
    command: ["systemctl", "--user", "is-active", "hlince-tailnet-guard.service"]
    onExited: function(exitCode) {
      root.systemdActive = exitCode === 0
      if (root.systemdActive) {
        root.childFallback = false
        fallbackProc.running = false
        return
      }
      if (!installProc.running) installProc.running = true
    }
  }

  Process {
    id: installProc
    running: false
    command: [root.script, "install-service"]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.systemdActive = true
        root.childFallback = false
        fallbackProc.running = false
        return
      }
      root.systemdActive = false
      root.childFallback = true
      if (!fallbackProc.running) fallbackProc.running = true
    }
  }

  Process {
    id: fallbackProc
    running: false
    command: ["setpriv", "--pdeathsig", "TERM", root.script, "run"]
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.ensureDaemon()
  }
}
