# QueueParty

A Phoenix LiveView application for shared YouTube queues. The project folder can be named `JamRoom`; its Elixir application and modules are named `queue_party` and `QueueParty`.

## Hosting

QueueParty uses **Render for public hosting** and **GitHub for source control**. This Phoenix application needs a running Elixir server; GitHub Pages cannot run its LiveViews or shared room state.

On the hosted site, everyone opens the same Render HTTPS address. Devices do not need to share Wi-Fi, and your computer does not need to keep a local server running. The person who creates a room is its host; running the website and hosting a listening room are different roles.

The sections below cover local development and the Render deployment configuration. No public site address is listed here yet.

## Start the project locally

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

## Use it with phones on local Wi-Fi

1. Connect the host computer and phones to the same Wi-Fi network.
2. Keep `mix phx.server` running on the computer.
3. Find the computer's local IP in macOS System Settings → Wi-Fi → Details → TCP/IP.
4. Open `http://COMPUTER-IP:4000` on the host and guest devices. A phone's `localhost` points to the phone, not the computer.
5. Start a room on the device that will play the videos. Guests join using its five-character room code or the **Copy invite** link.
6. Add YouTube links. The first video starts automatically when the room is idle; later submissions join the queue. Playback advances when each video ends. If the queue runs out, the next submitted video starts a new listening session automatically. Adding a video does not interrupt or resume a paused song.
7. Open **Host controls** next to the invite button, then use **Room settings → Play music on** to choose **Host device only** (the default) or **Every device**. The setting changes live for everyone in the room.

**Host controls** starts collapsed to keep the player and queue in view. It contains playback mode, skip-vote settings, host transfer, and background playlist controls. Toggle the button again, choose **Close**, or press Escape to collapse it. Closing the panel does not stop playback or an in-progress playlist import. Skip/approve-skip buttons and queue reordering stay beside the player and queue for quick access. The panel is host-only and follows host transfers.

With **Every device**, guests get their own YouTube player following the host's current song, play/pause state, and playhead. Late joiners start near the current position. If a browser blocks audio, tap **Play on this device** or the YouTube play button. The host controls playback; guest skip requests can also advance the queue at the configured vote threshold. Guests control their own volume. Switching back to **Host device only** stops the guest players.

Video titles are fetched in the background from YouTube's public oEmbed endpoint, without an API key. They appear in **Play next** and **Now playing** for everyone in the room. Playback starts immediately; a video-ID label is shown until its title arrives. If YouTube is unavailable, rate-limits the lookup, or cannot return metadata for a video, that fallback label stays and playback is unaffected. New submissions are looked up; existing items are not automatically backfilled after an upgrade.

The host can reorder **Play next** by dragging a song's grip with a mouse or touch. An orange line shows the drop position. For keyboard access, focus a grip and use the up/down arrow keys; Escape cancels an active drag. Everyone receives the new order immediately. Reordering never interrupts the current video or changes the background playlist. New submissions are preserved if they arrive during a drag; if the moved song or its destination has already left the queue, the move is safely rejected. Guests cannot reorder, and host controls follow a host transfer.

### Background playlists and Play next

The host can use **Background playlist → Public YouTube playlist URL → Load / replace playlist** to import one public playlist, up to **200 entries**. Loading happens in the background, without stopping playback. Private/unlisted playlists and automatically generated YouTube Mix (`RD…`) links are not supported.

- Individually submitted songs enter **Play next**, in submission order. The current song is never interrupted.
- When a song ends or is skipped, Play next is checked first. When requests run out, the host playlist resumes at its next track.
- A successful import starts automatically if the room is idle. Replacing a playlist leaves the current song and requests intact, and starts the replacement from its beginning on its next turn.
- **Repeat playlist** is off by default. Enable it to restart the playlist after its last track, while continuing to prioritize requests. Enabling repeat on an exhausted playlist restarts it automatically if the room is idle.
- **Remove playlist** cancels future playlist tracks (and any pending import); the current video finishes normally and individual requests remain.
- Everyone sees the loaded title and a preview of up to 10 upcoming playlist tracks. Each import is a snapshot; load it again to pick up later edits on YouTube. Imports that fail leave the previous playlist unchanged.
- Private/deleted entries are filtered during import. Playlist videos rejected by the host's player as unavailable or non-embeddable are skipped and excluded from later repeats in that room. If none remain, the playlist stops rather than looping through errors. Other player failures still allow the host to retry or skip manually.

Playlist position, repeat settings, and requests survive a host handoff, but still follow the room's normal in-memory restart and expiration rules. Guest skip votes apply to playlist songs as well as individual requests.

#### Optional YouTube Data API setup

Individual links and public title lookups still work without an API key. **Playlist imports require one server-side YouTube Data API v3 key**:

1. Create a Google Cloud project, enable **YouTube Data API v3**, and create an API key. Restrict the key to that API. See [Google's setup guide](https://developers.google.com/youtube/v3/getting-started).
2. In Render, add **Environment → Environment Variables → `YOUTUBE_API_KEY`**, set its value privately, and redeploy. No secret file is needed.
3. For local development, set `YOUTUBE_API_KEY` in the terminal environment before starting Phoenix. Never commit the actual key, paste it into a room, or put it in browser-side code.

Imports fetch playlist metadata and then pages of up to 50 entries using Req. A 200-entry playlist normally needs five requests: one metadata request plus four item-page requests. Missing credentials, API restrictions/quota problems, timeouts, empty playlists, and size limits are explained in the host's import form. See [playlist metadata](https://developers.google.com/youtube/v3/docs/playlists/list) and [playlist items](https://developers.google.com/youtube/v3/docs/playlistItems/list).

### Guest skip requests

While a song is playing, guests can select **Request skip**. Everyone sees the vote count, and the host can select **Approve skip** without waiting for the threshold. At the configured threshold, the song skips automatically—even if there are no more queued videos, in which case playback stops.

The host sets **Room settings → Votes needed to skip** and clicks **Save**. The default is **3**, with a permitted range of **1–100**; no room-size calculation is used. Lowering the threshold applies immediately to existing votes. Votes reset whenever the current song changes, including manual skips and natural endings.

Each browser session can vote once per song, including across refreshes and tabs sharing that session. This is lightweight duplicate prevention, not account-based voting: another browser, private session, or cleared cookies can vote separately. Keep the host link private.

The development server is configured to accept connections on the local network. If a phone cannot connect, check the Mac firewall and whether the Wi-Fi network isolates devices. Keep the host page open during playback.

The creator's address contains a private `?host=...` control token used to claim the room on its first connection. Host ownership is then tied to that browser session. Use **Copy invite** to share a guest link without the token. If clipboard access is unavailable over local HTTP, the button displays the invite link for manual copying.

### Host handoff and disconnects

- For a planned departure, use **Room settings → Transfer host**, choose a connected guest, and select **Pass host controls**. Guests are identified by their display names and a guest number; changing **Your name** updates the list.
- If the host's last room tab disconnects, everyone sees a reconnecting notice. After **30 seconds from server-side disconnection detection**, the longest continuously connected guest becomes host automatically. Returning within the grace period keeps the original host in charge.
- If no guests are connected when grace expires, the room waits. The previous host can return in the same browser session; otherwise, the next guest who joins takes over.
- Multiple tabs sharing the host's browser session share ownership. Closing one does not trigger a handoff while another room tab is connected. Test separate people using separate browsers or private sessions.
- Handoff preserves the current song, queue, playback mode, and skip votes. Former hosts become guests, and their previous host control token no longer works. Returning after a transfer does not take ownership back.
- The new host can return to the room from the same browser session without a special URL. Clearing cookies or changing browsers loses that session identity; this MVP has no account-based host recovery.

Every-device listeners keep playing during the reconnection window if the song was playing; normal end-of-song advancement resumes when a host is available. In host-device-only mode, sound stops when the host leaves and moves to the successor after handoff. A new host may need to press Play if their browser blocks autoplay. Rooms still disappear on a server restart or redeploy.

### Empty-room cleanup

When the last connected room tab leaves, the server keeps the room for **15 minutes**. Returning before cleanup cancels the timer and preserves the queue and settings. Once everyone leaves again, a fresh 15-minute window starts. The 30-second host handoff window runs separately and does not extend this deadline.

After 15 continuously empty minutes, the room and its queue, settings, and votes are deleted and cannot be recovered. Old invite links show that the room no longer exists; start a new room instead. Newly created rooms that nobody ever joins also expire after 15 minutes. Merely loading a page or adding an item without a connected room tab does not keep an empty room alive.

## Deploy on Render

### Service configuration

Create a Render **Web Service** connected to the [QueueParty GitHub repository](https://github.com/mossygrave/QueueParty), with language **Elixir** and branch **main**. Leave **Root Directory** blank when `mix.exs` is at the repository root. Do not deploy `original-files/`; it is a backup, not the runnable application.

Set **Build Command** to:

```sh
mix deps.get --only prod && mix compile && mix assets.setup && mix assets.deploy && mix release
```

Set **Start Command** to:

```sh
_build/prod/rel/queue_party/bin/queue_party start
```

The build installs dependencies, compiles the application, builds browser assets, and assembles the release used by the start command. `mix phx.digest` alone is not a complete build command.

### Environment variables

In Render's **Environment → Environment Variables**, add:

- `MIX_ENV`: `prod`
- `PHX_SERVER`: `true`
- `PHX_HOST`: your service hostname, such as `your-service.onrender.com`, without `https://` or a trailing slash
- `SECRET_KEY_BASE`: a private value generated locally with `mix phx.gen.secret`

Generate the secret from the folder containing `mix.exs`:

```sh
mix phx.gen.secret
```

Paste the output only into Render's `SECRET_KEY_BASE` value. Do not commit it to GitHub or put it in this README. This app reads environment variables directly, so a Render **Secret File** is not needed. Render supplies `PORT`, which the app reads automatically.

See Render's [Phoenix deployment guide](https://render.com/docs/deploy-phoenix) for platform background. The commands above use this project's existing release configuration.

### Publish updates

Commit and push changes from your local repository:

```sh
git add README.md
git commit -m "Document Render hosting"
git push origin main
```

For application changes, stage the relevant changed files instead of only `README.md`.

With a connected GitHub account and **Settings → Auto-Deploy → On Commit**, Render rebuilds and deploys pushes to `main`. If auto-deploy is off, or the service was created using only a public repository URL, use **Manual Deploy → Deploy latest commit**. **Restart service** restarts the existing deployed commit; it does not fetch new code. See [Render's deployment documentation](https://render.com/docs/deploys).

Wait for the deployment to be marked **Live**, not just **Build successful**, then reload the site. Check that the live deployment shows the expected commit. A failed deployment can leave the previous version running. For suspected stale build artifacts, Render also provides **Clear build cache & deploy**.

### Use the hosted site

1. Open your service's HTTPS address and choose **Start a room**.
2. The creator's browser session receives host controls. Share **Copy invite**, not the private creator URL. Use **Transfer host** before leaving, or let the disconnect grace period select a successor.
3. Guests open the invite on their phones or join using the room code.
4. The host chooses **Room settings → Play music on → Host device only** or **Every device**. This setting is hidden in the guest view.
5. Add a video to start playback automatically. Browsers may still require the host to tap the YouTube play button to allow sound; in every-device mode, guests can tap **Play on this device**. Automatic queue startup does not bypass browser autoplay restrictions.

Local and hosted rooms are separate. A room created on `localhost` cannot be joined through the Render site.

On Render's Free plan, a service spins down after 15 minutes without inbound traffic and can take about a minute to wake. Rooms and queues are in memory, so restarts, redeploys, and spin-downs clear them. Keep this deployment to **one server instance** until shared persistent room storage is added. See [Render's free-service limits](https://render.com/docs/free).

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

- Rooms and queues are kept in memory, deleted after 15 minutes with no connected participants, and cleared on server restart. This MVP runs on one server instance.
- Every-device playback uses periodic playhead corrections, so synchronization is approximate. YouTube ads, buffering, network delays, and browser background restrictions can cause devices to differ. Keep the host page open to control playback and advance the queue.
- Browsers may require a click on the YouTube Play button before allowing sound. Some videos cannot be embedded; the host can skip them.
- Public video titles depend on YouTube metadata availability. QR codes, accounts, and moderation are future features.
- The documented Render setup requires production environment variables and a successful live deployment. Changing local files alone does not update the hosted site.
