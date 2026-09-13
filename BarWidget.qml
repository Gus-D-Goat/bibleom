import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "settings.js" as Settings

Panel {
  id: root
  moduleName: "io.github.r4y-br.quran-motivation"
  ipcTarget: "io.github.r4y-br.quran-motivation.panel"

  readonly property string settingsPath: Quickshell.env("HOME") + "/.local/state/omarchy/quran-motivation-settings.json"

  // Security hardening (see SECURITY.md in the repo for the reasoning):
  // trusted absolute binaries and a minimal explicit environment for every
  // spawned process (no ambient PATH/LD_PRELOAD/etc. inheritance). All
  // settings reads/writes go through helpers/safe-settings-io.py, which
  // opens every path component from $HOME down relative to its already-
  // open parent directory descriptor with O_NOFOLLOW and publishes writes
  // via a randomized exclusive 0600 temp file rename()'d atomically
  // through that same retained descriptor.
  readonly property string omarchyShellBin: "/usr/bin/omarchy-shell"
  readonly property var minimalShellEnv: ({
    "PATH": "/usr/bin",
    "HOME": Quickshell.env("HOME") || "",
    "OMARCHY_PATH": Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy",
    "WAYLAND_DISPLAY": Quickshell.env("WAYLAND_DISPLAY") || "",
    "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || ""
  })

  readonly property string settingsRelPath: ".local/state/omarchy/quran-motivation-settings.json"
  readonly property string pythonBin: "/usr/bin/python3"
  readonly property string safeIoHelper: String(Qt.resolvedUrl("helpers/safe-settings-io.py")).replace("file://", "")
  readonly property var minimalIoEnv: ({ "HOME": Quickshell.env("HOME") || "" })

  property string pendingSettingsWrite: ""
  property bool settingsWritePending: false

  function readSettings() {
    if (!readSettingsProc.running) readSettingsProc.running = true
  }

  function flushSettingsWrite() {
    if (!settingsWritePending) return
    settingsWritePending = false
    writeSettingsProc.running = true
  }

  property bool visibleSetting: Settings.DEFAULTS.visible
  property real scale: Settings.DEFAULTS.scale
  property real posX: Settings.DEFAULTS.posX
  property real posY: Settings.DEFAULTS.posY
  property real backgroundOpacity: Settings.DEFAULTS.backgroundOpacity
  property int intervalMinutes: Settings.DEFAULTS.intervalMinutes

  // posX/posY are owned by Service.qml (it's the one with live drag
  // coordinates) — this panel only reads them back so a write here never
  // races a drag; every write below preserves whatever position is current.
  function currentSettings() {
    return {
      visible: root.visibleSetting,
      scale: root.scale,
      posX: root.posX,
      posY: root.posY,
      backgroundOpacity: root.backgroundOpacity,
      intervalMinutes: root.intervalMinutes
    }
  }

  function writeSettings() {
    pendingSettingsWrite = JSON.stringify(root.currentSettings())
    settingsWritePending = true
    if (!writeSettingsProc.running) flushSettingsWrite()
  }

  function applyLoaded(raw) {
    var next = Settings.parse(raw)
    visibleSetting = next.visible
    scale = next.scale
    posX = next.posX
    posY = next.posY
    backgroundOpacity = next.backgroundOpacity
    intervalMinutes = next.intervalMinutes
  }

  function setVisible(value) {
    visibleSetting = value
    writeSettings()
  }

  function setScale(value) {
    scale = Settings.clampScale(value)
    writeSettings()
  }

  function setBackgroundOpacity(value) {
    backgroundOpacity = Settings.clampOpacity(value)
    writeSettings()
  }

  function setIntervalMinutes(value) {
    intervalMinutes = Settings.clampInterval(value)
    writeSettings()
  }

  function showNext() {
    if (nextProc.running) return
    nextProc.running = true
  }

  // Closes this panel (so the desktop is visible) and tells the service to
  // start/stop drag-repositioning. The service itself ends the session on
  // an outside click, so this is a one-shot fire — no state to track here.
  function startReposition() {
    root.close()
    if (!repositionProc.running) repositionProc.running = true
  }

  Process {
    id: readSettingsProc
    command: [root.pythonBin, root.safeIoHelper, "read", root.settingsRelPath]
    clearEnvironment: true
    environment: root.minimalIoEnv
    stdout: StdioCollector { id: readSettingsOut; waitForEnd: true }
    // Exit 0 = verified content; 3 = absent; 2/1 = guard or usage failure.
    // Every non-zero case falls back to defaults, same as before.
    onExited: function(exitCode) {
      root.applyLoaded(exitCode === 0 ? readSettingsOut.text : "")
    }
  }

  Process {
    id: writeSettingsProc
    command: [root.pythonBin, root.safeIoHelper, "write", root.settingsRelPath]
    clearEnvironment: true
    environment: root.minimalIoEnv
    stdinEnabled: true
    onStarted: write(root.pendingSettingsWrite + "\n")
    onExited: function(exitCode) {
      if (root.settingsWritePending) root.flushSettingsWrite()
    }
  }

  // Pure inotify trigger: blockLoading/blockAllReads stay true forever, so
  // this FileView never itself reads the file — it only tells us to re-run
  // the safe helper above when something (us or an external actor) changes
  // the path.
  FileView {
    id: settingsWatcher
    path: root.settingsPath
    watchChanges: true
    blockLoading: true
    blockAllReads: true
    printErrors: false
    onFileChanged: root.readSettings()
  }

  Component.onCompleted: root.readSettings()

  Process {
    id: nextProc
    command: [root.omarchyShellBin, "io.github.r4y-br.quran-motivation", "next"]
    clearEnvironment: true
    environment: root.minimalShellEnv
  }

  Process {
    id: repositionProc
    command: [root.omarchyShellBin, "io.github.r4y-br.quran-motivation", "edit"]
    clearEnvironment: true
    environment: root.minimalShellEnv
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{EEDC}"
    tooltipText: "Quran Motivation"
    onPressed: function() { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: heroTitle.implicitHeight

          Text {
            id: heroTitle
            textFormat: Text.PlainText
            text: "Quran Motivation"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Show / hide ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(showLabel.implicitHeight, showSwitch.implicitHeight)

          Text {
            id: showLabel
            textFormat: Text.PlainText
            text: "Show verses on desktop"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          ToggleSwitch {
            id: showSwitch
            checked: root.visibleSetting
            foreground: root.bar.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.setVisible(!root.visibleSetting)
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Size ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(sizeHeader.implicitHeight, sizeValue.implicitHeight)

            PanelSectionHeader {
              id: sizeHeader
              text: "SIZE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: sizeValue
              textFormat: Text.PlainText
              text: Math.round((sizeSlider.dragging ? sizeSlider.liveValue : root.scale) * 100) + "%"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: sizeSlider
            bar: root.bar
            width: parent.width
            minimum: Settings.SCALE_MIN
            maximum: Settings.SCALE_MAX
            step: 0.05
            value: root.scale
            onReleased: function(v) { root.setScale(v) }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Background ----------
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(opacityHeader.implicitHeight, opacityValue.implicitHeight)

            PanelSectionHeader {
              id: opacityHeader
              text: "BACKGROUND OPACITY"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: opacityValue
              textFormat: Text.PlainText
              text: Math.round((opacitySlider.dragging ? opacitySlider.liveValue : root.backgroundOpacity) * 100) + "%"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: opacitySlider
            bar: root.bar
            width: parent.width
            minimum: Settings.OPACITY_MIN
            maximum: Settings.OPACITY_MAX
            step: 0.05
            value: root.backgroundOpacity
            onReleased: function(v) { root.setBackgroundOpacity(v) }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Position ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "POSITION"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

          Button {
            width: parent.width
            text: "Drag to reposition on desktop"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.startReposition()
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Rotation rate ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "CHANGE VERSES"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

          Dropdown {
            width: parent.width
            showLabel: false
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            value: String(root.intervalMinutes)
            options: {
              var list = []
              for (var i = 0; i < Settings.INTERVAL_OPTIONS.length; i++) {
                var o = Settings.INTERVAL_OPTIONS[i]
                list.push({ value: String(o.minutes), label: o.label })
              }
              return list
            }
            onChanged: function(v) { root.setIntervalMinutes(parseInt(v, 10)) }
          }

          Button {
            width: parent.width
            text: "Show a new verse now"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.showNext()
          }
        }
      }
    }
  }
}
