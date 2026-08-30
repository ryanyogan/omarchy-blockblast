.pragma library

// Block colors from the active Omarchy theme. colors.toml carries the
// terminal palette (red, orange, yellow, green, cyan, blue, magenta), which is
// exactly seven hues, one per block color. A theme that leaves some out gets
// hues spun from its accent instead, so every theme plays in its own colors.

var KEYS = ["red", "orange", "yellow", "green", "cyan", "blue", "magenta"]

function parseToml(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"/)
    if (m) out[m[1]] = m[2]
  }
  return out
}

function isHex(v) { return /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(String(v || "")) }

// Seven block colors. `accent` is a Qt color used for fallbacks.
function blockColors(toml, accent) {
  var vals = parseToml(toml)
  var out = []
  for (var i = 0; i < KEYS.length; i++) {
    var v = vals[KEYS[i]]
    if (!isHex(v) && KEYS[i] === "orange") v = vals["bright_yellow"] || vals["brown"]
    if (!isHex(v)) v = vals["bright_" + KEYS[i]]
    out.push(isHex(v) ? v : null)
  }
  for (var j = 0; j < out.length; j++) {
    if (!out[j]) out[j] = Qt.hsla((accent.hslHue + j / KEYS.length) % 1, Math.max(0.45, accent.hslSaturation), Math.max(0.42, Math.min(0.62, accent.hslLightness)), 1)
  }
  return out
}

function mode(toml) {
  var vals = parseToml(toml)
  return vals.mode === "light" ? "light" : "dark"
}

// A block face wants a lighter cap and a darker foot. These keep hue.
function lighten(c, amount) { return Qt.hsla(c.hslHue, c.hslSaturation, Math.min(1, c.hslLightness + amount), c.a) }
function darken(c, amount) { return Qt.hsla(c.hslHue, c.hslSaturation, Math.max(0, c.hslLightness - amount), c.a) }

// Text on a block: pick whichever of black/white contrasts more.
function ink(c) { return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6 ? "#101010" : "#ffffff" }
