let apiPromise

function loadAPI() {
  if (window.YT?.Player) return Promise.resolve(window.YT)
  if (apiPromise) return apiPromise

  apiPromise = new Promise((resolve, reject) => {
    const previous = window.onYouTubeIframeAPIReady
    window.onYouTubeIframeAPIReady = () => {
      previous?.()
      resolve(window.YT)
    }
    const script = document.createElement("script")
    script.src = "https://www.youtube.com/iframe_api"
    script.onerror = () => {
      apiPromise = undefined
      script.remove()
      reject(new Error("YouTube player API failed to load"))
    }
    document.head.appendChild(script)
  })

  return apiPromise
}

export default {
  mounted() {
    this.disposed = false
    this.ready = false
    this.connected = true
    this.isHost = this.el.dataset.host === "true"
    this.autoplayBlocked = false
    this.handoff = null
    this.snapshot = {
      item_id: this.el.dataset.itemId,
      status: this.el.dataset.playbackStatus,
      position: Number(this.el.dataset.playbackPosition) || 0,
      revision: Number(this.el.dataset.playbackRevision) || 0
    }
    this.snapshotAt = performance.now()
    // In host-only mode a transfer creates a fresh player on the new host.
    if (this.isHost && this.snapshot.position > 0) this.handoff = {prepared: false}

    this.targetPosition = () => this.snapshot.position + (
      this.snapshot.status === "playing" ? (performance.now() - this.snapshotAt) / 1000 : 0
    )

    this.syncVideo = () => {
      if (!this.ready || this.disposed || !this.connected) return false
      if (this.activeItemId === this.el.dataset.itemId) return false
      this.activeItemId = this.el.dataset.itemId
      this.playingItemId = null
      this.endedReportedItemId = null
      this.loadingItem = true
      const video = {videoId: this.el.dataset.videoId, startSeconds: this.targetPosition()}
      if (this.snapshot.status !== "paused" && !this.autoplayBlocked) {
        this.player.loadVideoById(video)
      } else {
        this.player.cueVideoById(video)
      }
      return true
    }

    this.syncGuest = (force = false) => {
      if (!this.ready || this.disposed || !this.connected || this.isHost) return
      if (this.syncVideo()) return
      if (this.autoplayBlocked) return
      const state = this.player.getPlayerState()
      // Buffering is not a seek command. Repeatedly seeking a loading player
      // back to a frozen host position can keep it stuck at the first second.
      if (state === window.YT.PlayerState.ENDED && this.playingItemId === this.activeItemId) return
      if (this.snapshot.status === "buffering") return
      if (!force && this.snapshot.status === "playing" && (
        this.loadingItem || state === window.YT.PlayerState.BUFFERING
      )) return
      const position = this.targetPosition()
      const needsSeek = force || Math.abs(this.player.getCurrentTime() - position) > 1.5
      if (needsSeek) {
        this.player.seekTo(position, true)
      }
      if (this.snapshot.status === "playing") {
        if (state !== window.YT.PlayerState.PLAYING && state !== window.YT.PlayerState.BUFFERING) {
          this.player.playVideo()
        }
      } else if (needsSeek || (state !== window.YT.PlayerState.PAUSED && state !== window.YT.PlayerState.CUED)) {
        this.player.pauseVideo()
      }
    }

    this.finishHostItem = () => {
      if (!this.isHost || !this.ready || this.disposed || !this.connected || this.handoff || this.loadingItem) return
      if (this.activeItemId !== this.el.dataset.itemId || this.playingItemId !== this.activeItemId) return
      if (this.player.getVideoData().video_id !== this.el.dataset.videoId) return
      if (this.player.getPlayerState() !== window.YT.PlayerState.ENDED || this.endedReportedItemId === this.activeItemId) return
      this.endedReportedItemId = this.activeItemId
      this.pushEvent("video_ended", {item_id: this.activeItemId})
    }

    this.settleHandoff = () => {
      if (!this.handoff || !this.ready || !this.connected || this.disposed) return
      this.syncVideo()
      if (this.player.getVideoData().video_id !== this.el.dataset.videoId) return
      const states = window.YT.PlayerState
      const state = this.player.getPlayerState()
      if (!this.handoff.prepared && state === states.ENDED && !this.loadingItem &&
        this.playingItemId === this.activeItemId && this.snapshot.status !== "paused") {
        this.handoff = null
        this.finishHostItem()
        return
      }
      if (this.autoplayBlocked) return
      if (!this.handoff.prepared) {
        this.handoff = {prepared: true, position: this.targetPosition(), at: performance.now()}
        const needsSeek = Math.abs(this.player.getCurrentTime() - this.handoff.position) > 1.5
        if (needsSeek) {
          this.player.seekTo(this.handoff.position, true)
        }
        if (this.snapshot.status === "paused") {
          if (needsSeek || (state !== states.PAUSED && state !== states.CUED)) this.player.pauseVideo()
        } else if (state !== states.PLAYING && state !== states.BUFFERING) {
          this.player.playVideo()
        }
      }
      // seekTo/playVideo are asynchronous. Do not publish the old local
      // position until the seek has landed and the desired state is ready.
      const position = this.player.getCurrentTime()
      const elapsed = (performance.now() - this.handoff.at) / 1000
      const paused = this.snapshot.status === "paused"
      const currentState = this.player.getPlayerState()
      const settledState = paused ? [states.PAUSED, states.CUED].includes(currentState) : currentState === states.PLAYING
      if (settledState && Number.isFinite(position) && position >= this.handoff.position - 1.5 &&
        position <= this.handoff.position + (paused ? 0 : elapsed) + 1.5) {
        this.handoff = null
        this.loadingItem = false
        if (!paused) this.playingItemId = this.activeItemId
      }
    }

    this.receiveSnapshot = (snapshot, force = false) => {
      if (this.disposed || this.isHost || !snapshot || snapshot.item_id !== this.el.dataset.itemId) return
      // Reconnecting may refresh the same revision, but must never apply an older reply.
      if (snapshot.item_id === this.snapshot.item_id && (
        snapshot.revision < this.snapshot.revision || (!force && snapshot.revision === this.snapshot.revision)
      )) return
      this.snapshot = snapshot
      this.snapshotAt = performance.now()
      this.syncGuest(force)
    }

    this.reportHost = (override) => {
      if (!this.isHost || !this.ready || this.disposed || !this.connected) return
      this.settleHandoff()
      if (this.handoff || this.loadingItem || this.activeItemId !== this.el.dataset.itemId) return
      const actualVideo = this.player.getVideoData().video_id
      if (actualVideo !== this.el.dataset.videoId) return
      this.finishHostItem()
      const status = override || ({1: "playing", 2: "paused", 3: "buffering", 5: "paused"})[this.player.getPlayerState()]
      const position = this.player.getCurrentTime()
      if (!status || !Number.isFinite(position)) return
      this.pushEvent("playback_update", {item_id: this.activeItemId, status, position})
    }

    this.requestSnapshot = () => {
      if (this.disposed || !this.connected) return
      if (this.isHost) return this.reportHost()
      const requestedAt = performance.now()
      this.pushEvent("request_playback", {}, reply => {
        if (this.disposed || !reply.playback) return
        const snapshot = {...reply.playback}
        if (snapshot.status === "playing") snapshot.position += (performance.now() - requestedAt) / 2000
        this.receiveSnapshot(snapshot, true)
      })
    }

    this.enableAudio = () => {
      this.autoplayBlocked = false
      if (this.isHost && this.handoff) {
        this.handoff.prepared = false
        this.reportHost()
      } else {
        this.syncGuest(true)
      }
    }
    this.onVisible = () => {
      if (document.visibilityState === "visible") this.requestSnapshot()
    }
    this.el.addEventListener("queueparty:enable-audio", this.enableAudio)
    document.addEventListener("visibilitychange", this.onVisible)
    this.handleEvent("room_playback", snapshot => this.receiveSnapshot(snapshot))
    this.syncTimer = setInterval(() => this.isHost ? this.reportHost() : this.syncGuest(), 2000)

    loadAPI().then(YT => {
      if (this.disposed) return
      const target = document.createElement("div")
      this.el.replaceChildren(target)
      this.player = new YT.Player(target, {
        width: "100%",
        height: "100%",
        videoId: this.el.dataset.videoId,
        playerVars: {rel: 0, playsinline: 1, origin: window.location.origin},
        events: {
          onReady: () => {
            if (this.disposed) return
            this.ready = true
            this.syncVideo()
            if (this.handoff) this.reportHost()
          },
          onStateChange: event => {
            if (this.disposed) return
            if (this.activeItemId !== this.el.dataset.itemId || this.player.getVideoData().video_id !== this.el.dataset.videoId) return
            if (event.data === YT.PlayerState.PLAYING) {
              if (this.autoplayBlocked && this.handoff) this.handoff.prepared = false
              this.playingItemId = this.activeItemId
              this.loadingItem = false
              this.autoplayBlocked = false
            }
            this.reportHost()
            if (event.data === YT.PlayerState.ENDED) this.finishHostItem()
          },
          onError: event => {
            if (this.disposed) return
            const actualVideo = this.player.getVideoData().video_id
            if (actualVideo && actualVideo !== this.el.dataset.videoId) return
            this.loadingItem = false
            this.reportHost("paused")
            this.pushEvent("player_error", {item_id: this.activeItemId, code: event.data})
          },
          onAutoplayBlocked: () => {
            if (this.disposed) return
            this.autoplayBlocked = true
            this.loadingItem = false
            this.reportHost("paused")
            this.pushEvent("autoplay_blocked", {})
          }
        }
      })
    }).catch(() => {
      if (!this.disposed) this.pushEvent("player_error", {})
    })
  },

  updated() {
    if (this.disposed) return
    const wasHost = this.isHost
    this.isHost = this.el.dataset.host === "true"
    const snapshot = {
      item_id: this.el.dataset.itemId,
      status: this.el.dataset.playbackStatus,
      position: Number(this.el.dataset.playbackPosition) || 0,
      revision: Number(this.el.dataset.playbackRevision) || 0
    }
    if (wasHost !== this.isHost) {
      if (snapshot.item_id !== this.snapshot.item_id || snapshot.revision >= this.snapshot.revision) {
        this.snapshot = snapshot
        this.snapshotAt = performance.now()
      }
      this.handoff = this.isHost ? {prepared: false} : null
      if (this.isHost) this.endedReportedItemId = null
      if (this.isHost) {
        this.reportHost()
      } else {
        this.syncGuest(true)
      }
    }
    if (this.isHost && this.activeItemId !== snapshot.item_id) {
      if (wasHost) this.handoff = null
      if (snapshot.item_id !== this.snapshot.item_id || snapshot.revision >= this.snapshot.revision) {
        this.snapshot = snapshot
        this.snapshotAt = performance.now()
      }
      this.syncVideo()
    } else {
      this.receiveSnapshot(snapshot)
    }
  },

  disconnected() {
    this.connected = false
    if (!this.isHost && this.ready) this.player.pauseVideo()
  },

  reconnected() {
    this.connected = true
    this.requestSnapshot()
  },

  destroyed() {
    this.disposed = true
    clearInterval(this.syncTimer)
    this.el.removeEventListener("queueparty:enable-audio", this.enableAudio)
    document.removeEventListener("visibilitychange", this.onVisible)
    this.player?.destroy()
  }
}
