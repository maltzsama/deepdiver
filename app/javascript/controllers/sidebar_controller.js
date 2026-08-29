import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static STORAGE_KEY = "deepdiver:sidebar-collapsed"

  static targets = ["collapse"]

  connect() {
    if (localStorage.getItem(this.constructor.STORAGE_KEY) === "true") {
      this.element.classList.add("collapsed")
    }
  }

  toggle(event) {
    this.element.classList.toggle("collapsed")
    localStorage.setItem(
      this.constructor.STORAGE_KEY,
      this.element.classList.contains("collapsed") ? "true" : "false"
    )
  }
}
