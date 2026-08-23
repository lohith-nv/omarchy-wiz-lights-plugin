import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "kshatriya-abhay.wiz-lights"
  ipcTarget: "kshatriya-abhay.wiz-lights"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var counts: Model.countOn(service.lights)
  property string expandedMac: ""
  property string editingMac: ""
  property var uiState: ({})

  function uiGet(mac, key, fallback) {
    var entry = uiState[String(mac)]
    var value = entry ? entry[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function uiSet(mac, key, value) {
    var entry = Object.assign({}, uiState[String(mac)] || {})
    entry[key] = value
    var next = Object.assign({}, uiState)
    next[String(mac)] = entry
    uiState = next
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function openAndLoad() {
    root.open()
    if (service.lights.length === 0 && !service.scanning) service.scan()
    else service.refresh()
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  onOpenedChanged: if (opened) {
    service.refresh()
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  function toggleLight(index) {
    var light = service.lights[index]
    if (!light || !light.reachable || light.pending || service.busy) return
    var turnOn = !light.state
    var updated = service.lights.slice()
    updated[index] = Object.assign({}, light, { state: turnOn, pending: true })
    service.lights = updated
    service.setPower(light.ip, turnOn, function(parsed, exitCode) {
      if (exitCode !== 0) {
        for (var i = 0; i < service.lights.length; i++) {
          if (service.lights[i].mac === light.mac && service.lights[i].pending) {
            var reverted = service.lights.slice()
            reverted[i] = Object.assign({}, reverted[i], { state: !turnOn, pending: false })
            service.lights = reverted
            break
          }
        }
      }
      service.refresh()
    })
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    fixedWidth: vertical ? -1 : content.implicitWidth + Style.space(16)
    tooltipText: "WiZ Lights · " + root.counts.on + "/" + root.counts.total + " on"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) service.scan()
      else root.openAndLoad()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      Image {
        visible: !(bar ? bar.vertical : false)
        width: Style.space(13)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        source: Qt.resolvedUrl("bulb.svg")
        sourceSize: Qt.size(26, 26)
        layer.enabled: true
        layer.effect: MultiEffect {
          colorization: 1
          colorizationColor: root.counts.on > 0 ? root.foreground : root.dim
        }
      }

      Text {
        visible: !(bar ? bar.vertical : false)
        anchors.verticalCenter: parent.verticalCenter
        text: root.counts.total > 0 ? (root.counts.on + "/" + root.counts.total) : "—"
        color: root.counts.on > 0 ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        visible: bar ? bar.vertical : false
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.counts.on)
        color: root.counts.on > 0 ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(text) {
        if (text === "r" || text === "R") service.scan()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scroll.contentItem
          property: "interactive"
          value: body.implicitHeight > scroll.height
        }

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "WiZ Lights"
            meta: service.scanning
                  ? "Scanning network…"
                  : (root.counts.total > 0
                     ? root.counts.on + " of " + root.counts.total + " on"
                     : "No bulbs found")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Image {
                width: Style.font.display
                height: width
                source: Qt.resolvedUrl("bulb.svg")
                sourceSize: Qt.size(48, 48)
                layer.enabled: true
                layer.effect: MultiEffect {
                  colorization: 1
                  colorizationColor: root.foreground
                }
              }
            }
          }

          Text {
            visible: service.lastError !== ""
            width: parent.width
            text: service.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !service.scanning && service.lights.length === 0 && service.lastError === ""
            width: parent.width
            text: "No bulbs saved yet. Press R or the scan button to search your local network."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Repeater {
            model: service.lights

            delegate: ColumnLayout {
              id: row
              required property var modelData
              required property int index
              width: body.width
              spacing: Style.space(8)

              readonly property bool expanded: root.expandedMac === String(modelData.mac)
              readonly property bool editing: root.editingMac === String(modelData.mac)
              readonly property bool pending: !!modelData.pending
              readonly property bool onState: !!modelData.state && modelData.reachable
              readonly property string bulbMode: String(modelData.mode || "") === "color"
                                                 ? "color"
                                                 : (modelData.temp ? "temp" : "")
              readonly property color knobColor: Color.popups.background
              readonly property string metaText: {
                if (!modelData.reachable) return "offline · " + String(modelData.ip || "")
                var module = String(modelData.moduleName || "")
                var meta = Model.metaText(modelData)
                return module !== "" ? module + " · " + meta : meta
              }

              function seedDimming() {
                var d = Number(modelData.dimming)
                if (!isFinite(d) || d <= 0) d = 100
                return Math.max(0, Math.min(100, d))
              }
              function seedTemp() {
                var t = Number(modelData.temp)
                if (!isFinite(t)) t = 2700
                return Math.max(2200, Math.min(6500, t))
              }
              function seedHue() {
                var rgb = modelData.rgb
                if (rgb && typeof rgb.length === "number" && rgb.length >= 3) {
                  return Math.round(Model.rgbToHsv(rgb[0], rgb[1], rgb[2]).h)
                }
                return 35
              }
              function seedSat() {
                var rgb = modelData.rgb
                if (rgb && typeof rgb.length === "number" && rgb.length >= 3) {
                  return Math.round(Model.rgbToHsv(rgb[0], rgb[1], rgb[2]).s * 100)
                }
                return 100
              }
              function sendRgb() {
                var rgb = Model.hsvToRgb(colorPlane.hue, colorPlane.sat, 1)
                var hex = Model.rgbToHex(rgb.r, rgb.g, rgb.b).toUpperCase()
                service.setHex(String(row.modelData.ip), hex, function(parsed, exitCode) {
                  if (exitCode !== 0 || (parsed && parsed.ok !== true)) {
                    service.lastError = parsed && parsed.error ? parsed.error : "failed to set color"
                  }
                  service.refresh()
                })
              }
              function reportFailure(parsed, exitCode, fallback) {
                if (exitCode !== 0 || (parsed && parsed.ok !== true)) {
                  service.lastError = parsed && parsed.error ? parsed.error : fallback
                }
                service.refresh()
              }

              RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(4)
                Layout.bottomMargin: Style.space(4)
                spacing: Style.space(10)

                MouseArea {
                  id: rowClick
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.expandedMac = row.expanded ? "" : String(row.modelData.mac)
                    if (root.expandedMac !== "") service.hold(1500)
                  }

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(6)

                    Text {
                      Layout.alignment: Qt.AlignVCenter
                      text: row.expanded ? "▾" : "▸"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(2)

                      Text {
                        Layout.fillWidth: true
                        text: row.modelData.name || "WiZ Light"
                        color: row.modelData.reachable ? root.foreground : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        Layout.fillWidth: true
                        text: row.metaText
                        color: row.modelData.reachable ? root.dim : root.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                PanelActionButton {
                  id: renameButton
                  iconText: "✎"
                  tooltipText: "Rename bulb"
                  visible: row.expanded && !row.editing
                  size: Style.space(30)
                  fontSize: Style.font.heading
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  enabled: !row.editing
                  onClicked: root.editingMac = String(row.modelData.mac)
                }

                Rectangle {
                  id: toggle
                  Layout.alignment: Qt.AlignVCenter
                  width: Style.space(40)
                  height: Style.space(22)
                  radius: height / 2
                  opacity: row.modelData.reachable && !row.pending ? 1.0 : 0.4
                  color: row.onState
                        ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.85)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

                  Behavior on color { ColorAnimation { duration: 90 } }
                  Behavior on opacity { NumberAnimation { duration: 90 } }

                  Rectangle {
                    width: parent.height - Style.space(4)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: row.onState ? parent.width - width - Style.space(2) : Style.space(2)
                    color: row.onState ? row.knobColor : root.foreground

                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 90 } }
                  }

                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    cursorShape: row.modelData.reachable && !row.pending ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                    onClicked: root.toggleLight(row.index)
                  }
                }
              }

              TextField {
                id: renameField
                Layout.fillWidth: true
                visible: row.editing
                text: row.modelData.name || ""
                placeholderText: "Bulb name"
                foreground: root.foreground
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(2)
                onAccepted: commit()
                onVisibleChanged: if (visible) {
                  selectAll()
                  forceActiveFocus()
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.editingMac = ""
                    event.accepted = true
                  }
                }
                function commit() {
                  var name = text.trim()
                  root.editingMac = ""
                  if (name === "" || name === String(row.modelData.name || "")) return
                  var mac = String(row.modelData.mac)
                  service.rename(mac, name, function(parsed, exitCode) {
                    row.reportFailure(parsed, exitCode, "rename failed")
                  })
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Style.space(14)
                visible: row.expanded
                opacity: row.modelData.reachable ? 1.0 : 0.35
                spacing: Style.space(10)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    Layout.preferredWidth: Style.space(64)
                    text: "Brightness"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  PanelSlider {
                    id: brightSlider
                    Layout.fillWidth: true
                    minimum: 0
                    maximum: 100
                    step: 1
                    integer: true
                    bar: root.bar
                    value: row.seedDimming()

                    onMoved: function(v) {
                      value = v
                      service.hold(2500)
                      brightTimer.restart()
                    }
                    onReleased: function(v) {
                      value = v
                      brightTimer.stop()
                      service.setBright(String(row.modelData.ip), Math.round(v), function(parsed, exitCode) {
                        row.reportFailure(parsed, exitCode, "failed to set brightness")
                      })
                    }

                    Timer {
                      id: brightTimer
                      interval: 200
                      onTriggered: service.setBright(String(row.modelData.ip), Math.round(brightSlider.value), function(parsed, exitCode) {
                        row.reportFailure(parsed, exitCode, "failed to set brightness")
                      })
                    }
                  }

                  Text {
                    Layout.preferredWidth: Style.space(38)
                    text: Math.round(brightSlider.value) + "%"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignRight
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)
                  opacity: row.bulbMode === "temp" ? 1.0 : 0.45

                  Behavior on opacity { NumberAnimation { duration: 120 } }

                  Text {
                    Layout.preferredWidth: Style.space(64)
                    text: "Warm/Cool"
                    color: row.bulbMode === "temp" ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: row.bulbMode === "temp"
                  }

                  GradientSlider {
                    id: tempSlider
                    Layout.fillWidth: true
                    minimum: 2200
                    maximum: 6500
                    value: root.uiGet(String(row.modelData.mac), "temp", row.seedTemp())
                    stops: [
                      { p: 0.0, c: "#ffa564" },
                      { p: 0.5, c: "#ffffff" },
                      { p: 1.0, c: "#bcd4ff" }
                    ]

                    onMoved: function(v) {
                      value = v
                      root.uiSet(String(row.modelData.mac), "temp", Math.round(v))
                      service.hold(2500)
                      tempTimer.restart()
                    }
                    onReleased: function(v) {
                      value = v
                      tempTimer.stop()
                      service.setTemp(String(row.modelData.ip), Math.round(v / 50) * 50, function(parsed, exitCode) {
                        row.reportFailure(parsed, exitCode, "failed to set temperature")
                      })
                    }

                    Timer {
                      id: tempTimer
                      interval: 200
                      onTriggered: service.setTemp(String(row.modelData.ip), Math.round(tempSlider.value / 50) * 50, function(parsed, exitCode) {
                        row.reportFailure(parsed, exitCode, "failed to set temperature")
                      })
                    }
                  }

                  Text {
                    Layout.preferredWidth: Style.space(38)
                    text: Math.round(tempSlider.value) + "K"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignRight
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)
                  opacity: row.bulbMode === "color" ? 1.0 : 0.45

                  Behavior on opacity { NumberAnimation { duration: 120 } }

                  Text {
                    Layout.preferredWidth: Style.space(64)
                    Layout.alignment: Qt.AlignVCenter
                    text: "Color"
                    color: row.bulbMode === "color" ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: row.bulbMode === "color"
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(4)

                    HueSatPlane {
                      id: colorPlane
                      Layout.fillWidth: true
                      hue: root.uiGet(String(row.modelData.mac), "hue", row.seedHue())
                      sat: root.uiGet(String(row.modelData.mac), "sat", row.seedSat()) / 100

                      onMoved: function(h, s) {
                        var mac = String(row.modelData.mac)
                        root.uiSet(mac, "hue", Math.round(h))
                        root.uiSet(mac, "sat", Math.round(s * 100))
                        service.hold(2500)
                        colorTimer.restart()
                      }
                      onReleased: function(h, s) {
                        colorTimer.stop()
                        row.sendRgb()
                      }

                      Timer {
                        id: colorTimer
                        interval: 200
                        onTriggered: row.sendRgb()
                      }
                    }

                    Text {
                      Layout.alignment: Qt.AlignRight
                      property var rgbValue: Model.hsvToRgb(colorPlane.hue, colorPlane.sat, 1)
                      text: Model.rgbToHex(rgbValue.r, rgbValue.g, rgbValue.b).toUpperCase()
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  PresetButton {
                    Layout.fillWidth: true
                    label: "White"
                    onChosen: {
                      var mac = String(row.modelData.mac)
                      root.uiSet(mac, "temp", 6500)
                      tempSlider.value = 6500
                      service.setTemp(String(row.modelData.ip), 6500, function(parsed, exitCode) {
                        row.reportFailure(parsed, exitCode, "failed to set white")
                      })
                    }
                  }

                  PresetButton {
                    Layout.fillWidth: true
                    label: "Warm"
                    onChosen: {
                      var mac = String(row.modelData.mac)
                      root.uiSet(mac, "hue", 45)
                      root.uiSet(mac, "temp", 2700)
                      colorPlane.hue = 45
                      tempSlider.value = 2700
                      service.setTemp(String(row.modelData.ip), 2700, function(parsed, exitCode) {
                        row.reportFailure(parsed, exitCode, "failed to set warm light")
                      })
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            PanelActionButton {
              iconText: service.scanning ? "…" : "⌕"
              tooltipText: "Scan network for WiZ bulbs (R)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !service.scanning
              onClicked: service.scan()
            }

            Item { Layout.fillWidth: true }

            Text {
              text: service.lastUpdated.getTime() > 0
                    ? "updated " + Qt.formatTime(service.lastUpdated, "HH:mm:ss")
                    : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  component PresetButton: Rectangle {
    id: pb
    property string label: ""
    signal chosen()
    implicitHeight: Style.space(28)
    radius: Math.max(Style.space(4), Style.cornerRadius)
    color: pbArea.containsMouse
           ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
           : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
    border.width: Style.normalBorderWidth

    Behavior on color { ColorAnimation { duration: 80 } }

    Text {
      anchors.centerIn: parent
      text: pb.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      id: pbArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pb.chosen()
    }
  }

  component GradientSlider: Item {
    id: gs
    property real minimum: 0
    property real maximum: 1
    property real value: 50
    property var stops: []
    readonly property real fraction: maximum > minimum ? Math.max(0, Math.min(1, (value - minimum) / (maximum - minimum))) : 0
    signal moved(real val)
    signal released(real val)
    implicitHeight: Style.space(20)

    onValueChanged: canvas.requestPaint()
    onStopsChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()

    Canvas {
      id: canvas
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: Style.space(5)
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        if (!gs.stops || gs.stops.length < 2) return
        var gradient = ctx.createLinearGradient(0, 0, width, 0)
        for (var i = 0; i < gs.stops.length; i++) {
          gradient.addColorStop(gs.stops[i].p, String(gs.stops[i].c))
        }
        ctx.fillStyle = gradient
        ctx.fillRect(0, 0, width, height)
      }
    }

    Rectangle {
      width: Style.space(13)
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      x: (parent.width - width) * gs.fraction
      color: gs.stops && gs.stops.length > 1 ? gs.colorAt(gs.fraction) : root.foreground
      border.color: root.foreground
      border.width: 1

      Behavior on x { NumberAnimation { duration: 30 } }
    }

    function colorAt(fraction) {
      for (var i = 1; i < stops.length; i++) {
        if (fraction <= stops[i].p) {
          var a = stops[i - 1]
          var b = stops[i]
          var span = b.p - a.p
          var t = span > 0 ? (fraction - a.p) / span : 0
          var ca = Qt.color(String(a.c))
          var cb = Qt.color(String(b.c))
          return Qt.rgba(
            ca.r + (cb.r - ca.r) * t,
            ca.g + (cb.g - ca.g) * t,
            ca.b + (cb.b - ca.b) * t,
            1)
        }
      }
      return String(stops[stops.length - 1].c)
    }

    function valueFromX(x) {
      var f = Math.max(0, Math.min(1, x / Math.max(1, width)))
      return minimum + f * (maximum - minimum)
    }

    MouseArea {
      id: area
      anchors.fill: parent
      anchors.margins: -Style.space(6)
      cursorShape: Qt.PointingHandCursor
      onPressed: function(mouse) {
        var v = valueFromX(mouse.x + area.anchors.leftMargin)
        gs.value = v
        gs.moved(v)
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var v = valueFromX(mouse.x + area.anchors.leftMargin)
        gs.value = v
        gs.moved(v)
      }
      onReleased: function(mouse) {
        gs.released(valueFromX(mouse.x + area.anchors.leftMargin))
      }
    }
  }
}
