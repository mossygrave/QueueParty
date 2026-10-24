import test from "node:test"
import assert from "node:assert/strict"
import hook from "../../assets/js/youtube_player.mjs"

test("player errors identify the active item and ignore stale-video errors", async t => {
  const {player, sent, context} = await mount(t)
  player.config.events.onError({data: 150})
  assert.deepEqual(sent.at(-1), ["player_error", {item_id: "first-item", code: 150}])
  context.el.dataset.videoId = "different-video"
  const count = sent.length
  player.config.events.onError({data: 150})
  assert.equal(sent.length, count)
})

test("host handoff changes reporting authority without restarting the song", async t => {
  const {player, states, sent, update, tick, calls} = await mount(t, {host: false, position: 42})
  player.emit(states.PLAYING)
  update({host: "true", playbackPosition: "42"})
  assert.equal(calls.filter(([name]) => name === "load").length, 1)
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "playing", position: 42}])
  update({host: "false", playbackPosition: "43"})
  const count = sent.length
  tick()
  player.emit(states.ENDED)
  assert.equal(sent.length, count, "former host must stop reporting and advancing the queue")
})

test("a guest promoted after the song ended can advance it", async t => {
  const {player, states, sent, update} = await mount(t, {host: false})
  player.emit(states.PLAYING)
  player.emit(states.ENDED)
  assert.equal(sent.length, 0)
  update({host: "true"})
  assert.deepEqual(sent.at(-1), ["video_ended", {item_id: "first-item"}])
})

test("buffering snapshots never repeatedly rewind or pause a guest", async t => {
  const {player, states, receive, tick, calls} = await mount(t, {host: false})
  player.emit(states.PLAYING)
  receive({item_id: "first-item", status: "buffering", position: 0, revision: 2})
  player.position = 2
  tick(); tick(); tick()
  assert.equal(calls.filter(([name]) => name === "seek" || name === "pause").length, 0)
  assert.equal(player.position, 2)
  receive({item_id: "first-item", status: "playing", position: 10, revision: 3})
  assert.deepEqual(calls.at(-1), ["seek", 10])
})

test("guests finish loading before drift correction and do not restart ended songs", async t => {
  const {player, states, receive, tick, advance, calls, update} = await mount(t, {host: false})
  advance(5000); tick(); tick()
  assert.equal(calls.length, 1, "do not keep seeking a player that is still loading")
  player.position = 100
  player.emit(states.PLAYING)
  player.emit(states.ENDED)
  const count = calls.length
  tick(); tick()
  receive({item_id: "first-item", status: "playing", position: 100, revision: 2})
  assert.equal(calls.length, count, "wait for the host's next track, rather than replaying")
  update({itemId: "next-item", videoId: "next-video", playbackPosition: "0", playbackRevision: "3"})
  assert.deepEqual(calls.at(-1), ["load", {videoId: "next-video", startSeconds: 0}])
})

test("a lagging promoted host waits for an asynchronous seek before reporting", async t => {
  const {player, states, update, tick, sent, calls} = await mount(t, {host: false})
  player.emit(states.PLAYING)
  player.seekTo = position => { calls.push(["seek", position]); player.state = states.BUFFERING }
  update({host: "true", playbackPosition: "45", playbackRevision: "2"})
  tick(); tick()
  assert.equal(sent.length, 0, "do not overwrite the room's playhead with zero")
  assert.equal(calls.filter(([name]) => name === "seek").length, 1)
  player.position = 45
  player.emit(states.PLAYING)
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "playing", position: 45}])
  player.emit(states.ENDED)
  tick(); player.emit(states.ENDED)
  assert.equal(sent.filter(([name]) => name === "video_ended").length, 1)
  update({itemId: "playlist-b", videoId: "second-video", playbackPosition: "0", playbackRevision: "3"})
  player.emit(states.PLAYING); player.emit(states.ENDED)
  assert.deepEqual(sent.at(-1), ["video_ended", {item_id: "playlist-b"}])
})

test("an autoplay-blocked promotion preserves the room position until the host enables audio", async t => {
  const {player, states, context, update, tick, sent, elementListeners} = await mount(t, {host: false})
  player.config.events.onAutoplayBlocked()
  sent.length = 0
  update({host: "true", playbackPosition: "45", playbackRevision: "2"})
  tick()
  assert.equal(sent.length, 0)
  assert.equal(context.handoff.prepared, false)
  elementListeners.get("queueparty:enable-audio")()
  assert.equal(player.position, 45)
  player.emit(states.PLAYING)
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "playing", position: 45}])
})

test("promotion can settle a paused, never-started player without playing it", async t => {
  const {player, states, update, sent, calls} = await mount(t, {host: false, status: "paused", position: 0})
  update({host: "true", playbackStatus: "paused", playbackPosition: "45", playbackRevision: "2"})
  assert.equal(player.state, states.PAUSED)
  assert.equal(calls.some(([name]) => name === "play"), false)
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "paused", position: 45}])
  player.emit(states.PLAYING); player.emit(states.ENDED)
  assert.deepEqual(sent.at(-1), ["video_ended", {item_id: "first-item"}])
})

test("demotion cancels a pending handoff and late callbacks cannot report or finish", async t => {
  const {player, states, update, tick, sent} = await mount(t, {host: false})
  player.seekTo = () => { player.state = states.BUFFERING }
  update({host: "true", playbackPosition: "45", playbackRevision: "2"})
  update({host: "false", playbackPosition: "45", playbackRevision: "3"})
  player.position = 45
  player.emit(states.PLAYING); player.emit(states.ENDED); tick()
  assert.equal(sent.length, 0)
})

test("late wrong-video ends, duplicate ends and offline ends cannot advance the room", async t => {
  const {context, player, sent, states, tick} = await mount(t)
  player.emit(states.PLAYING)
  player.videoId = "previous-video"
  player.emit(states.ENDED)
  assert.equal(sent.some(([name]) => name === "video_ended"), false)
  player.videoId = "first-video"
  hook.disconnected.call(context)
  player.emit(states.ENDED)
  assert.equal(sent.some(([name]) => name === "video_ended"), false)
  hook.reconnected.call(context)
  tick(); player.emit(states.ENDED)
  assert.equal(sent.filter(([name]) => name === "video_ended").length, 1)
})

test("promotion does not replace a newer received snapshot with stale DOM data", async t => {
  const {player, states, receive, update, sent} = await mount(t, {host: false})
  player.emit(states.PLAYING)
  receive({item_id: "first-item", status: "paused", position: 90, revision: 5})
  update({host: "true", playbackPosition: "0", playbackRevision: "1"})
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "paused", position: 90}])
})

test("promotion while the guest is cued for host buffering starts playback at the saved position", async t => {
  const {player, states, update, sent, calls} = await mount(t, {host: false, status: "paused"})
  update({host: "true", playbackStatus: "buffering", playbackPosition: "45", playbackRevision: "2"})
  player.emit(states.PLAYING)
  assert.equal(calls.some(([name, position]) => name === "seek" && position === 45), true)
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "playing", position: 45}])
  player.emit(states.ENDED)
  assert.deepEqual(sent.at(-1), ["video_ended", {item_id: "first-item"}])
})

test("a new track arriving during handoff cancels the old seek and stale end", async t => {
  const {player, states, update, sent, calls} = await mount(t, {host: false})
  player.seekTo = position => { calls.push(["seek", position]); player.state = states.BUFFERING }
  update({host: "true", playbackPosition: "45", playbackRevision: "2"})
  update({itemId: "playlist-b", videoId: "second-video", playbackPosition: "0", playbackRevision: "3"})
  player.emit(states.ENDED)
  assert.equal(sent.some(([name]) => name === "video_ended"), false)
  assert.deepEqual(calls.at(-1), ["load", {videoId: "second-video", startSeconds: 0}])
  player.emit(states.PLAYING); player.emit(states.ENDED)
  assert.deepEqual(sent.at(-1), ["video_ended", {item_id: "playlist-b"}])
})

test("host-only handoff with a fresh player cannot report its initial zero position", async t => {
  const {player, states, sent, tick} = await mount(t, {position: 45})
  player.position = 0
  player.emit(states.PLAYING); tick()
  assert.equal(sent.length, 0)
  player.position = 45
  player.emit(states.PLAYING)
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "playing", position: 45}])
})

test("promotion before the API is ready keeps its synchronization guard", async t => {
  const {context, player, states, update, sent, calls} = await mount(t, {host: false, deferReady: true})
  update({host: "true", playbackPosition: "45", playbackRevision: "2"})
  assert.notEqual(context.handoff, null)
  player.config.events.onReady()
  assert.deepEqual(calls.at(-1), ["load", {videoId: "first-video", startSeconds: 45}])
  assert.equal(sent.length, 0)
  player.emit(states.PLAYING)
  assert.equal(sent.at(-1)[1].position, 45)
})

test("reconnecting a blocked guest refreshes the snapshot without retrying autoplay", async t => {
  const {context, player, calls, server} = await mount(t, {host: false})
  player.config.events.onAutoplayBlocked()
  const count = calls.length
  server({item_id: "first-item", status: "playing", position: 45, revision: 2})
  hook.reconnected.call(context)
  assert.equal(context.snapshot.position, 45)
  assert.equal(calls.length, count)
})

test("a blocked new host tapping the YouTube player catches up before reporting", async t => {
  const {player, states, update, sent, calls} = await mount(t, {host: false})
  player.config.events.onAutoplayBlocked()
  sent.length = 0
  update({host: "true", playbackPosition: "45", playbackRevision: "2"})
  player.seekTo = position => { calls.push(["seek", position]); player.state = states.BUFFERING }
  player.emit(states.PLAYING)
  assert.equal(sent.length, 0)
  assert.deepEqual(calls.at(-1), ["seek", 45])
  player.position = 45
  player.emit(states.PLAYING)
  assert.equal(sent.at(-1)[1].position, 45)
})

async function mount(t, {host = true, position = 0, status = "playing", destroyBeforeAPI = false, deferReady = false} = {}) {
  let clock = 0
  let tick
  const calls = []
  const sent = []
  const handlers = new Map()
  const elementListeners = new Map()
  const documentListeners = new Map()
  const states = {PLAYING: 1, PAUSED: 2, BUFFERING: 3, ENDED: 0, CUED: 5}
  let serverSnapshot

  class Player {
    constructor(target, config) {
      this.target = target
      this.config = config
      this.videoId = config.videoId
      this.position = 0
      this.state = states.CUED
    }
    getCurrentTime() { return this.position }
    getPlayerState() { return this.state }
    getVideoData() { return {video_id: this.videoId} }
    loadVideoById(video) {
      calls.push(["load", video])
      this.videoId = video.videoId
      this.position = video.startSeconds
      this.state = states.BUFFERING
    }
    cueVideoById(video) {
      calls.push(["cue", video])
      this.videoId = video.videoId
      this.position = video.startSeconds
      this.state = states.CUED
    }
    playVideo() { calls.push(["play"]); this.state = states.PLAYING }
    pauseVideo() { calls.push(["pause"]); this.state = states.PAUSED }
    seekTo(position) { calls.push(["seek", position]); this.position = position }
    destroy() { calls.push(["destroy"]) }
    emit(state) { this.state = state; this.config.events.onStateChange({data: state}) }
  }

  const previousWindow = globalThis.window
  const previousDocument = globalThis.document
  globalThis.window = {YT: {Player, PlayerState: states}, location: {origin: "http://localhost:4000"}}
  globalThis.document = {
    createElement: tag => ({tag}), visibilityState: "visible",
    addEventListener: (name, callback) => documentListeners.set(name, callback),
    removeEventListener: name => documentListeners.delete(name)
  }
  t.mock.method(performance, "now", () => clock)
  t.mock.method(globalThis, "setInterval", callback => { tick = callback; return 7 })
  t.mock.method(globalThis, "clearInterval", id => calls.push(["clearInterval", id]))

  const context = {
    el: {
      dataset: {videoId: "first-video", itemId: "first-item", host: String(host), playbackStatus: status, playbackPosition: String(position), playbackRevision: "1"},
      replaceChildren(child) { this.child = child },
      addEventListener: (name, callback) => elementListeners.set(name, callback),
      removeEventListener: name => elementListeners.delete(name)
    },
    handleEvent: (name, callback) => handlers.set(name, callback),
    pushEvent(event, data, reply) {
      sent.push([event, data])
      if (event === "request_playback") reply({playback: serverSnapshot})
    }
  }

  t.after(() => {
    if (!context.disposed) hook.destroyed.call(context)
    globalThis.window = previousWindow
    globalThis.document = previousDocument
  })
  hook.mounted.call(context)
  if (destroyBeforeAPI) hook.destroyed.call(context)
  await Promise.resolve()
  if (!destroyBeforeAPI && !deferReady) context.player.config.events.onReady()

  return {
    context, calls, sent, states, elementListeners, documentListeners,
    player: context.player,
    tick: () => tick(),
    advance: milliseconds => { clock += milliseconds },
    receive: snapshot => handlers.get("room_playback")(snapshot),
    server: snapshot => { serverSnapshot = snapshot },
    update: data => { Object.assign(context.el.dataset, data); hook.updated.call(context) }
  }
}

test("host preserves the wrapper and starts near the saved position", async t => {
  const {context, player, calls} = await mount(t, {position: 50})
  assert.equal(player.target, context.el.child)
  assert.notEqual(player.target, context.el)
  assert.deepEqual(calls, [["load", {videoId: "first-video", startSeconds: 50}]])
})

test("host reports pause, seek and periodic playhead samples", async t => {
  const {player, sent, states, tick} = await mount(t)
  player.position = 12
  player.emit(states.PLAYING)
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "playing", position: 12}])
  player.position = 70
  player.emit(states.PAUSED)
  assert.deepEqual(sent.at(-1), ["playback_update", {item_id: "first-item", status: "paused", position: 70}])
  player.position = 80
  tick()
  assert.equal(sent.at(-1)[1].position, 80)
})

test("only a started host item can advance the queue, including repeated videos", async t => {
  const {player, sent, states, update} = await mount(t)
  player.emit(states.PLAYING)
  player.emit(states.ENDED)
  assert.deepEqual(sent.at(-1), ["video_ended", {item_id: "first-item"}])
  update({itemId: "second-item", playbackRevision: "2", playbackPosition: "0"})
  const count = sent.length
  player.emit(states.ENDED)
  assert.equal(sent.length, count)
  player.emit(states.PLAYING)
  player.emit(states.ENDED)
  assert.deepEqual(sent.at(-1), ["video_ended", {item_id: "second-item"}])
})

test("guest joins the current position and follows host pause and resume", async t => {
  const {player, calls, sent, receive, states} = await mount(t, {host: false, position: 42})
  assert.deepEqual(calls[0], ["load", {videoId: "first-video", startSeconds: 42}])
  player.emit(states.PLAYING)
  receive({item_id: "first-item", status: "paused", position: 75, revision: 2})
  assert.deepEqual(calls.slice(-2), [["seek", 75], ["pause"]])
  receive({item_id: "first-item", status: "playing", position: 75, revision: 3})
  assert.deepEqual(calls.at(-1), ["play"])
  player.emit(states.ENDED)
  assert.equal(sent.length, 0, "a guest must not report host state or advance the queue")
})

test("a paused late joiner stays paused and stale snapshots cannot rewind it", async t => {
  const {calls, receive, player, states} = await mount(t, {host: false, status: "paused", position: 60})
  assert.deepEqual(calls[0], ["cue", {videoId: "first-video", startSeconds: 60}])
  assert.equal(player.state, states.CUED)
  receive({item_id: "first-item", status: "paused", position: 90, revision: 3})
  const count = calls.length
  receive({item_id: "first-item", status: "playing", position: 0, revision: 2})
  receive({item_id: "old-item", status: "playing", position: 0, revision: 4})
  assert.equal(calls.length, count)
  assert.equal(player.position, 90)
})

test("guests correct drift without seeking on small timing differences", async t => {
  const {player, calls, advance, tick, states} = await mount(t, {host: false, position: 50})
  player.emit(states.PLAYING)
  advance(2000)
  player.position = 51.8
  tick()
  assert.equal(calls.filter(([name]) => name === "seek").length, 0)
  player.position = 10
  tick()
  assert.deepEqual(calls.at(-1), ["seek", 52])
})

test("blocked guest audio waits for a tap, then catches up", async t => {
  const {player, calls, sent, elementListeners, advance, tick} = await mount(t, {host: false})
  player.state = 5
  player.config.events.onAutoplayBlocked()
  assert.deepEqual(sent.at(-1), ["autoplay_blocked", {}])
  const count = calls.length
  advance(10000)
  tick()
  assert.equal(calls.length, count, "do not repeatedly retry blocked autoplay")
  elementListeners.get("queueparty:enable-audio")()
  assert.deepEqual(calls.slice(-2), [["seek", 10], ["play"]])
})

test("guest reconnect pauses while offline and fetches a fresh position", async t => {
  const {context, player, calls, server, tick} = await mount(t, {host: false})
  hook.disconnected.call(context)
  assert.deepEqual(calls.at(-1), ["pause"])
  const count = calls.length
  tick()
  assert.equal(calls.length, count)
  server({item_id: "first-item", status: "playing", position: 125, revision: 4})
  hook.reconnected.call(context)
  assert.equal(player.position, 125)
  assert.deepEqual(calls.at(-1), ["play"])
})

test("switching to the next song loads a new video and resets its position", async t => {
  const {calls, update} = await mount(t, {host: false, position: 90})
  update({videoId: "second-video", itemId: "second-item", playbackRevision: "2", playbackPosition: "0"})
  assert.deepEqual(calls.at(-1), ["load", {videoId: "second-video", startSeconds: 0}])
})

test("a delayed reconnect reply cannot override a newer host pause", async t => {
  const {context, player, receive} = await mount(t, {host: false})
  let pendingReply
  context.pushEvent = (_event, _data, reply) => { pendingReply = reply }
  hook.reconnected.call(context)
  receive({item_id: "first-item", status: "paused", position: 80, revision: 5})
  pendingReply({playback: {item_id: "first-item", status: "playing", position: 20, revision: 4}})
  assert.equal(player.position, 80)
  assert.equal(context.snapshot.status, "paused")
})

test("removing the guest player stops playback and cleans up timers and listeners", async t => {
  const {context, calls, elementListeners, documentListeners} = await mount(t, {host: false})
  hook.destroyed.call(context)
  assert.deepEqual(calls.slice(-2), [["clearInterval", 7], ["destroy"]])
  assert.equal(elementListeners.size, 0)
  assert.equal(documentListeners.size, 0)
})

test("leaving before the API resolves does not create a detached player", async t => {
  const {player, sent} = await mount(t, {destroyBeforeAPI: true})
  assert.equal(player, undefined)
  assert.equal(sent.length, 0)
})
