.pragma library

// Pure data helpers for the ABEMA panel. The QML side only fetches two JSON
// documents and hands the raw text in; parsing, joining, grouping, labelling
// and URL building live here so they can be read and tested without a shell.
//
// Both endpoints answer without a token. `channels` is the station list and its
// running order; `broadcast/slots` is what each channel is airing *right now* —
// it takes no date parameters, so there is no "later today" to show.
var CHANNELS_URL = "https://api.abema.io/v1/channels"
var SLOTS_URL = "https://api.abema.io/v1/broadcast/slots"
var IMAGE_HOST = "https://image.p-c2-x.abema-tv.com/image"
// The site favicon: ABEMA's mascot and wordmark, white on transparent, which
// is the only ABEMA brand asset that recolors cleanly for a status bar. The
// apple-touch-icon is the same art but baked onto an opaque black square.
var BRAND_ICON_URL = "https://abema.tv/favicon.ico?v=5"

// ABEMA names its own programmes, and a title carries whatever the broadcaster
// put in it. Everything that reaches a Text passes a limit first so one long
// title cannot push the panel layout off the screen.
var LIMITS = {
  text: 140,
  rows: 200
}

// Nerd Font (Material Design) glyphs, spelled the way the first-party widgets do.
var ICONS = {
  bar: "󰕧",     // video
  refresh: "󰑐", // refresh
  search: "󰍉",  // magnify
  back: "󰅁",    // chevron-left
  play: "󰐊"     // play
}

function clampText(value, limit) {
  var text = String(value === undefined || value === null ? "" : value)
    .replace(/[\x00-\x1f\x7f]+/g, " ")
    .trim()
  var max = limit > 0 ? limit : LIMITS.text
  return text.length > max ? text.substring(0, max) + "…" : text
}

// A channel or slot id lands in a URL and on a command line, so it never
// leaves this file unless it looks like one.
function isId(value) {
  return /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(String(value === undefined || value === null ? "" : value))
}

function isChannelId(value) {
  return isId(value)
}

function watchUrl(channelId) {
  return isChannelId(channelId) ? "https://abema.tv/now-on-air/" + channelId : ""
}

// ABEMA's page for one programme: where a slot that has not started yet lives.
function slotUrl(channelId, slotId) {
  return isId(channelId) && isId(slotId)
    ? "https://abema.tv/channels/" + channelId + "/slots/" + slotId
    : ""
}

// Where activating a row goes. A programme on air now is the live channel;
// anything later has no stream yet, so it opens its own page instead.
function rowUrl(row, now) {
  if (!row) return ""
  var airing = Number(row.startAt) <= now && now < Number(row.endAt)
  var slot = slotUrl(row.channelId, row.slotId)
  return airing || slot === "" ? watchUrl(row.channelId) : slot
}

// White transparent PNGs, which the panel recolors to the bar foreground.
// The height is the CDN's, not the panel's: it decodes small and stays crisp.
function logoUrl(channelId) {
  return isChannelId(channelId)
    ? IMAGE_HOST + "/channels/" + channelId + "/logo.png?height=48&quality=75&width=144&version=1"
    : ""
}

function parse(raw) {
  try {
    var value = JSON.parse(String(raw || ""))
    return value && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

function clock(epochSeconds) {
  var seconds = Number(epochSeconds)
  if (!isFinite(seconds) || seconds <= 0) return ""
  var date = new Date(seconds * 1000)
  return pad(date.getHours()) + ":" + pad(date.getMinutes())
}

// Slots that already ended (a stale fetch) and slots with a broken clock both
// end up at 1: the row is still watchable, the bar just reads as full.
// A slot that started before today still prints its own clock, so the bucket
// says which day it belongs to; without it a 21:40 heading sitting above 03:00
// reads as tonight rather than last night.
function dayNote(startAtSeconds, now) {
  var start = new Date(Number(startAtSeconds) * 1000)
  var today = new Date(Number(now) * 1000)
  var startDay = new Date(start.getFullYear(), start.getMonth(), start.getDate()).getTime()
  var todayDay = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
  var days = Math.round((todayDay - startDay) / 86400000)
  if (days === 0) return ""
  // A channel's own listing runs into tomorrow, so the note points both ways:
  // without it a 09:00 heading under an 23:40 one reads as the same morning.
  return (days > 0 ? "-" : "+") + Math.abs(days) + "d"
}

function progressOf(startAt, endAt, now) {
  var start = Number(startAt)
  var end = Number(endAt)
  if (!isFinite(start) || !isFinite(end) || end <= start) return 1
  return Math.max(0, Math.min(1, (now - start) / (end - start)))
}

function formatRemaining(endAt, now) {
  var end = Number(endAt)
  if (!isFinite(end)) return ""
  var minutes = Math.ceil((end - now) / 60)
  if (minutes <= 0) return "ending"
  if (minutes < 60) return minutes + "m left"
  return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m left"
}

function matches(row, needle) {
  if (needle === "") return true
  return (row.channelName + " " + row.title + " " + row.highlight).toLowerCase().indexOf(needle) >= 0
}

// Shared by both layouts: parse, join, clamp, filter. Rows come back in the
// order ABEMA listed the slots; each layout sorts them its own way.
function collectRows(channelsRaw, slotsRaw, filter, now) {
  var result = { rows: [], total: 0, error: "" }
  var channels = parse(channelsRaw)
  var slots = parse(slotsRaw)

  var names = {}
  var order = {}
  var list = channels && channels.channels instanceof Array ? channels.channels : []
  for (var i = 0; i < list.length; i++) {
    var channel = list[i]
    if (!channel || !isChannelId(channel.id)) continue
    names[channel.id] = clampText(channel.name)
    order[channel.id] = i
  }

  var airing = slots && slots.slots instanceof Array ? slots.slots : null
  if (airing === null) {
    result.error = String(slotsRaw || "") === "" ? "" : "ABEMA returned something unreadable."
    return result
  }

  var rows = []
  for (var j = 0; j < airing.length && rows.length < LIMITS.rows; j++) {
    var slot = airing[j]
    if (!slot || !isChannelId(slot.channelId)) continue

    var row = {
      channelId: String(slot.channelId),
      slotId: isId(slot.id) ? String(slot.id) : "",
      channelName: names[slot.channelId] || String(slot.channelId),
      logoUrl: logoUrl(slot.channelId),
      title: clampText(slot.title) || "(no title)",
      highlight: clampText(slot.highlight, 80),
      // The channel's own listing prints these two under the title; they are
      // the rest of what a slot says about the programme.
      detail: clampText(slot.detailHighlight, 200),
      content: clampText(slot.content, 600),
      startAt: Number(slot.startAt) || 0,
      endAt: Number(slot.endAt) || 0,
      startLabel: clock(slot.startAt),
      dayNote: dayNote(slot.startAt, now),
      endLabel: clock(slot.endAt) === "" ? "" : "~" + clock(slot.endAt),
      // A programme that has not started has nothing left of it to count.
      remainLabel: now < Number(slot.startAt) ? "" : formatRemaining(slot.endAt, now),
      progress: progressOf(slot.startAt, slot.endAt, now),
      channelOrder: order.hasOwnProperty(slot.channelId) ? order[slot.channelId] : LIMITS.rows + j
    }
    row.url = rowUrl(row, now)
    rows.push(row)
  }

  result.total = rows.length
  var needle = String(filter || "").trim().toLowerCase()
  for (var k = 0; k < rows.length; k++) {
    if (matches(rows[k], needle)) result.rows.push(rows[k])
  }
  return result
}

// A newspaper TV listing runs down the clock, so rows are ordered by start time
// and bucketed under it; channels keep the running order the ABEMA apps use
// within a bucket.
function buildView(channelsRaw, slotsRaw, filter, now) {
  var view = { groups: [], rows: [], total: 0, matched: 0, error: "" }
  var collected = collectRows(channelsRaw, slotsRaw, filter, now)
  view.error = collected.error
  view.total = collected.total
  if (collected.error !== "") return view

  var rows = collected.rows.slice()
  rows.sort(function(left, right) {
    return left.startAt - right.startAt || left.channelOrder - right.channelOrder
  })

  // Buckets are keyed by the printed time and the day, not the raw second, so
  // two slots that start 20 seconds apart share one "09:30" heading while
  // yesterday's 21:40 keeps its own.
  var buckets = {}
  for (var k = 0; k < rows.length; k++) {
    var row = rows[k]
    row.flatIndex = view.rows.length
    view.rows.push(row)

    var key = row.dayNote + " " + row.startLabel
    if (!buckets.hasOwnProperty(key)) {
      buckets[key] = { timeLabel: row.startLabel, dayNote: row.dayNote, items: [] }
      view.groups.push(buckets[key])
    }
    buckets[key].items.push(row)
  }
  view.matched = view.rows.length
  return view
}

// The grid is abema.tv/timetable's shape: a column per channel, time running
// down. It shows a fixed window around now, snapped to the half hour so the
// ruler lands on round times; programmes that run past either edge are clipped,
// which is what a printed listing does with them too.
var GRID_BEFORE = 3600
var GRID_SPAN = 4 * 3600

function gridWindow(now) {
  var start = Math.floor((Number(now) - GRID_BEFORE) / 1800) * 1800
  return { start: start, end: start + GRID_SPAN, span: GRID_SPAN }
}

function clamp01(value) {
  return value < 0 ? 0 : (value > 1 ? 1 : value)
}

function buildGrid(channelsRaw, slotsRaw, filter, now) {
  var grid = { columns: [], hours: [], nowTop: 0, total: 0, matched: 0, error: "" }
  var collected = collectRows(channelsRaw, slotsRaw, filter, now)
  grid.error = collected.error
  grid.total = collected.total
  if (collected.error !== "") return grid

  var window = gridWindow(now)
  grid.nowTop = clamp01((Number(now) - window.start) / window.span)

  for (var hour = Math.ceil(window.start / 3600) * 3600; hour <= window.end; hour += 3600) {
    grid.hours.push({ label: clock(hour), top: (hour - window.start) / window.span })
  }

  var rows = collected.rows.slice()
  rows.sort(function(left, right) { return left.channelOrder - right.channelOrder })

  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var top = clamp01((row.startAt - window.start) / window.span)
    row.flatIndex = i
    row.top = top
    row.height = Math.max(0, clamp01((row.endAt - window.start) / window.span) - top)
    row.clippedTop = row.startAt < window.start
    row.clippedBottom = row.endAt > window.end
    grid.columns.push(row)
  }
  grid.matched = grid.columns.length
  return grid
}

function summary(view) {
  if (view.total === 0) return "ABEMA"
  if (view.matched === view.total) return view.total + " channels on air"
  return view.matched + " of " + view.total + " channels"
}
