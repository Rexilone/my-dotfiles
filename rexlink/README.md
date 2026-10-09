# Rexlink

The phone link of Rexilone Shell: Android phones, tablets and watches on the desktop.
Here it is a **system service** (`rexlink.service`) with no window or tray icon of its own —
the interface is **Settings → Phone**, the phone module in the bar, the desktop widget,
the incoming call card and the quick reply popup.

| Path | What |
|------|------|
| `rexlink/` | the service (Python + PySide6, no GUI) |
| `rexlink.apk`, `apk.json` | the Android app; devices update from it automatically |
| `system/` | v4l2loopback config (webcam) and the ufw profile |
| `../home/.local/bin/rexlink` | launcher (`rexlink`, `rexlink ctl …`) |
| `../home/.config/systemd/user/rexlink.service` | the user service |

`./install.sh` links the launcher and the unit, enables the service and opens the ports in ufw;
`--with-webcam` also installs v4l2loopback. On NixOS the service is part of `nixos/modules/system.nix`
(`rexilone.webcam.enable` for the webcam).

## Connecting a device

1. Install `rexlink.apk` on the device and open it.
2. The device and the computer must be on the same network. Pick the computer in the list or enter its address.
3. Check the six-digit code on both screens and press **Pair** (in Settings → Phone or in the notification).
4. In the app: grant the permissions you need (notifications, SMS, phone, accessibility for control) and turn off battery optimization.

Ports: TCP 47820 (TLS), UDP 47821 (discovery). If devices see the computer but don't connect, it's the
firewall — Settings → Phone shows a warning with an **Open ports** button.

Everything goes over TLS. The computer's certificate (`~/.config/rexlink/cert.pem`) is pinned on the device
at pairing; the pairing code is derived from it on both sides, so a substitution shows up as a code mismatch.
Settings and paired devices — `~/.config/rexlink/config.json`.

## API

Everything Settings → Phone does is available to scripts. Unix socket
`$XDG_RUNTIME_DIR/rexlink/rexlink.sock`, JSON lines:

```
→ {"id": 1, "cmd": "devices"}
← {"id": 1, "ok": true, "result": [...]}
← {"id": 2, "ok": false, "error": "…"}
```

Without `device` a command goes to the current device (`select`). A state snapshot is also written to
`$XDG_RUNTIME_DIR/rexlink/state.json` on every change.

```sh
rexlink ctl devices
rexlink ctl ring device=<id>
rexlink ctl notif_reply key='<key>' action=1 text='On my way'
rexlink ctl send_files paths='["~/doc.pdf"]'
rexlink ctl '{"cmd": "sms_send", "address": "+15551234567", "body": "hi"}'
rexlink ctl watch                        # all events
rexlink ctl watch call notification      # only these
rexlink --send ~/photo.jpg               # send files to the current device
qs ipc call rexlink open files           # open Settings → Phone → Files
```

### Commands

| Command | Parameters | Result |
|---|---|---|
| `ping`, `version`, `state` | | `"pong"`, `{version, api}`, snapshot |
| `subscribe` / `unsubscribe` | `events?: [names]` | events start coming to this connection |
| **Devices** | | |
| `devices` | | `[{id, name, kind, model, online, address, battery, charging, notifications, current, ringing, appVersion, update}]` |
| `device` | `device?` | details: `status`, `media`, `call`, `caps`… |
| `select` · `rename` · `forget` | `device` · `device, name` · `device` | |
| `pairing` · `pair_answer` | · `device?, accept` | current pairing request · accept / decline |
| `update_device` · `apk` | `device?` · | update the app on the device · bundled APK version |
| **Notifications** | | |
| `notifications` | `device?` | `[{key, app, title, text, time, icon, actions:[{i, title, reply}], clearable}]` |
| `notif_action` · `notif_reply` | `key, action` · `key, action, text` | press an action · quick reply |
| `notif_dismiss` · `notif_dismiss_all` | `key` · | dismiss (on the device too) |
| **Media, calls, SMS** | | |
| `media` | `action?, value?` | state; `toggle play pause next prev stop seek` (`value` in ms) |
| `pc_media` | `action?` | the PC player (MPRIS) |
| `call` · `dial` | `action?` (`accept reject silence`) · `number` | |
| `sms_threads` · `sms_messages` | · `thread` | the list comes as an event |
| `sms_open` · `sms_state` · `sms_send` | `thread` (`""` — new) · · `address, body` | open conversation for the UI |
| **Clipboard, files** | | |
| `clipboard_pull` · `clipboard_history` · `clipboard_clear` | | |
| `send_files` | `paths` | |
| `transfers` · `transfer_cancel` · `transfers_clear` | · `fid` · | `[{fid, name, size, done, dir, state, speed, device}]` |
| `ring` | | find the device |
| **Webcam and screen** | | |
| `camera_start` · `camera_stop` · `camera` · `camera_switch` | · · · `facing` | v4l2loopback webcam |
| `screen_start` · `screen_stop` · `screen` | | showing the device screen |
| `screen_off` | `off` | turn the device panel off, keep the picture and control (ADB) |
| `adb_info` · `adb_pair` · `adb_connect` | · `port, code` · `port` | wireless debugging for “screen off” |
| `input` | `kind, …` | `tap {x,y}`, `long {x,y}`, `swipe {points, duration}`, `scroll {x,y,dy}`, `key {key}`, `text {text}`; coordinates 0…1 |
| `frames` | `channel, on` | watch a video channel (`screen:<id>`, `camera`): frames come as `frame` events |
| **Settings** | | |
| `settings` · `set` | · `key, value` | see `~/.config/rexlink/config.json`; `lang` — `ru` / `en` |
| `download_dir` · `autostart` · `firewall_check` | `path` · `on` · | |
| `show` | `page?` | asks the shell to open Settings → Phone (event `show`) |

Keys for `input` with `kind=key`: `back home recents notifications quick power lock screenshot volup voldown
enter backspace delete left right up down tab paste`.

### Events

`{"event": "<name>", "data": {...}}`

| Event | Data |
|---|---|
| `device_connected` / `device_disconnected` | `{id, name, kind, model, address, caps}` / `{id}` |
| `devices` | the device list (on any change) |
| `pair_request` / `pair_finished` | `{id, name, code}` / `{id}` |
| `status` | `{device, battery, charging, plug, temp, net, wifi:{ssid, level}, cell:{operator, gen, level}}` |
| `notification` / `notification_removed` | a notification + `device` / `{device, key}` |
| `media` / `pc_media` | the player state |
| `call` | `{device, state: ringing\|offhook\|idle\|missed, number, name}` |
| `sms_received` · `sms_threads` · `sms_messages` · `sms_sent` · `sms_state` | |
| `clipboard` / `clips` | one sync / the history |
| `transfers` / `transfer` | the list with progress / a finished transfer |
| `camera` · `camera_state` · `screen` · `screen_state` | video state (`screen_state` — every device, with ADB details) |
| `frame` | `{channel, path, w, h, seq}` — the latest frame as a JPEG in `$XDG_RUNTIME_DIR/rexlink/frames/` |
| `settings` | the settings (on any change) |
| `toast` · `show` · `reply_request` | a short message · open a page · quick reply asked from a notification |

Device kinds: `phone`, `tablet`, `watch`. `caps`: `notifications clipboard files media screen status calls sms camera`.

## Protocol

Frame = `u32 length | JSON | binary`; video = `u32 length | u8 type | data`
(0 — JSON `{w, h}`, 1 — H.264 Annex-B, SPS/PPS before every keyframe).
