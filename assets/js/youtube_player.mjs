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
    this.snapshot = {
      item_id: this.el.dataset.itemId,
      status: this.el.dataset.playbackStatus,
      position: Number(this.el.dataset.playbackPosition) || 0,
      revision: Number(this.el.dataset.playbackRevision) || 0
    }
    this.snapshotAt = performance.now()

    this.targetPosition = () => this.snapshot.position + (
      this.snapshot.status === "playing" ? (performance.now() - this.snapshotAt) / 1000 : 0
    )

    this.syncVideo = () => {
      if (!this.ready || this.disposed || !this.connected) return false
      if (this.activeItemId === this.el.dataset.itemId) return false
      this.activeItemId = this.el.dataset.itemId
      this.playingItemId = null
      this.loadingItem = true
      const video = {videoId: this.el.dataset.videoId, startSeconds: this.targetPosition()}
      if (this.snapshot.status === "playing" && !this.autoplayBlocked) {
        this.player.loadVideoById(video)
      } else {
        this.player.cueVideoById(video)
      }
      return true
    }

    this.syncGuest = (force = false) => {
      if (!this.ready || this.disposed || !this.connected || this.isHost) return
      if (this.syncVideo()) return
      if (this.autoplayBlocked && !force) return
      const position = this.targetPosition()
      if (force || Math.abs(this.player.getCurrentTime() - position) > 1.5) {
        this.player.seekTo(position, true)
      }
      const state = this.player.getPlayerState()
      if (this.snapshot.status === "playing") {
        if (state !== window.YT.PlayerState.PLAYING && state !== window.YT.PlayerState.BUFFERING) {
          this.player.playVideo()
        }
      } else if (state !== window.YT.PlayerState.PAUSED && state !== window.YT.PlayerState.CUED) {
        this.player.pauseVideo()
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
      this.syncGuest()
    }

    this.reportHost = (override) => {
      if (!this.isHost || !this.ready || this.disposed || !this.connected || this.loadingItem) return
      const actualVideo = this.player.getVideoData().video_id
      if (actualVideo !== this.el.dataset.videoId) return
      const status = override || ({1: "playing", 2: "paused", 3: "buffering"})[this.player.getPlayerState()]
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
      this.syncGuest(true)
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
          },
          onStateChange: event => {
            if (this.disposed) return
            if (event.data === YT.PlayerState.PLAYING) {
              if (this.player.getVideoData().video_id !== this.el.dataset.videoId) return
              this.playingItemId = this.activeItemId
              this.loadingItem = false
              this.autoplayBlocked = false
            }
            this.reportHost()
            if (this.isHost && event.data === YT.PlayerState.ENDED && this.playingItemId === this.activeItemId) {
              this.pushEvent("video_ended", {item_id: this.playingItemId})
            }
          },
          onError: () => {
            if (this.disposed) return
            this.loadingItem = false
            this.reportHost("paused")
            this.pushEvent("player_error", {})
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
    const snapshot = {
      item_id: this.el.dataset.itemId,
      status: this.el.dataset.playbackStatus,
      position: Number(this.el.dataset.playbackPosition) || 0,
      revision: Number(this.el.dataset.playbackRevision) || 0
    }
    if (this.isHost && this.activeItemId !== snapshot.item_id) {
      this.snapshot = snapshot
      this.snapshotAt = performance.now()
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
