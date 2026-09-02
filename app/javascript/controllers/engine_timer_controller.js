import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "label", "timer"]

  static values = {
    deadline: String,
    start: String,
    mode: String,
    // Median seconds this phase has historically taken. The progress bar fills
    // against THIS, not against the deadline: the deadline is a failure
    // horizon, so using it as the denominator made a normal start render as a
    // few percent of the bar and a nearly-full bar mean "about to fail".
    estimate: Number,
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

  // Fills against the expected duration and escalates the bar's APPEARANCE as
  // the phase runs long: normal up to the estimate, `over` past it, `expired`
  // at the deadline. The deadline is therefore still visible, as a treatment
  // rather than as the scale.
  updateCountdown() {
    const now = Date.now()
    const startTime = this.parseTime(this.startValue)
    const deadlineTime = this.parseTime(this.deadlineValue)
    if (!startTime) return

    const elapsedMs = now - startTime
    const estimateMs = (this.estimateValue || 0) * 1000

    if (deadlineTime && now >= deadlineTime) {
      this.setBar(100, "expired")
      this.labelTarget.textContent = this.labelTarget.dataset.expired || ""
      return
    }

    // No history yet: there is no honest estimate, so do not invent one.
    if (estimateMs <= 0) {
      this.setBar(null, "indeterminate")
      if (deadlineTime) this.labelTarget.textContent = this.formatRemaining(deadlineTime - now)
      return
    }

    const pct = Math.min(100, (elapsedMs / estimateMs) * 100)
    // Past the estimate the bar holds at full and turns to the warning
    // treatment; it is taking longer than this phase normally does.
    this.setBar(pct, elapsedMs > estimateMs ? "over" : null)
    this.labelTarget.textContent =
      elapsedMs > estimateMs && deadlineTime
        ? this.formatRemaining(deadlineTime - now)
        : this.formatEstimate(estimateMs - elapsedMs)
  }

  // Applies the fill width and the escalation state to the bar. A null width
  // means indeterminate, and the CSS animates it instead of sizing it.
  setBar(pct, state) {
    const bar = this.barTarget
    bar.classList.remove("is-over", "is-expired", "indeterminate")

    if (state === "indeterminate") {
      bar.classList.add("indeterminate")
      bar.style.removeProperty("--engine-progress")
      return
    }

    bar.style.setProperty("--engine-progress", pct.toFixed(1) + "%")
    if (state === "over") bar.classList.add("is-over")
    if (state === "expired") bar.classList.add("is-expired")
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

  // "~14s to go" against the historical estimate, not against a timeout.
  formatEstimate(ms) {
    const totalSeconds = Math.max(0, Math.round(ms / 1000))
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60

    if (minutes > 0) {
      return seconds > 0 ? `~${minutes}m ${seconds}s to go` : `~${minutes}m to go`
    }
    return `~${seconds}s to go`
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
