import { Controller } from "@hotwired/stimulus"

// Shows catalog form fields scoped to one catalog type. Wrappers declare
// data-type-show="nessie polaris"; the type select toggles visibility.
export default class extends Controller {
  static targets = ["field"]

  change(event) {
    const type = event.target.value
    this.fieldTargets.forEach((wrapper) => {
      const shownFor = (wrapper.dataset.typeShow || "").split(/\s+/)
      wrapper.classList.toggle("hidden", !shownFor.includes(type))
    })
  }

  connect() {
    const select = this.element.querySelector("select[data-catalog-type-select]")
    if (!select) return
    this.change({ target: select })
  }
}
