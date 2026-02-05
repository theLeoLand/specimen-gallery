import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="theme"
export default class extends Controller {
  static targets = ["lightIcon", "darkIcon"]

  connect() {
    this.updateIcons()
  }

  toggle() {
    const isDark = document.documentElement.classList.contains("dark")
    
    if (isDark) {
      document.documentElement.classList.remove("dark")
      localStorage.setItem("theme", "light")
    } else {
      document.documentElement.classList.add("dark")
      localStorage.setItem("theme", "dark")
    }
    
    this.updateIcons()
  }

  updateIcons() {
    const isDark = document.documentElement.classList.contains("dark")
    
    if (this.hasLightIconTarget && this.hasDarkIconTarget) {
      // Show sun icon in dark mode (to switch to light)
      // Show moon icon in light mode (to switch to dark)
      this.lightIconTarget.classList.toggle("hidden", !isDark)
      this.darkIconTarget.classList.toggle("hidden", isDark)
    }
  }
}

