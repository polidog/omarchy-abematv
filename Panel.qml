import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar widget for ABEMA: the live schedule of every channel in one panel.
// Activating a row hands the channel to ABEMA's own player — the linear HLS
// streams are DRM-encrypted, so playback belongs to the site, not to us.
Panel {
  id: root
  moduleName: "io.github.polidog.abematv"
  ipcTarget: "io.github.polidog.abematv"

  // Raw responses; Model.buildView owns every bit of parsing.
  property string channelsRaw: ""
  property string slotsRaw: ""
  property string fetchError: ""
  property string filter: ""
  property int cursor: 0
  property bool cursorActive: false
  // Empty while a schedule is on screen; the channel a click drilled into
  // otherwise. Held as an id rather than as the row, so the detail view keeps
  // ticking along with everything else.
  property string detailChannel: ""
  // The channel view walks its own rows, so it keeps its own cursor: the
  // schedule's indexes count channels, and these count programmes.
  property int listingCursor: 0
  property string listingRaw: ""
  // Drives the "12m left" labels and the progress bars. Stepped by the same
  // timer that refetches, so the two never disagree by more than a tick.
  property int nowSeconds: Math.floor(Date.now() / 1000)

  readonly property string openWith: String(setting("openWith", "webapp"))
  readonly property bool showFilter: setting("showFilter", true) === true
  // The helper next to this file; Quickshell resolves plugin paths as file:// URLs.
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property bool barLogoReady: barLogo.status === Image.Ready
  readonly property string layout: String(setting("layout", "grid")) === "listing" ? "listing" : "grid"
  readonly property var view: Model.buildView(channelsRaw, slotsRaw, filter, nowSeconds)
  readonly property var grid: Model.buildGrid(channelsRaw, slotsRaw, filter, nowSeconds)
  // Same rows either way; only the order the cursor walks them in differs.
  readonly property var items: layout === "grid" ? grid.columns : view.rows
  // What the schedule already knows about the channel a head was tapped on:
  // the slot it is airing, and no more — the polled endpoints have no "later".
  readonly property var airingRows: {
    var found = []
    for (var i = 0; i < items.length; i++) {
      if (items[i].channelId === detailChannel) found.push(items[i])
    }
    return found
  }
  // The channel's real listing, once the helper has fetched it. Reuses the
  // listing layout's own builder: the helper answers in the shape the polled
  // endpoint uses, so there is one row format in this panel, not two.
  readonly property var listingRows: listingRaw === ""
    ? [] : Model.buildView(channelsRaw, listingRaw, "", nowSeconds).rows
  // The listing where it arrived, what is on now until it does. A channel is
  // open whenever either has a row, so the view never blinks out mid-fetch.
  readonly property var channelRows: listingRows.length > 0 ? listingRows : airingRows
  // The programme the cursor is on. Everything that dereferences a row tests
  // this one property rather than a second, separately-updated flag: two
  // bindings can disagree for a frame, and the delegate would read past it.
  readonly property var detailRow: {
    if (detailChannel === "" || channelRows.length === 0) return null
    return channelRows[Math.max(0, Math.min(channelRows.length - 1, listingCursor))]
  }
  readonly property bool showingDetail: detailRow !== null
  readonly property bool loading: channelsProc.running || slotsProc.running
  readonly property string problem: fetchError !== "" ? fetchError : view.error

  // The station list barely ever changes, so fetch it once per shell session;
  // the slots document is the whole point of the panel and is refetched on
  // every open and every tick while the panel is up.
  function refresh() {
    fetchError = ""
    nowSeconds = Math.floor(Date.now() / 1000)
    if (channelsRaw === "" && !channelsProc.running) channelsProc.running = true
    if (!slotsProc.running) slotsProc.running = true
  }

  function moveCursor(delta) {
    // Inside a channel the cursor walks that channel's programmes; outside it
    // walks the schedule.
    if (detailChannel !== "") {
      if (channelRows.length === 0) return
      cursorActive = true
      listingCursor = Math.max(0, Math.min(channelRows.length - 1, listingCursor + delta))
      return
    }
    if (items.length === 0) return
    cursorActive = true
    cursor = Math.max(0, Math.min(items.length - 1, cursor + delta))
  }

  // A click on a channel opens what it is airing rather than the player; the
  // player is one more Enter away, from the detail view.
  function openDetail(row) {
    if (!row || !Model.isChannelId(row.channelId)) return
    cursor = row.flatIndex
    cursorActive = true
    listingCursor = 0
    detailChannel = row.channelId
  }

  // The row carries a URL that Model built from validated ids; check the shape
  // again on the way out, so the only thing that can ever reach a command line
  // is an ABEMA channel or programme page.
  function watch(row) {
    if (!row) return
    var url = Model.rowUrl(row, nowSeconds)
    if (url === "") return

    close()
    // The browser keeps its own tabs; the web app would stack a window per
    // channel, so that path goes through the helper that reuses one window.
    Quickshell.execDetached(root.openWith === "browser"
      ? ["omarchy-launch-browser", url]
      : [root.pluginDir + "bin/abematv-watch", url])
  }

  function activateCursor() {
    if (detailChannel !== "") { watch(detailRow); return }
    if (cursor >= 0 && cursor < items.length) openDetail(items[cursor])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onFilterChanged: { cursor = 0; detailChannel = "" }
  onDetailChannelChanged: {
    listingRaw = ""
    listingCursor = 0
    if (detailChannel === "") return
    // Set the command here rather than binding it: a binding is re-evaluated
    // when the property change is notified, and this handler is notified too.
    // Whichever ran first, the helper was asked for the *previous* channel —
    // an empty one on the first open, which it refuses, which read as "this
    // channel has no listing" and fell back to the row already on screen.
    listingProc.command = [pluginDir + "bin/abematv-listing", detailChannel]
    listingProc.running = true
  }
  onCursorChanged: gridBody.revealCursor()
  onOpenedChanged: {
    if (opened) {
      cursor = 0
      cursorActive = false
      detailChannel = ""
      listingRaw = ""
      filterField.text = ""
      refresh()
    }
  }

  // ABEMA's own clients poll this once a minute (the slots response says so in
  // `interval`). Nothing is fetched while the panel is closed.
  Timer {
    id: tick
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }

  // Both fetches are capped where the bytes are produced rather than where they
  // are collected: curl is told the only scheme it may speak, how much of an
  // answer is still an answer, and — by never being handed -L — that a redirect
  // off ABEMA is not somewhere to follow.
  Process {
    id: channelsProc
    command: ["curl", "-fsS", "--proto", "=https", "--max-filesize", "8000000",
      "--max-time", "10", Model.CHANNELS_URL]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        // Keep the last good list on a failed fetch: names are cosmetic, and
        // the slots response still carries the ids the rows need.
        if (raw !== "") root.channelsRaw = raw
      }
    }
  }

  Process {
    id: slotsProc
    command: ["curl", "-fsS", "--proto", "=https", "--max-filesize", "8000000",
      "--max-time", "10", Model.SLOTS_URL]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") {
          // Only complain when there is nothing on screen already; a dropped
          // tick should not replace a schedule the user is reading.
          if (root.slotsRaw === "") root.fetchError = "Could not reach ABEMA."
          return
        }
        root.fetchError = ""
        root.slotsRaw = raw
      }
    }
  }

  // The channel's own listing. ABEMA gates the full timetable behind the token
  // its clients mint for themselves, so this one goes through a helper rather
  // than a bare curl; it answers in the polled endpoint's shape. Nothing is
  // fetched until a channel is actually opened.
  Process {
    id: listingProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        // No listing is not an error: the panel falls back to what is on air.
        if (raw !== "" && root.detailChannel !== "") root.listingRaw = raw
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.ICONS.bar
    // The glyph is the fallback: it shows until the logo has loaded, and stays
    // if the network never answers.
    labelVisible: !root.barLogoReady
    hasVisualContent: true
    fixedWidth: root.barLogoReady ? barLogo.width + Style.spaceReal(12) : -1
    active: root.opened
    useActiveColor: false
    tooltipText: "ABEMA — what's on air"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.refresh()
      else root.toggle()
    }

    // abema.tv's wordmark, copied from the site's logo.svg with a white fill:
    // every raster ABEMA icon is baked onto an opaque black square, and
    // MultiEffect's colorization scales the source colour, so only a white
    // shape on transparent recolors to the bar foreground.
    Image {
      id: barLogo
      anchors.centerIn: parent
      height: Style.spaceReal(11)
      width: height * 186 / 56
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      source: Qt.resolvedUrl("abema.svg")
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: barLogo
      source: barLogo
      visible: root.barLogoReady
      colorization: 1.0
      colorizationColor: button.foreground
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.layout === "grid" ? 940 : 520))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: filterField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        // Columns run left to right in the grid, so j/k walk them too rather
        // than doing nothing.
        var delta = root.layout === "grid" ? (dx !== 0 ? dx : dy) : dy
        if (delta !== 0) root.moveCursor(delta)
      }
      onActivateRequested: root.activateCursor()
      // Esc backs out of the detail view first; the panel closes from the list.
      onCloseRequested: {
        if (root.detailChannel !== "") root.detailChannel = ""
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "/" && root.showFilter) filterField.forceActiveFocus()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "ABEMA"
            meta: root.detailRow ? root.detailRow.channelName
              : root.loading && root.view.total === 0 ? "Loading…" : Model.summary(root.view)
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: Text {
              textFormat: Text.PlainText
              text: Model.ICONS.bar
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
            }
            trailingControl: PanelActionButton {
              iconText: Model.ICONS.refresh
              tooltipText: "Refresh (r)"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.refresh()
            }
          }

          TextField {
            id: filterField
            visible: root.showFilter && !root.showingDetail
            width: parent.width
            placeholderText: Model.ICONS.search + " Filter by channel or programme"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily
            onTextChanged: root.filter = text
            Keys.onEscapePressed: function(event) {
              if (text !== "") text = ""
              else keyCatcher.forceActiveFocus()
              event.accepted = true
            }
            onAccepted: root.activateCursor()
            Keys.onDownPressed: function(event) {
              root.moveCursor(root.cursorActive ? 1 : 0)
              event.accepted = true
            }
            Keys.onUpPressed: function(event) {
              root.moveCursor(-1)
              event.accepted = true
            }
          }

          Text {
            visible: root.items.length === 0
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.problem !== "" ? root.problem
              : root.loading ? "Asking ABEMA what's on…"
              : root.view.total === 0 ? "Nothing is on air right now."
              : "No channel matches this filter."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          // abema.tv/timetable's shape: a column per channel with time running
          // down it, a rule on each hour and a brighter one on now. Only the
          // hours around now exist in the data, so that window is the whole grid.
          Item {
            id: gridBody
            visible: root.layout === "grid" && root.grid.columns.length > 0 && !root.showingDetail
            width: parent.width
            implicitHeight: visible ? headerHeight + gridHeight : 0

            readonly property int headerHeight: Style.space(42)
            readonly property int gridHeight: Style.space(340)
            readonly property int columnWidth: Style.space(124)

            // Keep the cursor's column on screen when the keyboard moves it.
            function revealCursor() {
              if (!visible) return
              var left = root.cursor * columnWidth
              if (left < gridFlick.contentX) gridFlick.contentX = left
              else if (left + columnWidth > gridFlick.contentX + gridFlick.width)
                gridFlick.contentX = left + columnWidth - gridFlick.width
            }

            // The ruler stays put while the channels scroll under it.
            Item {
              id: timeAxis
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Style.space(36)

              Repeater {
                model: root.grid.hours

                delegate: Text {
                  required property var modelData
                  width: timeAxis.width
                  y: gridBody.headerHeight + modelData.top * gridBody.gridHeight - height / 2
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Flickable {
              id: gridFlick
              anchors.left: timeAxis.right
              anchors.leftMargin: Style.space(6)
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              contentWidth: Math.max(width, root.grid.columns.length * gridBody.columnWidth)
              contentHeight: height
              flickableDirection: Flickable.HorizontalFlick
              boundsBehavior: Flickable.StopAtBounds
              clip: true

              Repeater {
                model: root.grid.hours

                delegate: Rectangle {
                  required property var modelData
                  y: gridBody.headerHeight + modelData.top * gridBody.gridHeight
                  width: gridFlick.contentWidth
                  height: 1
                  color: Qt.darker(root.bar.foreground, 2.8)
                }
              }

              Repeater {
                model: root.grid.columns

                delegate: Item {
                  id: column
                  required property var modelData
                  required property int index
                  x: index * gridBody.columnWidth
                  width: gridBody.columnWidth
                  height: gridBody.headerHeight + gridBody.gridHeight

                  Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Qt.darker(root.bar.foreground, 3.0)
                  }

                  // Column head: the logo where it loads, the name always.
                  Item {
                    id: columnHead
                    width: parent.width
                    height: gridBody.headerHeight

                    Image {
                      id: headLogo
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(4)
                      width: parent.width - Style.space(16)
                      height: Style.space(15)
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      source: column.modelData.logoUrl
                      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                      visible: false
                      layer.enabled: true
                    }

                    MultiEffect {
                      anchors.fill: headLogo
                      source: headLogo
                      visible: headLogo.status === Image.Ready
                      colorization: 1.0
                      colorizationColor: Color.accent
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.leftMargin: Style.space(4)
                      anchors.rightMargin: Style.space(4)
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.space(5)
                      horizontalAlignment: Text.AlignHCenter
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: column.modelData.channelName
                      color: Qt.darker(root.bar.foreground, 1.4)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    HoverHandler {
                      cursorShape: Qt.PointingHandCursor
                      onHoveredChanged: if (hovered) { root.cursorActive = true; root.cursor = column.modelData.flatIndex }
                    }

                    TapHandler {
                      onTapped: root.openDetail(column.modelData)
                    }
                  }

                  CursorSurface {
                    id: block
                    visible: column.modelData.height > 0
                    x: Style.space(2)
                    y: gridBody.headerHeight + column.modelData.top * gridBody.gridHeight
                    width: column.width - Style.space(5)
                    height: Math.max(Style.space(20),
                      column.modelData.height * gridBody.gridHeight - Style.space(2))
                    hasCursor: root.cursorActive && root.cursor === column.modelData.flatIndex
                    bordered: true
                    foreground: root.bar.foreground
                    fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
                    clip: true

                    Column {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(6)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(6)
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(4)
                      spacing: Style.space(2)

                      // An arrow where the programme started before the window,
                      // so a block touching the top edge is not read as starting
                      // there.
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: (column.modelData.clippedTop ? "↑ " : "")
                          + column.modelData.startLabel + " " + column.modelData.endLabel
                        color: Color.accent
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 5
                        text: column.modelData.title
                        color: root.bar.foreground
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                      }
                    }

                    HoverHandler {
                      cursorShape: Qt.PointingHandCursor
                      onHoveredChanged: if (hovered) { root.cursorActive = true; root.cursor = column.modelData.flatIndex }
                    }

                    // The channel head opens what the channel is airing; the
                    // block *is* that programme, so tapping it just watches.
                    TapHandler {
                      onTapped: root.watch(column.modelData)
                    }
                  }
                }
              }

              // Now, drawn over the blocks it crosses.
              Rectangle {
                y: gridBody.headerHeight + root.grid.nowTop * gridBody.gridHeight
                width: gridFlick.contentWidth
                height: 1
                color: Color.accent
                z: 3
              }
            }
          }

          Column {
            visible: root.layout === "listing" && !root.showingDetail
            width: parent.width
            spacing: Style.space(12)

            // The listing itself: a heading per start time, a rule running down
            // the left of the column, and the channels that started at that time
            // beside it.
            Repeater {
              model: root.view.groups

              delegate: Item {
                id: groupBlock
                required property var modelData
                width: panelColumn.width
                implicitHeight: groupRows.implicitHeight

                Column {
                  id: timeHeading
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(10)
                  width: Style.space(40)
                  spacing: 0

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    textFormat: Text.PlainText
                    text: groupBlock.modelData.timeLabel
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  // Slots that began before today keep their own clock, so say
                  // which day it was.
                  Text {
                    width: parent.width
                    visible: groupBlock.modelData.dayNote !== ""
                    horizontalAlignment: Text.AlignRight
                    textFormat: Text.PlainText
                    text: groupBlock.modelData.dayNote
                    color: Qt.darker(root.bar.foreground, 2.0)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Rectangle {
                  id: timeRule
                  anchors.left: timeHeading.right
                  anchors.leftMargin: Style.space(8)
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: 1
                  color: Qt.darker(root.bar.foreground, 2.6)
                }

                Column {
                  id: groupRows
                  anchors.left: timeRule.right
                  anchors.leftMargin: Style.space(6)
                  anchors.right: parent.right
                  spacing: 0

                  Repeater {
                    model: groupBlock.modelData.items

                    delegate: CursorSurface {
                      id: row
                      required property var modelData
                      width: groupRows.width
                      implicitHeight: rowBody.implicitHeight + Style.spacing.lg
                      hasCursor: root.cursorActive && root.cursor === row.modelData.flatIndex
                      foreground: root.bar.foreground
                      fill: Style.hoverFillFor(root.bar.foreground, Color.accent)

                      Column {
                        id: rowBody
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(8)
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(3)

                        // Channel identity: the logo where it loads, the name always.
                        // The logo keeps its slot either way, so the names stay in a
                        // column when a logo is slow or missing.
                        Item {
                          width: parent.width
                          implicitHeight: Math.max(channelLogo.height, channelLabel.implicitHeight)

                          Image {
                            id: channelLogo
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Style.space(44)
                            height: Style.font.caption + Style.space(4)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            source: row.modelData.logoUrl
                            sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                            // Kept as a hidden layer so the effect can sample it.
                            visible: false
                            layer.enabled: true
                          }

                          // ABEMA ships the logos as white on transparent, which
                          // disappears on a light theme; paint them in the accent
                          // colour the rest of the panel already uses.
                          MultiEffect {
                            anchors.fill: channelLogo
                            source: channelLogo
                            visible: channelLogo.status === Image.Ready
                            colorization: 1.0
                            colorizationColor: Color.accent
                          }

                          Text {
                            id: channelLabel
                            anchors.left: channelLogo.right
                            anchors.leftMargin: Style.space(8)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            text: row.modelData.channelName
                            color: Qt.darker(root.bar.foreground, 1.35)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }

                        Text {
                          width: parent.width
                          textFormat: Text.PlainText
                          elide: Text.ElideRight
                          text: row.modelData.title
                          color: root.bar.foreground
                          font.family: root.bar.fontFamily
                          font.pixelSize: Style.font.body
                        }

                        // How far in it is, and when it ends — a listing reads
                        // "~10:30" rather than a bare countdown.
                        Item {
                          width: parent.width
                          implicitHeight: untilLabel.implicitHeight

                          Text {
                            id: untilLabel
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: row.modelData.endLabel + "  ·  " + row.modelData.remainLabel
                            color: Qt.darker(root.bar.foreground, 1.6)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          Rectangle {
                            anchors.left: parent.left
                            anchors.right: untilLabel.left
                            anchors.rightMargin: Style.space(10)
                            anchors.verticalCenter: parent.verticalCenter
                            height: Style.space(2)
                            radius: height / 2
                            color: Qt.darker(root.bar.foreground, 2.4)

                            Rectangle {
                              width: parent.width * row.modelData.progress
                              height: parent.height
                              radius: parent.radius
                              color: Color.accent
                            }
                          }
                        }
                      }

                      HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: if (hovered) { root.cursorActive = true; root.cursor = row.modelData.flatIndex }
                      }

                      TapHandler {
                        onTapped: root.openDetail(row.modelData)
                      }
                    }
                  }
                }
              }
            }
          }

          // What the channel head opens: the channel, and every slot ABEMA
          // says it is airing. Tapping a programme hands the channel to the
          // player, so this list is the last stop rather than a card on the
          // way to one. A one-row Repeater for the header rather than a
          // visibility flag, so nothing in here guards against no channel.
          Repeater {
            model: root.detailRow ? [root.detailRow] : []

            delegate: Column {
              id: channelBody
              required property var modelData
              width: panelColumn.width
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(8)

                PanelActionButton {
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: Model.ICONS.back
                  tooltipText: "Back to the schedule (Esc)"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onClicked: root.detailChannel = ""
                }

                Item {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(52)
                  height: Style.space(16)

                  Image {
                    id: channelHeadLogo
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: channelBody.modelData.logoUrl
                    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                    visible: false
                    layer.enabled: true
                  }

                  MultiEffect {
                    anchors.fill: channelHeadLogo
                    source: channelHeadLogo
                    visible: channelHeadLogo.status === Image.Ready
                    colorization: 1.0
                    colorizationColor: Color.accent
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(0, parent.width - Style.space(96))
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: channelBody.modelData.channelName
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              // One row per slot: when it runs, what it is, how far in it is.
              Repeater {
                model: root.channelRows

                delegate: CursorSurface {
                  id: slotRow
                  required property var modelData
                  required property int index
                  width: channelBody.width
                  implicitHeight: slotBody.implicitHeight + Style.spacing.lg
                  hasCursor: root.cursorActive && root.listingCursor === slotRow.index
                  bordered: true
                  foreground: root.bar.foreground
                  fill: Style.hoverFillFor(root.bar.foreground, Color.accent)

                  Column {
                    id: slotBody
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: slotRow.modelData.startLabel + " " + slotRow.modelData.endLabel
                        + (slotRow.modelData.dayNote === "" ? "" : "  " + slotRow.modelData.dayNote)
                      color: Color.accent
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      wrapMode: Text.WordWrap
                      elide: Text.ElideRight
                      maximumLineCount: 2
                      text: slotRow.modelData.title
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    // What ABEMA writes about the programme: the one-line
                    // pitch, then as much of the synopsis as two lines hold.
                    Text {
                      visible: text !== ""
                      width: parent.width
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: slotRow.modelData.detail
                      color: Qt.darker(root.bar.foreground, 1.5)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      visible: text !== ""
                      width: parent.width
                      textFormat: Text.PlainText
                      wrapMode: Text.WordWrap
                      elide: Text.ElideRight
                      maximumLineCount: 2
                      text: slotRow.modelData.content
                      color: Qt.darker(root.bar.foreground, 1.9)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Item {
                      visible: slotRow.modelData.remainLabel !== ""
                      width: parent.width
                      implicitHeight: visible ? slotRemain.implicitHeight : 0

                      Text {
                        id: slotRemain
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: slotRow.modelData.remainLabel
                        color: Qt.darker(root.bar.foreground, 1.6)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: slotRemain.left
                        anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        height: Style.space(2)
                        radius: height / 2
                        color: Qt.darker(root.bar.foreground, 2.4)

                        Rectangle {
                          width: parent.width * slotRow.modelData.progress
                          height: parent.height
                          radius: parent.radius
                          color: Color.accent
                        }
                      }
                    }
                  }

                  HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered) { root.cursorActive = true; root.listingCursor = slotRow.index }
                  }

                  TapHandler {
                    onTapped: root.watch(slotRow.modelData)
                  }
                }
              }
            }
          }

          PanelSeparator {
            visible: root.items.length > 0
            foreground: root.bar.foreground
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.showingDetail
              ? "Enter watch · Esc back · " + (root.layout === "grid" ? "h/l" : "j/k") + " programme"
              : (root.layout === "grid" ? "h/l move" : "j/k move")
                + " · Enter open · / filter · r refresh"
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
