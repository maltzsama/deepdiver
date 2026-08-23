// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Rows marked with data-href navigate on click. Inner links, buttons and
// form controls keep their own behavior.
document.addEventListener("click", (event) => {
  const row = event.target.closest("tr[data-href]")
  if (!row) return
  if (event.target.closest("a, button, input, select, label")) return
  window.location = row.dataset.href
})
