import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "settings.js" as Settings

// Overlays a random motivational ayah on the desktop background, sitting
// just above the wallpaper (WlrLayer.Bottom) so it never covers the bar,
// panels, or windows. Normally fully click-through (empty input mask) so
// the existing double-click-to-change-wallpaper gesture on the background
// layer keeps working underneath it; while `editMode` is on (toggled from
// the bar widget), it grabs input so the ayah card can be dragged, and a
// click anywhere else on the desktop ends the session.
//
// Show/hide, size, background opacity, and rotation rate are controlled
// from the companion bar widget (BarWidget.qml) through the shared settings
// file at `settingsPath` — this service watches that file and reapplies it,
// and also writes back to it after a drag commits a new position.
Item {
  id: root

  readonly property string ayahsPath: String(Qt.resolvedUrl("ayahs.json")).replace("file://", "")
  readonly property string settingsPath: Quickshell.env("HOME") + "/.local/state/omarchy/quran-motivation-settings.json"

  property var ayahs: []
  property int currentIndex: -1
  readonly property var current: (currentIndex >= 0 && currentIndex < ayahs.length) ? ayahs[currentIndex] : null

  property bool visibleSetting: Settings.DEFAULTS.visible
  property real scale: Settings.DEFAULTS.scale
  property real posX: Settings.DEFAULTS.posX
  property real posY: Settings.DEFAULTS.posY
  property real backgroundOpacity: Settings.DEFAULTS.backgroundOpacity
  property int intervalMinutes: Settings.DEFAULTS.intervalMinutes

  property bool editMode: false

  function pickRandom() {
    if (ayahs.length === 0) return
    if (ayahs.length === 1) {
      currentIndex = 0
      return
    }
    var next
    do {
      next = Math.floor(Math.random() * ayahs.length)
    } while (next === currentIndex)
    currentIndex = next
  }

  function applySettings(raw) {
    var next = Settings.parse(raw)
    visibleSetting = next.visible
    scale = next.scale
    posX = next.posX
    posY = next.posY
    backgroundOpacity = next.backgroundOpacity
    intervalMinutes = next.intervalMinutes
  }

  // Called after a drag commits a new center point (normalized 0..1).
  function commitPosition(nx, ny) {
    posX = Settings.clampUnit(nx, posX)
    posY = Settings.clampUnit(ny, posY)
    settingsFile.setText(JSON.stringify({
      visible: visibleSetting,
      scale: scale,
      posX: posX,
      posY: posY,
      backgroundOpacity: backgroundOpacity,
      intervalMinutes: intervalMinutes
    }, null, 2) + "\n")
  }

  FileView {
    id: dataFile
    path: root.ayahsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var parsed = []
      try {
        var value = JSON.parse(text())
        if (Array.isArray(value)) parsed = value
      } catch (e) {
        parsed = []
      }
      root.ayahs = parsed
      if (root.currentIndex < 0 || root.currentIndex >= root.ayahs.length) root.pickRandom()
    }
    onFileChanged: reload()
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applySettings(text())
    onLoadFailed: root.applySettings("")
    onFileChanged: reload()
  }

  IpcHandler {
    target: "io.github.r4y-br.quran-motivation"

    function next(): void { root.pickRandom() }
    function edit(): void { root.editMode = !root.editMode }
  }

  Timer {
    // Re-evaluate on a short tick so an interval change from the bar widget
    // takes effect without waiting out the previous (possibly much longer)
    // interval.
    id: rotationTimer
    property real elapsedMs: 0
    interval: 30000
    running: true
    repeat: true
    onTriggered: {
      elapsedMs += interval
      if (elapsedMs >= root.intervalMinutes * 60 * 1000) {
        elapsedMs = 0
        root.pickRandom()
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "io-github-r4y-br-quran-motivation"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Click-through normally (empty mask); full input while repositioning.
      mask: Region {
        width: root.editMode ? panel.width : 0
        height: root.editMode ? panel.height : 0
      }

      readonly property bool shown: root.visibleSetting && root.current !== null

      // Catches clicks outside the card while repositioning and ends the
      // session. Declared before `content` so the card's own MouseArea (on
      // top, hit-tested first) wins when the click lands on the card itself.
      MouseArea {
        anchors.fill: parent
        enabled: root.editMode
        onClicked: root.editMode = false
      }

      // Small hint so dragging is discoverable instead of mysterious.
      Rectangle {
        visible: root.editMode
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 16
        width: hint.implicitWidth + 24
        height: hint.implicitHeight + 14
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.6)

        Text {
          id: hint
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "Drag the ayah to reposition it — click anywhere else when done"
          color: "#ffffff"
          font.pixelSize: 13
        }
      }

      Item {
        id: content
        visible: panel.shown
        opacity: panel.shown ? 1 : 0
        width: card.width
        height: card.height
        z: 1

        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        // Position is imperative, not a live binding: drag.target writes to
        // x/y directly, and a persistent binding here would fight that. It's
        // (re)applied on load and whenever posX/posY change from settings.
        function applyStoredPosition() {
          x = Math.max(0, Math.min(panel.width - width, root.posX * panel.width - width / 2))
          y = Math.max(0, Math.min(panel.height - height, root.posY * panel.height - height / 2))
        }

        Component.onCompleted: applyStoredPosition()
        onWidthChanged: if (!dragArea.drag.active) applyStoredPosition()
        onHeightChanged: if (!dragArea.drag.active) applyStoredPosition()

        Connections {
          target: root
          function onPosXChanged() { if (!dragArea.drag.active) content.applyStoredPosition() }
          function onPosYChanged() { if (!dragArea.drag.active) content.applyStoredPosition() }
        }

        Rectangle {
          id: card
          width: column.width + Math.round(28 * root.scale)
          height: column.height + Math.round(20 * root.scale)
          radius: 14
          color: Qt.rgba(0, 0, 0, root.backgroundOpacity)
          border.width: root.editMode ? 2 : 0
          border.color: Qt.rgba(1, 1, 1, 0.8)
        }

        Column {
          id: column
          // No fixed width: sizes to whichever line is widest, so the card
          // hugs short ayahs instead of always stretching to maxTextWidth.
          // Row/Column each own one axis — Column owns y, so horizontal
          // anchors on its children (below) are fine, unlike in a Row.
          anchors.centerIn: card
          readonly property real maxTextWidth: Math.min(panel.width * 0.72, 900)
          spacing: Math.round(14 * root.scale)

          Text {
            width: Math.min(implicitWidth, column.maxTextWidth)
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: root.current ? root.current.arabic : ""
            color: "#ffffff"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: "Noto Naskh Arabic"
            font.pixelSize: Math.round(30 * root.scale)
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.65)
          }

          Text {
            width: Math.min(implicitWidth, column.maxTextWidth)
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: root.current ? root.current.translation : ""
            color: Qt.rgba(1, 1, 1, 0.88)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.italic: true
            font.pixelSize: Math.round(16 * root.scale)
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.65)
          }

          Text {
            width: Math.min(implicitWidth, column.maxTextWidth)
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: root.current ? ("— " + root.current.reference) : ""
            color: Qt.rgba(1, 1, 1, 0.6)
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Math.round(12 * root.scale)
            font.letterSpacing: 1
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.65)
          }
        }

        MouseArea {
          id: dragArea
          anchors.fill: card
          enabled: root.editMode
          cursorShape: Qt.SizeAllCursor
          drag.target: content
          drag.axis: Drag.XAndYAxis
          drag.minimumX: 0
          drag.maximumX: panel.width - content.width
          drag.minimumY: 0
          drag.maximumY: panel.height - content.height
          onReleased: {
            var nx = (content.x + content.width / 2) / panel.width
            var ny = (content.y + content.height / 2) / panel.height
            root.commitPosition(nx, ny)
          }
        }
      }
    }
  }
}
