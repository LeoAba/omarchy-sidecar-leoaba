import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// iPad as a second display. The streaming work happens in the
// `omarchy-sidecar` CLI (a detached process); this widget only starts/stops
// it and mirrors its state file, so a shell restart never drops a session.
Panel {
  id: root
  moduleName: "leoaba.sidecar"
  ipcTarget: "sidecar"
  //   omarchy-shell sidecar toggleConnection
  manageIpc: false

  // The sender ships inside this plugin folder (bin/omarchy-sidecar).
  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-sidecar")).replace(/^file:\/\//, ""))
  readonly property bool scanOnOpen: setting("scanOnOpen", true) === true

  // ------------------------------------------------------------------- state

  property var status: ({ state: "idle" })     // mirror of ~/.local/state/omarchy/sidecar.json
  property var devices: []                     // from `omarchy-sidecar list --json`
  property bool scanning: false
  property string quality: "balanced"          // sharp | balanced | light
  property string lastTarget: ""
  property string lastPanel: "2388x1668"       // iPad panel pixels, remembered from the last session

  // One line describing the selected quality: what is sent and how it looks.
  readonly property string qualitySpec: {
    var wh = String(status.panel || lastPanel).split("x")
    var f = quality === "sharp" ? 1.0 : quality === "balanced" ? 0.75 : 0.5
    var w = Math.floor(Number(wh[0]) * f / 2) * 2, h = Math.floor(Number(wh[1]) * f / 2) * 2
    var note = quality === "sharp" ? "native pixels · crispest"
             : quality === "balanced" ? "56% of the pixels · slightly soft"
             : "25% of the pixels · softest"
    return w + "×" + h + " sent · " + note
  }
  property bool prefsLoaded: false
  property bool editingHost: false
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property string st: String(status.state || "idle")
  readonly property bool active: st === "streaming" || st === "connecting" || st === "reconnecting" || st === "sleeping"
  readonly property bool streaming: st === "streaming"

  readonly property string glyphTablet: String.fromCodePoint(0xF04F6)    // md-tablet
  readonly property string glyphRefresh: String.fromCodePoint(0xF0450)   // md-restore
  readonly property string glyphClose: String.fromCodePoint(0xF0156)     // md-close
  readonly property string glyphLink: String.fromCodePoint(0xF0337)      // md-link
  readonly property string glyphIp: String.fromCodePoint(0xF0A5F)        // md-ip-network
  readonly property string glyphUsb: String.fromCodePoint(0xF0553)       // md-usb
  readonly property string glyphWifi: String.fromCodePoint(0xF05A9)      // md-wifi

  // "USB" | "Wi-Fi" | "" — what the live connection runs over.
  readonly property string transport: streaming ? String(status.transport || "") : ""
  // "2388×1668 · 59 fps" while streaming (encoded size; older senders only report the panel).
  readonly property string videoLine: {
    if (!streaming) return ""
    var size = String(status.video || status.panel || "").replace("x", "×")
    return (size ? size + " · " : "") + Math.round(status.fps || 0) + " fps"
  }

  readonly property string statusLine: {
    if (st === "streaming") return "Streaming · " + Number(status.mbps || 0).toFixed(1) + " Mbps"
    if (st === "connecting") return "Connecting…"
    if (st === "reconnecting") return "Reconnecting…"
    if (st === "sleeping") return "iPad locked — resumes on wake"
    if (st === "error") return "Error"
    return "Not connected"
  }

  onStatusChanged: {
    var pn = String(status.panel || "")
    if (prefsLoaded && /^[0-9]+x[0-9]+$/.test(pn) && pn !== lastPanel) { lastPanel = pn; savePrefs() }
  }

  // ---------------------------------------------------------------- controls

  function connectTo(target) {
    var t = String(target || "")
    lastTarget = t
    savePrefs()
    var cmd = [cli, "connect", "--background", "--quality", quality]
    if (t !== "") cmd.splice(2, 0, t)
    Quickshell.execDetached(cmd)
    status = { state: "connecting", device: t || "iPad" }
  }

  function disconnect() {
    Quickshell.execDetached([cli, "stop"])
  }

  function toggleConnection() {
    if (active) disconnect()
    else connectTo(lastTarget !== "" ? lastTarget : (devices.length > 0 ? devices[0].id : ""))
  }

  function scan() {
    if (scanning) return
    scanning = true
    listProcess.running = true
  }

  function setQuality(q) {
    quality = q
    savePrefs()
    if (active) Quickshell.execDetached([cli, "quality", q])  // live, no reconnect
  }

  function beginHostEntry() {
    editingHost = true
    Qt.callLater(function() {
      hostField.text = root.lastTarget.indexOf(".") !== -1 ? root.lastTarget : ""
      hostField.selectAll()
      hostField.forceActiveFocus()
    })
  }

  function cancelHostEntry() {
    editingHost = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitHostEntry() {
    var h = String(hostField.text || "").trim()
    if (h === "") return
    connectTo(h)
    cancelHostEntry()
  }

  // ---------------------------------------------------------- persistence

  function savePrefs() {
    if (!prefsLoaded) return
    prefsFile.setText(JSON.stringify({ quality: quality, lastTarget: lastTarget, lastPanel: lastPanel }, null, 2) + "\n")
  }

  function loadPrefs(raw) {
    if (prefsLoaded) return
    var p = {}
    try { p = JSON.parse(raw || "{}") || {} } catch (e) { p = {} }
    if (p.quality === "sharp" || p.quality === "balanced" || p.quality === "light") quality = p.quality
    lastTarget = String(p.lastTarget || "")
    if (/^[0-9]+x[0-9]+$/.test(String(p.lastPanel || ""))) lastPanel = p.lastPanel
    prefsLoaded = true
  }

  FileView {
    id: prefsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/sidecar-ui.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadPrefs(text())
    onLoadFailed: root.loadPrefs("")
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/sidecar.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.status = JSON.parse(text()) || { state: "idle" } } catch (e) { }
    }
    onLoadFailed: root.status = { state: "idle" }
  }

  // The state file can't report a crashed sender; `status` checks the pid.
  Process {
    id: statusProcess
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { var s = JSON.parse(text); if (s && s.state === "idle" && root.active) root.status = s } catch (e) { }
      }
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.active
    onTriggered: statusProcess.running = true
  }

  Process {
    id: listProcess
    command: [root.cli, "list", "--json", "--timeout", "3"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.devices = JSON.parse(text) || [] } catch (e) { root.devices = [] }
      }
    }
    onExited: root.scanning = false
  }

  // --------------------------------------------------------------------- ipc

  IpcHandler {
    target: "sidecar"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(target: string): void { root.connectTo(target) }
    function disconnect(): void { root.disconnect() }
    function toggleConnection(): void { root.toggleConnection() }
    function scan(): void { root.scan() }
    function status(): string { return root.st + (root.status.device ? " " + root.status.device : "") }
  }

  // ------------------------------------------------------------- bar button

  onOpenedChanged: {
    cursorActive = false
    cursorIndex = 0
    editingHost = false
    if (opened && scanOnOpen) scan()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyphTablet
    dimmed: !root.active
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleConnection()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------------ popup

  // Keyboard cursor order: connect/disconnect, quality ×3, host entry, rescan, devices.
  readonly property var actions: {
    var list = [
      function() { root.toggleConnection() },
      function() { root.setQuality("sharp") },
      function() { root.setQuality("balanced") },
      function() { root.setQuality("light") },
      function() { root.beginHostEntry() },
      function() { root.scan() }
    ]
    for (var i = 0; i < devices.length; i++) {
      (function(d) { list.push(function() { root.connectTo(d.id || d.name) }) })(devices[i])
    }
    return list
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingHost
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        var n = root.actions.length
        root.cursorIndex = (root.cursorIndex + (dx !== 0 ? dx : dy) + n) % n
      }
      onActivateRequested: {
        if (root.cursorActive) root.actions[root.cursorIndex]()
        else root.toggleConnection()
      }
      onTextKey: function(t) {
        if (t === "r") root.scan()
        else if (t === "i") root.beginHostEntry()
        else if (t === "d") root.disconnect()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: tablet glyph · device/status · on/off switch ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.glyphTablet
            color: root.bar.foreground
            opacity: root.active ? 1 : 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          // Same on/off switch as the built-in panels; it is cursor slot 0.
          ToggleSwitch {
            id: powerSwitch
            checked: root.active
            busy: root.st === "connecting" || root.st === "reconnecting"
            hasCursor: root.cursorActive && root.cursorIndex === 0
            foreground: root.bar.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onHovered: function(on) { if (on) { root.cursorActive = true; root.cursorIndex = 0 } }
            onToggled: root.toggleConnection()

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: root.active ? "Disconnect the iPad" : "Connect " + (root.lastTarget ? "the last iPad" : "an iPad")
              fontFamily: root.bar.fontFamily
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: powerSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              textFormat: Text.PlainText
              text: root.active && root.status.device ? String(root.status.device) : "iPad display"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              // Transport badge: which link the stream rides on.
              Rectangle {
                id: transportBadge
                visible: root.transport !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: badgeLabel.implicitWidth + Style.space(10)
                height: badgeLabel.implicitHeight + Style.space(2)
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: root.bar.foreground

                Text {
                  id: badgeLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: (root.transport === "USB" ? root.glyphUsb : root.glyphWifi) + " " + root.transport.toUpperCase()
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.statusLine.toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width - (transportBadge.visible ? transportBadge.width + parent.spacing : 0)
              }
            }

            // Live resolution and frame rate, quiet third line.
            Text {
              visible: root.videoLine !== ""
              textFormat: Text.PlainText
              text: root.videoLine
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              visible: root.st === "error" && !!root.status.message
              textFormat: Text.PlainText
              text: String(root.status.message || "")
              color: root.bar.foreground
              opacity: 0.7
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Quality ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "QUALITY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: qualityRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 2) / 3

            ActionButton { index: 1; width: qualityRow.cellWidth; text: "Sharp"; active: root.quality === "sharp" }
            ActionButton { index: 2; width: qualityRow.cellWidth; text: "Balanced"; active: root.quality === "balanced" }
            ActionButton { index: 3; width: qualityRow.cellWidth; text: "Light"; active: root.quality === "light" }
          }

          Text {
            textFormat: Text.PlainText
            text: root.qualitySpec
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Devices ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(devHeader.implicitHeight, devButtons.implicitHeight)

            PanelSectionHeader {
              id: devHeader
              text: root.scanning ? "LOOKING FOR IPADS…" : "IPADS ON THIS NETWORK"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              id: devButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              readonly property real cellWidth: Math.max(ipButton.implicitWidth, rescanButton.implicitWidth)
              ActionButton { id: ipButton; index: 4; width: devButtons.cellWidth; iconText: root.glyphIp; text: "By IP"; active: root.editingHost }
              ActionButton { id: rescanButton; index: 5; width: devButtons.cellWidth; iconText: root.glyphRefresh; text: "Rescan" }
            }
          }

          Text {
            visible: root.devices.length === 0 && !root.scanning
            textFormat: Text.PlainText
            text: "None found. Open OpenDisplay on the iPad (same Wi-Fi), or connect by IP."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Repeater {
            model: root.devices
            DeviceRow {
              required property var modelData
              required property int index
              width: parent.width
              dev: modelData
              rowIndex: 6 + index
            }
          }

          Row {
            visible: root.editingHost
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: hostField
              width: Style.space(180)
              placeholderText: "192.168.1.20 or 100.x.y.z"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelHostEntry()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitHostEntry()
                  event.accepted = true
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "Enter to connect · Esc"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }
    }
  }

  // Borderless, two-line device row in the style of the Bluetooth panel.
  component DeviceRow: CursorSurface {
    id: row
    required property var dev
    required property int rowIndex
    readonly property bool isCurrent: root.active && (root.status.id === dev.id || root.status.device === dev.name)

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: isCurrent
    foreground: root.bar.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursorIndex = row.rowIndex }
      onClicked: root.actions[row.rowIndex]()
    }

    PanelToolTip {
      visible: rowMouse.containsMouse
      text: row.isCurrent ? "Connected" : "Connect"
      fontFamily: root.bar.fontFamily
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(devIcon.implicitHeight, devInfo.implicitHeight)

      Text {
        id: devIcon
        textFormat: Text.PlainText
        text: root.glyphTablet
        color: row.isCurrent ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.heading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: devInfo
        spacing: Style.space(1)
        anchors.left: devIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: String(row.dev.name || "iPad")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          textFormat: Text.PlainText
          text: (row.isCurrent ? "Connected · " : "") + String((row.dev.addresses || [])[0] || "")
          color: row.isCurrent ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }
  }

  component ActionButton: Button {
    property int index: 0
    iconSize: Style.font.title
    fontSize: Style.font.bodySmall
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true
    hasCursor: root.cursorActive && root.cursorIndex === index
    onClicked: root.actions[index]()
    onHovered: function(h) {
      if (h) {
        root.cursorActive = true
        root.cursorIndex = index
      }
    }
  }
}
