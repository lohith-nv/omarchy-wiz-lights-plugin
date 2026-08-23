.pragma library

function parse(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || typeof parsed !== "object" || parsed.ok !== true || !Array.isArray(parsed.lights)) {
      return { ok: false, error: String(parsed && parsed.error) || "Could not parse wizctl output" }
    }
    return { ok: true, lights: parsed.lights, discovered: parsed.discovered }
  } catch (error) {
    return { ok: false, error: "Could not parse wizctl output" }
  }
}

function countOn(lights) {
  var total = Array.isArray(lights) ? lights.length : 0
  var on = 0
  for (var i = 0; i < total; i++) {
    if (lights[i] && lights[i].reachable && lights[i].state) on++
  }
  return { on: on, total: total }
}

function rssiText(dbm) {
  var value = Number(dbm)
  if (!isFinite(value)) return ""
  return Math.round(value) + " dBm"
}

function metaText(light) {
  if (!light) return ""
  if (!light.reachable) return "offline"
  var parts = [String(light.ip || "")]
  var rssi = rssiText(light.rssi)
  if (rssi !== "") parts.push(rssi)
  return parts.join(" · ")
}

function hsvToRgb(h, s, v) {
  var hue = ((Number(h) || 0) % 360 + 360) % 360
  var sat = Math.max(0, Math.min(1, Number(s) || 0))
  var val = Math.max(0, Math.min(1, Number(v) || 0))
  var c = val * sat
  var x = c * (1 - Math.abs((hue / 60) % 2 - 1))
  var m = val - c
  var rp = 0, gp = 0, bp = 0
  if (hue < 60) { rp = c; gp = x } else if (hue < 120) { rp = x; gp = c }
  else if (hue < 180) { gp = c; bp = x } else if (hue < 240) { gp = x; bp = c }
  else if (hue < 300) { rp = x; bp = c } else { rp = c; bp = x }
  return {
    r: Math.round((rp + m) * 255),
    g: Math.round((gp + m) * 255),
    b: Math.round((bp + m) * 255)
  }
}

function rgbToHsv(r, g, b) {
  var rn = (Number(r) || 0) / 255
  var gn = (Number(g) || 0) / 255
  var bn = (Number(b) || 0) / 255
  var max = Math.max(rn, gn, bn)
  var min = Math.min(rn, gn, bn)
  var d = max - min
  var h = 0
  if (d > 0) {
    if (max === rn) h = 60 * (((gn - bn) / d) % 6)
    else if (max === gn) h = 60 * ((bn - rn) / d + 2)
    else h = 60 * ((rn - gn) / d + 4)
  }
  if (h < 0) h += 360
  return { h: h, s: max === 0 ? 0 : d / max, v: max }
}

function rgbToHex(r, g, b) {
  function byte(v) {
    var n = Math.max(0, Math.min(255, Math.round(Number(v) || 0)))
    var hex = n.toString(16)
    return hex.length < 2 ? "0" + hex : hex
  }
  return "#" + byte(r) + byte(g) + byte(b)
}

var exportsObject = {
  parse: parse,
  countOn: countOn,
  rssiText: rssiText,
  metaText: metaText,
  hsvToRgb: hsvToRgb,
  rgbToHsv: rgbToHsv,
  rgbToHex: rgbToHex
}

if (typeof module !== "undefined" && module.exports) module.exports = exportsObject
