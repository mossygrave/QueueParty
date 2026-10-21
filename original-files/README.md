# QueueParty

QueueParty is a Phoenix LiveView MVP for collaborative YouTube listening rooms.

## MVP flow

1. Start a room from the home page.
2. Share the room code or `/room/CODE` URL.
3. Guests paste YouTube links into the shared queue.
4. The host starts or skips videos; the queue updates live for everyone.

## Run locally

```sh
mix deps.get
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000).

This first version keeps rooms in memory, so restarting the server clears rooms. The next production steps are PostgreSQL persistence, stronger host identity, moderation/rate limits, and QR-code generation.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
