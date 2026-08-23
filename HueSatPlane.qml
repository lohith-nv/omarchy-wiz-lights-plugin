import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property real hue: 30
  property real sat: 1
  property int planeRadius: Math.max(Style.space(4), Style.cornerRadius)
  readonly property color planeBorder: Qt.rgba(
    Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.45)
  signal moved(real h, real s)
  signal released(real h, real s)

  implicitHeight: Style.space(64)

  onHueChanged: refreshMarker()
  onSatChanged: refreshMarker()
  Component.onCompleted: refreshMarker()

  function refreshMarker() {
    var rgb = Model.hsvToRgb(hue, sat, 1)
    marker.color = Qt.rgba(rgb.r / 255, rgb.g / 255, rgb.b / 255, 1)
  }

  function markerLeft() {
    var half = markerOuter.width / 2
    var inset = half * 0.65
    var center = Math.max(inset, Math.min(width - inset, (hue / 360) * width))
    return center - half
  }

  function markerTop() {
    var half = markerOuter.height / 2
    var inset = half * 0.65
    var center = Math.max(inset, Math.min(height - inset, sat * height))
    return center - half
  }

  function applyPosition(x, y) {
    var fx = Math.max(0, Math.min(1, x / Math.max(1, width)))
    var fy = Math.max(0, Math.min(1, y / Math.max(1, height)))
    hue = fx * 360
    sat = fy
  }

  Canvas {
    id: plane
    anchors.fill: parent
    antialiasing: true

    Component.onCompleted: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      plane.roundedPath(ctx, 0, 0, width, height, root.planeRadius)
      ctx.save()
      ctx.clip()

      var rainbow = ctx.createLinearGradient(0, 0, width, 0)
      rainbow.addColorStop(0.000, "#ff0000")
      rainbow.addColorStop(0.167, "#ffff00")
      rainbow.addColorStop(0.333, "#00ff00")
      rainbow.addColorStop(0.500, "#00ffff")
      rainbow.addColorStop(0.667, "#0000ff")
      rainbow.addColorStop(0.833, "#ff00ff")
      rainbow.addColorStop(1.000, "#ff0000")
      ctx.fillStyle = rainbow
      ctx.fillRect(0, 0, width, height)

      var fade = ctx.createLinearGradient(0, 0, 0, height)
      fade.addColorStop(0, "#ffffffff")
      fade.addColorStop(1, "#00ffffff")
      ctx.fillStyle = fade
      ctx.fillRect(0, 0, width, height)

      ctx.restore()
    }

    function roundedPath(ctx, x, y, w, h, r) {
      r = Math.min(r, w / 2, h / 2)
      ctx.beginPath()
      ctx.moveTo(x + r, y)
      ctx.lineTo(x + w - r, y)
      ctx.arcTo(x + w, y, x + w, y + r, r)
      ctx.lineTo(x + w, y + h - r)
      ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
      ctx.lineTo(x + r, y + h)
      ctx.arcTo(x, y + h, x, y + h - r, r)
      ctx.lineTo(x, y + r)
      ctx.arcTo(x, y, x + r, y, r)
      ctx.closePath()
    }
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: root.planeRadius
    border.color: root.planeBorder
    border.width: Style.normalBorderWidth
  }

  Rectangle {
    id: markerOuter
    width: Style.space(17)
    height: width
    radius: width / 2
    color: "transparent"
    border.color: Qt.rgba(0, 0, 0, 0.55)
    border.width: 3
    x: root.markerLeft()
    y: root.markerTop()

    Rectangle {
      id: marker
      anchors.centerIn: parent
      width: parent.width - Style.space(4)
      height: width
      radius: width / 2
      border.color: "#ffffff"
      border.width: 2
      color: "#ffffff"
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor

    onPressed: function(mouse) {
      root.applyPosition(mouse.x, mouse.y)
      root.moved(root.hue, root.sat)
    }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      root.applyPosition(mouse.x, mouse.y)
      root.moved(root.hue, root.sat)
    }
    onReleased: function(mouse) {
      root.applyPosition(mouse.x, mouse.y)
      root.released(root.hue, root.sat)
    }
  }
}
