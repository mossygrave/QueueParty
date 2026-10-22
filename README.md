# JamRoom / QueueParty

A Phoenix LiveView application for shared YouTube queues. The project folder can be named `JamRoom`; its Elixir application and modules are named `queue_party` and `QueueParty`.

## Start the project

Install Elixir 1.17 or later with a compatible Erlang/OTP version. Both are already available on the Mac used to prepare this project.

Open a terminal **in the folder containing `mix.exs`**, then run:

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>. No database, YouTube API key, Node.js, or npm installation is needed. The first setup downloads the Elixir dependencies and the esbuild asset builder.

If Mix requests Hex or Rebar, install them and retry:

```sh
mix local.hex --force
mix local.rebar --force
mix setup
```

## Use it with phones

1. Connect the host computer and phones to the same Wi-Fi network.
2. Keep `mix phx.server` running on the computer.
3. Find the computer's local IP in macOS System Settings → Wi-Fi → Details → TCP/IP.
4. Open `http://COMPUTER-IP:4000` on the host and guest devices. A phone's `localhost` points to the phone, not the computer.
5. Start a room on the device that will play the videos. Guests join using its five-character room code or the **Copy invite** link.
6. Add YouTube links. The host clicks **Play first video**. Playback then advances when each video ends.
7. In **Room settings → Play music on**, the host can choose **Host device only** (the default) or **Every device**. The setting changes live for everyone in the room.

With **Every device**, guests get their own YouTube player following the host's current song, play/pause state, and playhead. Late joiners start near the current position. If a browser blocks audio, tap **Play on this device** or the YouTube play button. The host alone advances the queue; guests control their own volume. Switching back to **Host device only** stops the guest players.

The development server is configured to accept connections on the local network. If a phone cannot connect, check the Mac firewall and whether the Wi-Fi network isolates devices. Keep the host page open during playback.

The host address contains a private `?host=...` control token. Use **Copy invite** to share a guest link without that token. If clipboard access is unavailable over local HTTP, the button displays the invite link for manual copying.

## Project structure

```text
JamRoom/
  mix.exs                 # Project definition and dependencies
  mix.lock                # Locked dependency versions
  config/                 # Development, test, and production configuration
  lib/queue_party/         # Room state, queue operations, and link validation
  lib/queue_party_web/     # Router, LiveViews, layouts, and web components
  assets/js/              # LiveView connection and YouTube player integration
  priv/static/            # Styles, images, and built browser assets
  test/                   # Elixir and LiveView tests
```

`mix setup` creates `deps/` and `_build/`. Keep the application files in their shown subfolders; the original five loose files by themselves are not a runnable Phoenix project.

## Verify

```sh
mix precommit
```

This compiles with warnings treated as errors, formats the source, and runs the tests. An optional player-hook test uses Node's built-in test runner:

```sh
node --test test/js/youtube_player_test.mjs
```

## Current limits

- Rooms and queues are kept in memory and are cleared on server restart. This MVP runs on one server instance.
- Every-device playback uses periodic playhead corrections, so synchronization is approximate. YouTube ads, buffering, network delays, and browser background restrictions can cause devices to differ. Keep the host page open to control playback and advance the queue.
- Browsers may require a click on the YouTube Play button before allowing sound. Some videos cannot be embedded; the host can skip them.
- Queue titles show the video ID; title lookup, QR codes, accounts, and moderation are future features.
- Public deployment needs production secrets, HTTPS, and a hosting setup. These local development instructions do not deploy the app.
