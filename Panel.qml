import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "howard3.tailnet-guard"
  ipcTarget: "howard3.tailnet-guard"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color dimmer: Qt.darker(foreground, 2.2)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    if (u.indexOf("file://") === 0) u = u.substring(7)
    while (u.length > 1 && u.charAt(u.length - 1) === "/") u = u.substring(0, u.length - 1)
    return decodeURIComponent(u)
  }
  readonly property string script: root.pluginDir + "/bin/tailnet-guard"
  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/tailnet-guard.json"
  readonly property string statusPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/tailnet-guard/status.json"

  property var status: ({})
  property var config: ({ defaultPolicy: "deny", safe: [], unsafe: [], notify: true })
  property int cursor: 0
  property bool cursorActive: false

  readonly property string phase: String(status.phase || "disconnected")
  readonly property string networkName: String(status.network || status.ssid || status.connection || "")
  readonly property bool connected: phase === "connected"
  readonly property bool heldDown: String(status.decision || "down") !== "up"
  readonly property bool currentTrusted: status.safe === true
  readonly property var safeNets: config.safe instanceof Array ? config.safe : []
  readonly property var unsafeNets: config.unsafe instanceof Array ? config.unsafe : []
  readonly property bool defaultAllow: String(config.defaultPolicy || "deny") === "allow"
  readonly property var menuRows: buildRows()

  readonly property color barIconColor: {
    if (!root.connected) return root.dim
    if (root.heldDown) return Qt.darker(root.barForeground, 1.55)
    return root.barForeground
  }

  readonly property int barContentWidth: Style.bar.iconFont
  readonly property int barSlot: barContentWidth + Style.space(10)
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  function buildRows() {
    var rows = [
      { kind: "allowCurrent" },
      { kind: "defaultPolicy" }
    ]
    var i
    for (i = 0; i < safeNets.length; i++) rows.push({ kind: "safe", name: String(safeNets[i]) })
    for (i = 0; i < unsafeNets.length; i++) rows.push({ kind: "unsafe", name: String(unsafeNets[i]) })
    return rows
  }

  function parseJson(raw, fallback) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") return parsed
    } catch (e) {
    }
    return fallback
  }

  function runGuard(args) {
    Quickshell.execDetached([root.script].concat(args))
  }

  function currentName() {
    return root.networkName
  }

  function allowCurrent() {
    if (!root.connected || root.currentName() === "") return
    runGuard(["allow", "--current"])
  }

  function denyCurrent() {
    if (!root.connected || root.currentName() === "") return
    runGuard(["deny", "--current"])
  }

  function forgetName(name) {
    if (!name) return
    runGuard(["forget", name])
  }

  function toggleDefault() {
    runGuard(["set-default", root.defaultAllow ? "deny" : "allow"])
  }

  function toggleCurrentAllow() {
    if (root.currentTrusted) denyCurrent()
    else allowCurrent()
  }

  function activateCursor() {
    var rows = root.menuRows
    if (rows.length === 0) return
    var row = rows[Math.max(0, Math.min(root.cursor, rows.length - 1))]
    if (row.kind === "allowCurrent") toggleCurrentAllow()
    else if (row.kind === "defaultPolicy") toggleDefault()
    else if (row.name) forgetName(row.name)
  }

  function moveCursor(dy) {
    root.cursorActive = true
    var n = root.menuRows.length
    if (n === 0) return
    root.cursor = (root.cursor + dy % n + n) % n
  }

  onOpenedChanged: {
    if (opened) {
      statusFile.reload()
      configFile.reload()
      root.cursor = 0
      root.cursorActive = false
    }
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.status = root.parseJson(text(), {})
    onLoadFailed: root.status = ({})
    onFileChanged: reload()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.config = root.parseJson(text(), { defaultPolicy: "deny", safe: [], unsafe: [], notify: true })
    onLoadFailed: root.config = ({ defaultPolicy: "deny", safe: [], unsafe: [], notify: true })
    onFileChanged: reload()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    opticalSize: root.barContentWidth
    tooltipText: {
      var text = String(root.status.reasonText || "")
      if (text !== "") return text
      return root.heldDown ? "Tailscale held down" : "Tailscale allowed"
    }

    iconComponent: Component {
      ShieldIcon {
        iconSize: Style.bar.iconFont
        color: root.barIconColor
        heldDown: root.heldDown
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.runGuard(["apply"])
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Math.min(Style.space(300), panel.availableCardWidth > 0 ? panel.availableCardWidth : Style.space(300))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.activateCursor()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onTextKey: function(t) {
        if (t === "a") root.allowCurrent()
        else if (t === "d") root.denyCurrent()
        else if (t === "t") root.toggleDefault()
        else if (t === "r") root.runGuard(["apply"])
      }

      Flickable {
        id: mainScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: mainColumn
          width: mainScroll.width
          spacing: 0

          PanelHero {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            title: root.connected ? (root.networkName || "Network") : (root.phase === "sleeping" ? "Sleeping" : "Between networks")
            meta: root.status.reasonText || (root.heldDown ? "Tailscale held down" : "Tailscale allowed")
            iconComponent: Component {
              ShieldIcon {
                iconSize: Style.font.display
                color: root.connected && !root.heldDown ? root.foreground : root.dim
                heldDown: root.heldDown
              }
            }
          }

          Item { width: 1; height: Style.space(12) }

          Toggle {
            width: parent.width
            label: "Allow Tailscale here"
            description: root.connected
              ? (root.currentTrusted ? "This network is trusted" : "Unknown and blocked until you allow it")
              : "Connect to a network first"
            checked: root.currentTrusted
            enabled: root.connected && root.currentName() !== ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.cursor === 0
            onClicked: root.toggleCurrentAllow()
          }

          Item { width: 1; height: Style.space(8) }

          Toggle {
            width: parent.width
            label: "Unknown networks"
            description: root.defaultAllow ? "Allow Tailscale until a network is blocked" : "Hold Tailscale down until a network is trusted"
            checked: root.defaultAllow
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.cursor === 1
            onClicked: root.toggleDefault()
          }

          Item { width: 1; height: Style.space(12) }
          PanelSeparator { width: parent.width; foreground: root.foreground }
          Item { width: 1; height: Style.space(8) }

          PanelSectionHeader {
            width: parent.width
            text: "Trusted"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            visible: root.safeNets.length === 0
            topPadding: Style.space(4)
            bottomPadding: Style.space(8)
            text: "None yet. Allow the current network to add it."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.safeNets
            Item {
              width: mainColumn.width
              height: Style.space(26)
              readonly property int rowIndex: 2 + index
              readonly property bool hot: (root.cursorActive && root.cursor === rowIndex) || mouse.containsMouse

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: parent.hot ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  root.cursor = parent.rowIndex
                  root.cursorActive = true
                }
              }

              Text {
                anchors.left: parent.left
                anchors.right: forgetBtn.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: String(modelData)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              PanelActionButton {
                id: forgetBtn
                z: 1
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "×"
                tooltipText: "Forget"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.forgetName(String(modelData))
              }
            }
          }

          Item { width: 1; height: Style.space(8) }
          PanelSectionHeader {
            width: parent.width
            text: "Blocked"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            visible: root.unsafeNets.length === 0
            topPadding: Style.space(4)
            text: "None. Unknown networks are still held down."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.unsafeNets
            Item {
              width: mainColumn.width
              height: Style.space(26)
              readonly property int rowIndex: 2 + root.safeNets.length + index
              readonly property bool hot: (root.cursorActive && root.cursor === rowIndex) || mouse.containsMouse

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: parent.hot ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  root.cursor = parent.rowIndex
                  root.cursorActive = true
                }
              }

              Text {
                anchors.left: parent.left
                anchors.right: forgetUnsafe.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: String(modelData)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              PanelActionButton {
                id: forgetUnsafe
                z: 1
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "×"
                tooltipText: "Forget"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.forgetName(String(modelData))
              }
            }
          }
        }
      }
    }
  }
}
