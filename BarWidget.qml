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
    settingsFile.setText(JSON.stringify(root.currentSettings(), null, 2) + "\n")
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

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyLoaded(text())
    onLoadFailed: root.applyLoaded("")
    onFileChanged: reload()
  }

  Process {
    id: nextProc
    command: ["omarchy-shell", "io.github.r4y-br.quran-motivation", "next"]
  }

  Process {
    id: repositionProc
    command: ["omarchy-shell", "io.github.r4y-br.quran-motivation", "edit"]
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
