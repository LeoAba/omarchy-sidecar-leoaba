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
  readonly property string authorUrl: "https://linktr.ee/leoaba"
  // First use: `omarchy plugin add` only clones, so the widget runs ./setup
  // (packages, touch helper) in a terminal the first time it is used.
  readonly property string setupScript: decodeURIComponent(String(Qt.resolvedUrl("setup")).replace(/^file:\/\//, ""))
  property bool needsSetup: false
  property bool setupRunning: false
  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-sidecar")).replace(/^file:\/\//, ""))
  readonly property bool scanOnOpen: setting("scanOnOpen", true) === true

  // ------------------------------------------------------------------- state

  property var status: ({ state: "idle" })     // mirror of ~/.local/state/omarchy/sidecar.json
  property var devices: []                     // from `omarchy-sidecar list --json`
  property bool scanning: false
  property string quality: "balanced"          // sharp | balanced | light
  property string lastTarget: ""
  property bool usbOnly: false                 // never connect over Wi-Fi (for untrusted networks)
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

  readonly property string glyphRefresh: String.fromCodePoint(0xF0450)   // md-restore
  readonly property string glyphClose: String.fromCodePoint(0xF0156)     // md-close
  readonly property string glyphLink: String.fromCodePoint(0xF0337)      // md-link
  readonly property string glyphIp: String.fromCodePoint(0xF0A5F)        // md-ip-network
  readonly property string glyphUsb: String.fromCodePoint(0xF0553)       // md-usb
  readonly property string glyphWifi: String.fromCodePoint(0xF05A9)      // md-wifi

  // "USB" | "Wi-Fi" | "" — what the live connection runs over.
  readonly property string transport: streaming ? String(status.transport || "") : ""
  // Details under the connected device: "Streaming · 1194×834 · 40 fps · 0.3 Mbps".
  readonly property string statusLine: {
    if (st === "streaming") {
      var size = String(status.video || status.panel || "").replace("x", "×")
      return "Streaming · " + (size ? size + " · " : "") + Math.round(status.fps || 0) + " fps · "
        + Number(status.mbps || 0).toFixed(1) + " Mbps"
    }
    if (st === "connecting") return "Connecting…"
    if (st === "reconnecting") return "Reconnecting…"
    if (st === "sleeping") return "Locked — resumes on wake"
    return ""
  }

  // A friendly name for the connected device. While connecting the state file can
  // hold the raw target (a UUID or an IP), which must never be shown as a name.
  readonly property string deviceName: {
    var d = String(status.device || "")
    var looksRaw = /^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(d) || /^[0-9.:\[\]]+$/.test(d)
    if (d !== "" && !looksRaw) return d
    for (var i = 0; i < devices.length; i++)
      if (devices[i].id && devices[i].id === status.id) return String(devices[i].name)
    return "iPad"
  }

  function isConnectedDevice(d) {
    return active && ((d.id && d.id === status.id) || (!d.id && d.name === status.device))
  }
  readonly property var otherDevices: devices.filter(function(d) { return !root.isConnectedDevice(d) })

  // The quirky line under the title; a new pick each time the panel opens.
  property int quipSeed: 0
  readonly property var quips: ({
    idle: ["Your iPad, but make it a monitor", "Two screens are better than one", "Room for one more screen"],
    connecting: ["Shaking hands with the iPad…"],
    reconnecting: ["Finding the iPad again…"],
    streaming: ["Now in two places at once", "Your desktop grew an iPad", "More room to think"],
    sleeping: ["The iPad is napping"],
    error: ["Something went sideways"]
  })
  readonly property string quip: {
    if (needsSetup) return setupRunning ? "Setting things up…" : "One click to finish setup"
    var list = quips[st] || quips.idle
    return list[quipSeed % list.length]
  }

  onStatusChanged: {
    var pn = String(status.panel || "")
    if (prefsLoaded && /^[0-9]+x[0-9]+$/.test(pn) && pn !== lastPanel) { lastPanel = pn; savePrefs() }
  }

  // ---------------------------------------------------------------- controls

  function runSetup() {
    setupRunning = true
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", setupScript])
  }

  // `trust` is set when the user explicitly picks an iPad from the list: it
  // (re)pins that iPad to its current address. Quick-connect never re-pins.
  function connectTo(target, trust) {
    if (needsSetup) { runSetup(); return }
    var t = String(target || "")
    lastTarget = t
    savePrefs()
    var cmd = [cli, "connect", "--background", "--quality", quality]
    if (usbOnly) cmd.push("--usb")
    if (trust) cmd.push("--trust")
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
    // Only an IP address or hostname, optionally with :port — never a path.
    if (!/^(\[[0-9A-Fa-f:.]+\]|[0-9A-Fa-f:.]+|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)(:[0-9]+)?$/.test(h)) {
      hostField.text = ""
      return
    }
    connectTo(h)
    cancelHostEntry()
  }

  // ---------------------------------------------------------- persistence

  function savePrefs() {
    if (!prefsLoaded) return
    prefsFile.setText(JSON.stringify({ quality: quality, lastTarget: lastTarget, lastPanel: lastPanel, usbOnly: usbOnly }, null, 2) + "\n")
  }

  function loadPrefs(raw) {
    if (prefsLoaded) return
    var p = {}
    try { p = JSON.parse(raw || "{}") || {} } catch (e) { p = {} }
    if (p.quality === "sharp" || p.quality === "balanced" || p.quality === "light") quality = p.quality
    lastTarget = String(p.lastTarget || "")
    usbOnly = p.usbOnly === true
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
    id: checkProcess
    command: [root.cli, "check"]
    onExited: function(code) {
      root.needsSetup = code !== 0
      if (!root.needsSetup) root.setupRunning = false
    }
  }
  Component.onCompleted: checkProcess.running = true

  // While setup runs in its terminal, notice when it has finished.
  Timer {
    interval: 3000
    repeat: true
    running: root.needsSetup && root.setupRunning
    onTriggered: checkProcess.running = true
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
    if (opened) { quipSeed = Math.floor(Math.random() * 1000); checkProcess.running = true }
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
    // Solid gray when idle, full colour while connected.
    iconComponent: Component {
      Item {
        IPadIcon {
          anchors.centerIn: parent
          iconSize: Style.space(14)
          color: root.active ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.55)
        }
      }
    }
    tooltipText: ""
    onPressed: function(b) {
      if (root.needsSetup) root.runSetup()
      else if (b === Qt.RightButton) root.toggleConnection()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------------ popup

  // Keyboard cursor order: connect/disconnect, quality ×3, host entry, rescan, USB-C only, devices.
  readonly property var actions: {
    var list = [
      function() { root.toggleConnection() },
      function() { root.setQuality("sharp") },
      function() { root.setQuality("balanced") },
      function() { root.setQuality("light") },
      function() { root.beginHostEntry() },
      function() { root.scan() },
      function() { root.usbOnly = !root.usbOnly; root.savePrefs() }
    ]
    for (var i = 0; i < otherDevices.length; i++) {
      (function(d) { list.push(function() { root.connectTo(d.id || d.name, true) }) })(otherDevices[i])
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

        // ---------- Header: icon · title + status line · on/off switch ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

          IPadIcon {
            id: heroIcon
            iconSize: Style.font.display * 1.15
            color: root.active ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.55)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          // Connection switch; keyboard cursor slot 0.
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
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "Sidecar"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.quip.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
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

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Connected ----------
        Column {
          visible: root.active
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "CONNECTED"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          ConnectedRow { width: parent.width }
        }

        PanelSeparator { visible: root.active; foreground: root.bar.foreground }

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

        // ---------- Connection ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(connLabels.implicitHeight, usbOnlyButton.implicitHeight)

          Column {
            id: connLabels
            anchors.left: parent.left
            anchors.right: usbOnlyButton.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "CONNECTION"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }
            Text {
              textFormat: Text.PlainText
              text: root.usbOnly ? "USB-C cable only · nothing goes over the network"
                                 : "USB-C when plugged in, otherwise Wi-Fi (unencrypted)"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }

          ActionButton {
            id: usbOnlyButton
            index: 6
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.glyphUsb
            text: "USB-C only"
            active: root.usbOnly
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
            visible: root.otherDevices.length === 0 && !root.scanning
            textFormat: Text.PlainText
            text: root.active ? "No other iPads found."
                              : "None found. Open OpenDisplay on the iPad (same Wi-Fi), or connect by IP."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Repeater {
            model: root.otherDevices
            DeviceRow {
              required property var modelData
              required property int index
              width: parent.width
              dev: modelData
              rowIndex: 7 + index
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

        // Tiny author credit, bottom right.
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: "leoaba"
          color: Qt.darker(root.bar.foreground, creditMouse.containsMouse ? 1.1 : 1.8)
          font.family: root.bar.fontFamily
          font.pixelSize: Math.round(Style.font.caption * 0.8)
          font.underline: creditMouse.containsMouse

          MouseArea {
            id: creditMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { Qt.openUrlExternally(root.authorUrl); root.close() }
          }
        }
      }
    }
  }

  // The connected device: name, then a badge for the link and the live stream
  // details. Clicking it disconnects.
  component ConnectedRow: CursorSurface {
    id: crow
    current: true
    foreground: root.bar.foreground
    implicitHeight: crowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: crowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.disconnect()
    }

    PanelToolTip {
      visible: crowMouse.containsMouse
      text: "Disconnect"
      fontFamily: root.bar.fontFamily
    }

    Item {
      id: crowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(crowIcon.implicitHeight, crowInfo.implicitHeight)

      IPadIcon {
        id: crowIcon
        iconSize: Style.font.heading * 1.2
        color: root.bar.foreground
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: crowInfo
        spacing: Style.space(3)
        anchors.left: crowIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: root.deviceName
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          // Which link the stream rides on.
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
            text: root.statusLine
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width - (transportBadge.visible ? transportBadge.width + parent.spacing : 0)
          }
        }
      }
    }
  }

  // Borderless, two-line row for an iPad found on the network.
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

      IPadIcon {
        id: devIcon
        iconSize: Style.font.heading * 1.2
        color: row.isCurrent ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.55)
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
