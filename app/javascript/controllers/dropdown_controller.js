import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.onOutsideClick = this.onOutsideClick.bind(this)
    this.onKeydown = this.onKeydown.bind(this)
    document.addEventListener("click", this.onOutsideClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.onOutsideClick)
    document.removeEventListener("keydown", this.onKeydown)
  }

  toggle(event) {
    event.stopPropagation()
    const open = this.menuTarget.classList.toggle("open")
    this.menuTarget.hidden = !open
  }

  close() {
    this.menuTarget.classList.remove("open")
    this.menuTarget.hidden = true
  }

  onOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  onKeydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
