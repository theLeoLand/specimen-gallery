import { Controller } from "@hotwired/stimulus"

// Provides autocomplete suggestions for scientific names via GBIF
export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: String }

  connect() {
    this.debounceTimer = null
    this.selectedIndex = -1
  }

  disconnect() {
    this.clearDebounce()
    this.hideResults()
  }

  onInput() {
    this.clearDebounce()
    const query = this.inputTarget.value.trim()

    if (query.length < 2) {
      this.hideResults()
      return
    }

    this.debounceTimer = setTimeout(() => {
      this.fetchSuggestions(query)
    }, 250)
  }

  onKeydown(event) {
    if (!this.hasResultsTarget || this.resultsTarget.classList.contains("hidden")) {
      return
    }

    const items = this.resultsTarget.querySelectorAll("[data-suggestion]")
    if (items.length === 0) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
        this.highlightItem(items)
        break
      case "ArrowUp":
        event.preventDefault()
        this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
        this.highlightItem(items)
        break
      case "Enter":
        event.preventDefault()
        if (this.selectedIndex >= 0 && items[this.selectedIndex]) {
          this.selectSuggestion({ currentTarget: items[this.selectedIndex] })
        }
        break
      case "Escape":
        this.hideResults()
        break
    }
  }

  highlightItem(items) {
    items.forEach((item, index) => {
      if (index === this.selectedIndex) {
        item.classList.add("bg-amber-100", "dark:bg-amber-900/50")
      } else {
        item.classList.remove("bg-amber-100", "dark:bg-amber-900/50")
      }
    })
  }

  async fetchSuggestions(query) {
    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(query)}`
      const response = await fetch(url)

      if (!response.ok) {
        this.hideResults()
        return
      }

      const suggestions = await response.json()
      this.renderSuggestions(suggestions)
    } catch (error) {
      console.warn("Autocomplete fetch failed:", error)
      this.hideResults()
    }
  }

  renderSuggestions(suggestions) {
    if (!suggestions || suggestions.length === 0) {
      this.hideResults()
      return
    }

    this.selectedIndex = -1
    this.resultsTarget.innerHTML = suggestions.map(s => `
      <div data-suggestion data-name="${this.escapeHtml(s.name)}"
           data-action="click->taxon-autocomplete#selectSuggestion"
           class="px-4 py-2 cursor-pointer hover:bg-amber-100 dark:hover:bg-amber-900/50 transition-colors">
        <span class="font-medium text-stone-800 dark:text-stone-100">${this.escapeHtml(s.name)}</span>
        <span class="text-xs text-stone-500 dark:text-stone-400 ml-2">${this.escapeHtml(s.rank || '')}</span>
      </div>
    `).join("")

    this.resultsTarget.classList.remove("hidden")
  }

  selectSuggestion(event) {
    const name = event.currentTarget.dataset.name
    if (name) {
      this.inputTarget.value = name
    }
    this.hideResults()
    this.inputTarget.focus()
  }

  hideResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.classList.add("hidden")
      this.resultsTarget.innerHTML = ""
    }
    this.selectedIndex = -1
  }

  clearDebounce() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = null
    }
  }

  onBlur() {
    // Delay to allow click on suggestion
    setTimeout(() => this.hideResults(), 150)
  }

  escapeHtml(text) {
    if (!text) return ""
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}

