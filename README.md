# ABEMA — an Omarchy bar widget

What every [ABEMA](https://abema.tv/) channel is airing right now, in one panel.
Click a programme to watch it. Click a channel's head for that channel's own listing — everything it is showing next, with the synopsis under each title — and pick one from there.

- A grid in the shape of abema.tv/timetable: a column per channel, time running down
- Or a newspaper-style listing, with rows grouped under their start time
- Channel logos, end times, minutes left, and a line across the grid on now
- A channel's own listing, about a day of it, behind its column head
- ABEMA's own mark in the status bar, recolored to the bar foreground
- Picking a channel replaces the ABEMA window instead of opening another one
- Filter by channel name or programme title
- Refreshes once a minute while the panel is open, and never while it is closed

## Layouts

`grid` (default) is abema.tv/timetable's shape: one column per channel, time
running down, an hour ruler pinned to the left and a bright line on now.
Programmes that run past either edge of the four-hour window are clipped, with
a `↑` where one started earlier. Scroll sideways (or press `h`/`l`) for the
rest of the channels.

`listing` is a newspaper TV column instead: rows grouped under their start
time, each with a progress bar. Slots that began before today carry a `-1d`
mark, so a 21:40 heading is not read as tonight.

Either way, tapping a programme hands it to ABEMA, and tapping a channel's name
or logo opens that one channel: its next day or so of programmes, one row each.
A programme on air now opens the live channel; a later one opens its own page,
because there is no stream to join yet.

## Install

```bash
omarchy plugin add https://github.com/polidog/omarchy-abematv.git --enable
```

`--enable` puts the widget in the bar and asks which section; drop it to add the
plugin without enabling it yet. Later:

```bash
omarchy plugin update io.github.polidog.abematv   # pull a newer version
omarchy plugin remove io.github.polidog.abematv   # uninstall
omarchy bar move io.github.polidog.abematv --section right
```

Plugins run unsandboxed inside `omarchy-shell`, so read the code first — it is
one QML file, one JS file, one shell script and one Python script.

### From a clone, to hack on it

```bash
git clone https://github.com/polidog/omarchy-abematv
cd omarchy-abematv
tools/install-local
```

## Settings

| Key | Default | What it does |
|-----|---------|--------------|
| `layout` | `grid` | `grid` is the timetable grid; `listing` is the newspaper-style list. |
| `openWith` | `webapp` | `webapp` opens a dedicated player window; `browser` opens a tab in the default browser. |
| `showFilter` | `true` | Show the filter box in the panel. |

## Keys

`h` / `l` (or `j` / `k`) move · `Enter` open the channel, then watch the programme under the cursor · `/` filter · `r` refresh · `Esc` back, then close.
Right-clicking the bar button refreshes without opening the panel.

## What it does not do

- **No playback of its own, and no video inside the panel.** ABEMA's linear HLS
  streams are encrypted with ABEMA's own key scheme (`abematv-license://`), so
  only their player can decode them — nothing the shell could render itself.
  This widget is a schedule and a launcher. What it does do is keep the player
  to a single window: picking a channel closes the ABEMA web-app window that is
  already up before opening the new one, so channels replace each other instead
  of stacking. A Hyprland window rule on `class:^(chrome-abema\.tv)` will pin
  that window to wherever you want it.
- **No "later today" in the schedule views.** The endpoint the panel polls
  returns what is on air *now* and takes no date parameters. The full timetable
  is behind a token, so it is fetched only when you open one channel — the grid
  and the listing still show the present.
- **Free tier only.** Anything premium still asks you to sign in, in the player.

The schedule comes from ABEMA's public endpoints (`api.abema.io/v1/channels`
and `/v1/broadcast/slots`), which answer without a token. One channel's own
listing comes from `/v1/timetable/dataSet`, which does not: `bin/abematv-listing`
mints the anonymous device token ABEMA's own clients mint on first run — no
account, no login, nothing to do with playback or DRM — and caches it and the
timetable under `~/.cache/omarchy-abematv`. This is an unofficial plugin and is not affiliated with ABEMA or
CyberAgent.

## Dependencies

All of these ship with Omarchy: `python3` (the listing helper), `curl` (the two
polled endpoints), `jq` and `hyprctl` (finding the ABEMA window to replace), and
`omarchy-launch-webapp` or `omarchy-launch-browser` (opening the player). The
widget writes nothing but its own cache under `~/.cache/omarchy-abematv`.

## Development

```bash
tools/test-model               # the data helpers, without a shell
tools/install-local            # sync into ~/.config/omarchy/plugins
tools/install-local --restart  # QML edits need the shell restarted to take
```

MIT.
