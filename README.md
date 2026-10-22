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
6. Add YouTube links. The host clicks **Play first video**. Playback then advances when each video ends.
7. In **Room settings → Play music on**, the host can choose **Host device only** (the default) or **Every device**. The setting changes live for everyone in the room.

With **Every device**, guests get their own YouTube player following the host's current song, play/pause state, and playhead. Late joiners start near the current position. If a browser blocks audio, tap **Play on this device** or the YouTube play button. The host alone advances the queue; guests control their own volume. Switching back to **Host device only** stops the guest players.

The development server is configured to accept connections on the local network. If a phone cannot connect, check the Mac firewall and whether the Wi-Fi network isolates devices. Keep the host page open during playback.

The host address contains a private `?host=...` control token. Use **Copy invite** to share a guest link without that token. If clipboard access is unavailable over local HTTP, the button displays the invite link for manual copying.

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
2. Keep the creator's tab open; its private `?host=...` URL grants room controls. Share **Copy invite**, not the host URL.
3. Guests open the invite on their phones or join using the room code.
4. The host chooses **Room settings → Play music on → Host device only** or **Every device**. This setting is hidden in the guest view.
5. Add videos and choose **Play first video**. In every-device mode, guests may need to tap **Play on this device** to allow audio.

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

- Rooms and queues are kept in memory and are cleared on server restart. This MVP runs on one server instance.
- Every-device playback uses periodic playhead corrections, so synchronization is approximate. YouTube ads, buffering, network delays, and browser background restrictions can cause devices to differ. Keep the host page open to control playback and advance the queue.
- Browsers may require a click on the YouTube Play button before allowing sound. Some videos cannot be embedded; the host can skip them.
- Queue titles show the video ID; title lookup, QR codes, accounts, and moderation are future features.
- The documented Render setup requires production environment variables and a successful live deployment. Changing local files alone does not update the hosted site.
