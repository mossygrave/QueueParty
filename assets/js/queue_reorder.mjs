// Only the ignored controller owns DOM here. LiveView owns the streamed queue;
// moves are applied on the server rather than moving or cloning queue elements.
export default {
  mounted() {
    this.queue = this.el.parentElement.querySelector("#queue")
    this.marker = this.el.querySelector(".queue-drop-marker")
    this.status = this.el.querySelector(".queue-reorder-status")
    this.rows = () => Array.from(this.queue.querySelectorAll("[data-item-id]"))
    this.enabled = () => this.queue.dataset.reorderEnabled === "true"
    this.cancel = () => {
      const pointerId = this.drag?.pointerId
      this.drag = null
      this.marker.hidden = true
      if (pointerId !== undefined && this.queue.hasPointerCapture(pointerId)) {
        this.queue.releasePointerCapture(pointerId)
      }
    }
    this.sendMove = (id, beforeId) => {
      if (this.enabled()) this.pushEvent("move_queue_item", {id, before_id: beforeId})
    }
    this.onDown = event => {
      if (!this.enabled() || this.drag || event.button !== 0 || event.isPrimary === false) return
      const handle = event.target.closest(".queue-drag-handle")
      if (!handle || !this.queue.contains(handle)) return
      const row = handle.closest("[data-item-id]")
      event.preventDefault()
      handle.focus({preventScroll: true})
      this.drag = {id: row.dataset.itemId, pointerId: event.pointerId, x: event.clientX, y: event.clientY, moved: false}
      this.queue.setPointerCapture(event.pointerId)
    }
    this.locate = event => {
      const target = this.el.ownerDocument.elementFromPoint(event.clientX, event.clientY)
      const row = target?.closest("[data-item-id]")
      if (!row || !this.queue.contains(row) || row.dataset.itemId === this.drag.id) return null
      const rect = row.getBoundingClientRect()
      const after = event.clientY >= rect.top + rect.height / 2
      const rows = this.rows()
      return {
        beforeId: after ? (rows[rows.indexOf(row) + 1]?.dataset.itemId ?? null) : row.dataset.itemId,
        rect, y: after ? rect.bottom : rect.top
      }
    }
    this.onMove = event => {
      if (!this.drag || event.pointerId !== this.drag.pointerId) return
      if (!this.enabled() || !this.rows().some(row => row.dataset.itemId === this.drag.id)) {
        this.cancel()
        return
      }
      if (Math.hypot(event.clientX - this.drag.x, event.clientY - this.drag.y) < 5 && !this.drag.moved) return
      this.drag.moved = true
      event.preventDefault()
      const view = this.el.ownerDocument.defaultView
      if (event.clientY < 64) view.scrollBy(0, -16)
      else if (event.clientY > view.innerHeight - 64) view.scrollBy(0, 16)
      const destination = this.locate(event)
      this.marker.hidden = !destination
      if (destination) {
        Object.assign(this.marker.style, {
          left: `${destination.rect.left}px`, top: `${destination.y}px`, width: `${destination.rect.width}px`
        })
      }
    }
    this.onUp = event => {
      if (!this.drag || event.pointerId !== this.drag.pointerId) return
      const {id, moved} = this.drag
      const destination = moved && this.enabled() ? this.locate(event) : null
      this.cancel()
      if (destination && destination.beforeId !== id) this.sendMove(id, destination.beforeId)
    }
    this.onCancel = event => {
      if (this.drag?.pointerId === event.pointerId) this.cancel()
    }
    this.onKey = event => {
      if (event.key === "Escape") { this.cancel(); return }
      if (!this.enabled() || !["ArrowUp", "ArrowDown"].includes(event.key)) return
      const handle = event.target.closest(".queue-drag-handle")
      if (!handle) return
      event.preventDefault()
      const row = handle.closest("[data-item-id]")
      const rows = this.rows()
      const index = rows.indexOf(row)
      if (event.key === "ArrowUp" && index > 0) this.sendMove(row.dataset.itemId, rows[index - 1].dataset.itemId)
      if (event.key === "ArrowDown" && index < rows.length - 1) this.sendMove(row.dataset.itemId, rows[index + 2]?.dataset.itemId ?? null)
    }
    this.listeners = {pointerdown: this.onDown, pointermove: this.onMove, pointerup: this.onUp,
      pointercancel: this.onCancel, lostpointercapture: this.onCancel, keydown: this.onKey}
    for (const [name, callback] of Object.entries(this.listeners)) this.queue.addEventListener(name, callback)
    this.handleEvent("queue_reordered", ({id}) => {
      this.status.textContent = "Play next order updated."
      // Stream resets can replace rows during the patch. Restore focus after
      // LiveView has finished applying the new order, not to the outgoing row.
      this.focusFrame = this.el.ownerDocument.defaultView.requestAnimationFrame(() => {
        this.focusFrame = null
        if (!this.enabled()) return
        const row = this.rows().find(row => row.dataset.itemId === id)
        row?.querySelector(".queue-drag-handle")?.focus({preventScroll: true})
      })
    })
  },
  destroyed() {
    this.cancel()
    if (this.focusFrame != null) this.el.ownerDocument.defaultView.cancelAnimationFrame(this.focusFrame)
    for (const [name, callback] of Object.entries(this.listeners)) this.queue.removeEventListener(name, callback)
  }
}
