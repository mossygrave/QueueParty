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
    this.syncVideo = () => {
      if (!this.ready || this.disposed) return
      if (this.activeItemId === this.el.dataset.itemId) return
      this.activeItemId = this.el.dataset.itemId
      this.player.loadVideoById(this.el.dataset.videoId)
    }

    loadAPI().then(YT => {
      if (this.disposed) return
      const target = document.createElement("div")
      this.el.replaceChildren(target)
      this.activeItemId = this.el.dataset.itemId
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
            this.player.playVideo()
          },
          onStateChange: event => {
            if (this.disposed) return
            if (event.data === YT.PlayerState.PLAYING) this.playingItemId = this.activeItemId
            if (event.data === YT.PlayerState.ENDED && this.playingItemId === this.activeItemId) {
              this.pushEvent("video_ended", {item_id: this.playingItemId})
            }
          },
          onError: () => { if (!this.disposed) this.pushEvent("player_error", {}) },
          onAutoplayBlocked: () => { if (!this.disposed) this.pushEvent("autoplay_blocked", {}) }
        }
      })
    }).catch(() => {
      if (!this.disposed) this.pushEvent("player_error", {})
    })
  },

  updated() {
    this.syncVideo()
  },

  destroyed() {
    this.disposed = true
    this.player?.destroy()
  }
}
