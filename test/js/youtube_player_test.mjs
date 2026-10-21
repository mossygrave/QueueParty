import test from "node:test"
import assert from "node:assert/strict"
import hook from "../../assets/js/youtube_player.mjs"

test("player keeps its wrapper, loads the next item, and reports completion", async () => {
  const calls = []
  let options
  let target
  class Player {
    constructor(element, config) { target = element; options = config }
    playVideo() { calls.push("play") }
    loadVideoById(id) { calls.push(["load", id]) }
    destroy() { calls.push("destroy") }
  }
  globalThis.window = {YT: {Player, PlayerState: {PLAYING: 1, ENDED: 0}}, location: {origin: "http://localhost:4000"}}
  globalThis.document = {createElement: tag => ({tag})}
  const context = {
    el: {dataset: {videoId: "first-video", itemId: "first-item"}, replaceChildren(child) { this.child = child }},
    pushEvent: (event, data) => calls.push([event, data])
  }
  hook.mounted.call(context)
  await Promise.resolve()
  assert.equal(target, context.el.child)
  assert.notEqual(target, context.el)
  options.events.onReady()
  assert.deepEqual(calls, ["play"])
  options.events.onStateChange({data: 1})
  options.events.onStateChange({data: 0})
  assert.deepEqual(calls.at(-1), ["video_ended", {item_id: "first-item"}])
  context.el.dataset = {videoId: "second-video", itemId: "second-item"}
  hook.updated.call(context)
  assert.deepEqual(calls.at(-1), ["load", "second-video"])
  const count = calls.length
  options.events.onStateChange({data: 0})
  assert.equal(calls.length, count, "a stale end event must not finish the new item")
  options.events.onStateChange({data: 1})
  options.events.onStateChange({data: 0})
  assert.deepEqual(calls.at(-1), ["video_ended", {item_id: "second-item"}])
  hook.destroyed.call(context)
  assert.equal(calls.at(-1), "destroy")
})

test("leaving before the API resolves does not create a detached player", async () => {
  let playerCount = 0
  globalThis.window = {YT: {Player: class { constructor() { playerCount++ } }}}
  const context = {el: {dataset: {}}, pushEvent() { assert.fail("must not emit after leaving") }}
  hook.mounted.call(context)
  hook.destroyed.call(context)
  await Promise.resolve()
  assert.equal(playerCount, 0)
})
