// Shared schema/validation for the settings file both Service.qml (reader
// and drag-position writer) and BarWidget.qml (control panel writer) use, so
// the two never drift out of sync.

var DEFAULTS = {
  visible: true,
  scale: 1.0,
  posX: 0.5,
  posY: 0.88,
  backgroundOpacity: 0.4,
  intervalMinutes: 240
}
var SCALE_MIN = 0.6
var SCALE_MAX = 2.0
var OPACITY_MIN = 0
var OPACITY_MAX = 0.85
var INTERVAL_OPTIONS = [
  { label: "Every 15 minutes", minutes: 15 },
  { label: "Every 30 minutes", minutes: 30 },
  { label: "Every hour", minutes: 60 },
  { label: "Every 2 hours", minutes: 120 },
  { label: "Every 4 hours", minutes: 240 },
  { label: "Every 8 hours", minutes: 480 },
  { label: "Once a day", minutes: 1440 }
]

function clampScale(value) {
  var n = Number(value)
  if (isNaN(n) || n <= 0) n = DEFAULTS.scale
  return Math.max(SCALE_MIN, Math.min(SCALE_MAX, n))
}

function clampUnit(value, fallback) {
  var n = Number(value)
  if (isNaN(n)) n = fallback
  return Math.max(0, Math.min(1, n))
}

function clampOpacity(value) {
  var n = Number(value)
  if (isNaN(n)) n = DEFAULTS.backgroundOpacity
  return Math.max(OPACITY_MIN, Math.min(OPACITY_MAX, n))
}

function clampInterval(value) {
  var n = Number(value)
  if (isNaN(n) || n <= 0) return DEFAULTS.intervalMinutes
  return n
}

function parse(raw) {
  var parsed = {}
  try {
    var obj = JSON.parse(String(raw || "{}"))
    if (obj && typeof obj === "object") parsed = obj
  } catch (e) {
    parsed = {}
  }
  return {
    visible: typeof parsed.visible === "boolean" ? parsed.visible : DEFAULTS.visible,
    scale: clampScale(parsed.scale),
    posX: clampUnit(parsed.posX, DEFAULTS.posX),
    posY: clampUnit(parsed.posY, DEFAULTS.posY),
    backgroundOpacity: clampOpacity(parsed.backgroundOpacity),
    intervalMinutes: clampInterval(parsed.intervalMinutes)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULTS: DEFAULTS,
    SCALE_MIN: SCALE_MIN,
    SCALE_MAX: SCALE_MAX,
    OPACITY_MIN: OPACITY_MIN,
    OPACITY_MAX: OPACITY_MAX,
    INTERVAL_OPTIONS: INTERVAL_OPTIONS,
    clampScale: clampScale,
    clampUnit: clampUnit,
    clampOpacity: clampOpacity,
    clampInterval: clampInterval,
    parse: parse
  }
}
