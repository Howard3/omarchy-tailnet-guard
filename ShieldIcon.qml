import QtQuick
import qs.Commons

// Small shield badge for the bar. A slash means Tailscale is being held down.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool heldDown: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real cx: width / 2
  readonly property real bodyW: width * 0.58
  readonly property real bodyH: height * 0.46

  Rectangle {
    id: body
    width: root.bodyW
    height: root.bodyH
    radius: width * 0.22
    color: root.color
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.height * 0.14
  }

  Rectangle {
    width: root.bodyW * 0.72
    height: root.bodyW * 0.72
    rotation: 45
    color: root.color
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: body.bottom
    anchors.topMargin: -width * 0.46
  }

  Rectangle {
    visible: root.heldDown
    anchors.centerIn: parent
    width: parent.width * 1.18
    height: Math.max(2, parent.height * 0.13)
    radius: height / 2
    color: root.color
    rotation: -45
  }
}
