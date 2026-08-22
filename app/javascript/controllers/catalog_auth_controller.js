import { Controller } from "@hotwired/stimulus"

// Shows only the credential fields that apply to the selected auth strategy.
// Field wrappers declare data-auth-show="<method1> <method2>"; the select
// fires change and every wrapper toggles visibility accordingly.
export default class extends Controller {
  static targets = ["field"]

  change(event) {
    const method = event.target.value
    this.fieldTargets.forEach((wrapper) => {
      const shownFor = (wrapper.dataset.authShow || "").split(/\s+/)
      wrapper.classList.toggle("hidden", !shownFor.includes(method))
    })
  }

  // Applies the visibility rules once on load so a page rendered with a saved
  // credential starts consistent.
  connect() {
    const select = this.element.querySelector("select[data-auth-method-select]")
    if (!select) return
    this.change({ target: select })
  }
}
