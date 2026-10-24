import test from "node:test"
import assert from "node:assert/strict"
import hook from "../../assets/js/queue_reorder.mjs"

function mount() {
  const sent = [], listeners = new Map(), events = new Map(), captures = new Set(), scrolls = []
  const marker = {hidden: true, style: {}}
  const status = {textContent: ""}
  const rows = ["a", "b", "c"].map((id, index) => {
    const row = {dataset: {itemId: id}, getBoundingClientRect: () => ({left: 20, top: 100 + index * 60, bottom: 160 + index * 60, width: 300, height: 60})}
    const handle = {focus: () => { handle.focused = true }, closest: selector => selector === ".queue-drag-handle" ? handle : row}
    row.closest = () => row
    row.querySelector = () => handle
    row.handle = handle
    return row
  })
  const queue = {
    dataset: {reorderEnabled: "true"},
    querySelectorAll: () => rows,
    contains: element => rows.some(row => row === element || row.handle === element),
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name),
    setPointerCapture: id => captures.add(id), hasPointerCapture: id => captures.has(id), releasePointerCapture: id => captures.delete(id)
  }
  let target = null
  const el = {parentElement: {querySelector: () => queue},
    querySelector: selector => selector === ".queue-drop-marker" ? marker : status,
    ownerDocument: {elementFromPoint: () => target, defaultView: {innerHeight: 600, scrollBy: (...args) => scrolls.push(args), requestAnimationFrame: callback => { callback(); return 1 }, cancelAnimationFrame() {}}}}
  const context = {el, pushEvent: (...args) => sent.push(args), handleEvent: (name, callback) => events.set(name, callback)}
  hook.mounted.call(context)
  const event = (target, overrides = {}) => ({target, pointerId: 1, button: 0, isPrimary: true, clientX: 40, clientY: 120, preventDefault() {}, ...overrides})
  const down = (index = 0, overrides = {}) => listeners.get("pointerdown")(event(rows[index].handle, overrides))
  const move = (index, y, overrides = {}) => { target = rows[index] ?? null; listeners.get("pointermove")(event(target, {clientY: y, ...overrides})) }
  const up = (index, y, overrides = {}) => { target = rows[index] ?? null; listeners.get("pointerup")(event(target, {clientY: y, ...overrides})) }
  const key = (index, key) => listeners.get("keydown")(event(rows[index].handle, {key}))
  return {context, queue, rows, sent, marker, status, listeners, events, captures, scrolls, down, move, up, key}
}

test("mouse drag drops before a row without rearranging streamed DOM", () => {
  const m = mount()
  m.down(2); m.move(0, 110)
  assert.equal(m.marker.hidden, false)
  assert.equal(m.marker.style.top, "100px")
  m.up(0, 110)
  assert.deepEqual(m.sent, [["move_queue_item", {id: "c", before_id: "a"}]])
  assert.deepEqual(m.rows.map(row => row.dataset.itemId), ["a", "b", "c"])
  assert.equal(m.marker.hidden, true)
  assert.equal(m.captures.size, 0)
})

test("touch drag can drop after the last row", () => {
  const m = mount()
  m.down(0, {pointerType: "touch"}); m.move(2, 270); m.up(2, 270)
  assert.deepEqual(m.sent, [["move_queue_item", {id: "a", before_id: null}]])
})

test("clicks, drops outside, and Escape never move songs", () => {
  const m = mount()
  m.down(); m.up(1, 190)
  m.down(); m.move(-1, 300); m.up(-1, 300)
  m.down(); m.move(1, 190); m.key(0, "Escape"); m.up(1, 190)
  assert.equal(m.sent.length, 0)
  assert.equal(m.marker.hidden, true)
})

test("arrow keys move one position, respect boundaries and restore focus", () => {
  const m = mount()
  m.key(0, "ArrowUp"); m.key(2, "ArrowDown")
  assert.equal(m.sent.length, 0)
  m.key(1, "ArrowUp"); m.key(0, "ArrowDown"); m.key(1, "ArrowDown")
  assert.deepEqual(m.sent.map(([, payload]) => payload), [
    {id: "b", before_id: "a"}, {id: "a", before_id: "c"}, {id: "b", before_id: null}
  ])
  m.events.get("queue_reordered")({id: "b"})
  assert.equal(m.rows[1].handle.focused, true)
  assert.equal(m.status.textContent, "Play next order updated.")
})

test("host transfer during a drag disables drops and keyboard moves", () => {
  const m = mount()
  m.down(); m.move(2, 270)
  m.queue.dataset.reorderEnabled = "false"
  m.up(2, 270); m.key(1, "ArrowUp"); m.down()
  assert.equal(m.sent.length, 0)
  assert.equal(m.context.drag, null)
})

test("removed source, pointer cancellation and unrelated pointers are safe", () => {
  const m = mount()
  m.down(); m.move(2, 270, {pointerId: 2}); m.up(2, 270, {pointerId: 2})
  assert.equal(m.sent.length, 0)
  m.rows.shift(); m.move(1, 220)
  assert.equal(m.context.drag, null)
  m.down(); m.listeners.get("pointercancel")({pointerId: 1})
  assert.equal(m.context.drag, null)
})

test("dragging near viewport edges scrolls and cleanup removes listeners", () => {
  const m = mount()
  m.down(); m.move(2, 590); m.move(0, 10)
  assert.deepEqual(m.scrolls, [[0, 16], [0, -16]])
  hook.destroyed.call(m.context)
  assert.equal(m.listeners.size, 0)
  assert.equal(m.captures.size, 0)
})
