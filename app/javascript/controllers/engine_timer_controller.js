import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "label", "timer"]

  static values = {
    deadline: String,
    start: String,
    mode: String,
  }

  connect() {
    this.tick = this.tick.bind(this)
    this.tick()
    this.interval = setInterval(this.tick, 1000)
  }

  disconnect() {
    if (this.interval) clearInterval(this.interval)
  }

  tick() {
    if (this.hasTimerTarget) {
      this.updateTimer()
    }
    if (this.hasBarTarget && this.hasLabelTarget) {
      if (this.modeValue === "countdown") this.updateCountdown()
      else if (this.modeValue === "uptime") this.updateUptime()
    }
  }

  updateTimer() {
    const now = Date.now()
    const deadlineTime = this.parseTime(this.deadlineValue)
    if (!deadlineTime) return

    const remainingMs = deadlineTime - now
    if (remainingMs <= 0) {
      this.timerTarget.textContent = this.timerTarget.dataset.expired || ""
      return
    }
    this.timerTarget.textContent = this.formatRemaining(remainingMs)
  }

  updateCountdown() {
    const deadlineTime = this.parseTime(this.deadlineValue)
    if (!deadlineTime) return

    const now = Date.now()
    const totalMs = deadlineTime - (this.parseTime(this.startValue) || now)
    const elapsedMs = now - (this.parseTime(this.startValue) || now)
    const remainingMs = deadlineTime - now

    if (remainingMs <= 0) {
      this.barTarget.style.setProperty("--engine-progress", "100%")
      this.labelTarget.textContent = this.labelTarget.dataset.expired || ""
      return
    }

    const pct = totalMs > 0 ? Math.min(100, (elapsedMs / totalMs) * 100) : 0
    this.barTarget.style.setProperty("--engine-progress", pct.toFixed(1) + "%")
    this.labelTarget.textContent = this.formatRemaining(remainingMs)
  }

  updateUptime() {
    const startTime = this.parseTime(this.startValue)
    if (!startTime) return

    const elapsedMs = Date.now() - startTime
    this.labelTarget.textContent = this.formatElapsed(elapsedMs)
  }

  parseTime(isoString) {
    if (!isoString) return null
    const t = new Date(isoString)
    return isNaN(t.getTime()) ? null : t.getTime()
  }

  formatRemaining(ms) {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60

    if (minutes > 0) {
      return seconds > 0
        ? `~${minutes}m ${seconds}s left`
        : `~${minutes}m left`
    }
    return `~${seconds}s left`
  }

  formatElapsed(ms) {
    const totalSeconds = Math.floor(ms / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const hours = Math.floor(minutes / 60)
    const mins = minutes % 60

    if (hours > 0) {
      return `${hours}h ${mins}m`
    }
    return `${minutes}m`
  }
}
