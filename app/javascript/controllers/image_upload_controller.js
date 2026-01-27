import { Controller } from "@hotwired/stimulus"
import imageCompression from "browser-image-compression"

// Handles client-side image compression for large mobile uploads
// Prevents Cloudinary's 10MB limit from blocking users
export default class extends Controller {
  static targets = [
    "fileInput",
    "fileInfo",
    "fileName",
    "fileSize",
    "warning",
    "warningText",
    "status",
    "statusText",
    "submitButton",
    "removeBackground"
  ]

  static values = {
    maxSizeMb: { type: Number, default: 8 },      // Compress if over this (buffer under 10MB limit)
    bgRemovalMaxSizeMb: { type: Number, default: 6 }, // Target for background removal
    hardLimitMb: { type: Number, default: 10 },   // Absolute max after compression
    maxWidthOrHeight: { type: Number, default: 3000 }, // Good for high-res displays
    bgRemovalMaxDimension: { type: Number, default: 1800 } // CRITICAL: Cloudinary BG removal counts pixel data, not file size
  }

  // Store the compressed file to submit
  compressedFile = null

  connect() {
    // Listen for form submit to swap in compressed file
    this.element.addEventListener("submit", this.handleSubmit.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("submit", this.handleSubmit.bind(this))
  }
  
  // Re-evaluate when user toggles background removal after selecting a file
  // Called via data-action="change->image-upload#bgToggleChanged" on checkbox
  bgToggleChanged() {
    if (this.hasFileInputTarget && this.fileInputTarget.files[0]) {
      // Reset compressed file and re-run the selection logic
      this.compressedFile = null
      this.fileSelected({ target: this.fileInputTarget })
    }
  }

  async fileSelected(event) {
    const file = event.target.files[0]
    if (!file) {
      this.hideFileInfo()
      return
    }

    this.compressedFile = null
    this.showFileInfo(file)

    const sizeMb = file.size / (1024 * 1024)
    const isHeic = file.type === "image/heic" || file.type === "image/heif" || 
                   file.name.toLowerCase().endsWith(".heic") || file.name.toLowerCase().endsWith(".heif")
    const bgRemovalChecked = this.hasRemoveBackgroundTarget && this.removeBackgroundTarget.checked

    // Show HEIC notice
    if (isHeic) {
      this.showWarning("HEIC format detected. Your device will convert it during upload.", "info")
    }

    // Check if compression/resizing needed
    if (sizeMb > this.hardLimitMbValue) {
      this.showWarning(`File is ${sizeMb.toFixed(1)}MB — too large to upload. Please choose a smaller image.`, "error")
      this.disableSubmit()
    } else if (bgRemovalChecked) {
      // ALWAYS resize for background removal - Cloudinary counts uncompressed pixel data, not file size
      // A 2.9MB JPEG can be 20MB+ of pixel data if dimensions are large (e.g., 4000x5000)
      await this.compressImage(file, true)
    } else if (sizeMb > this.maxSizeMbValue) {
      // Regular upload: only compress if over threshold
      await this.compressImage(file, false)
    } else {
      // File is fine, no compression needed
      this.hideWarning()
      this.enableSubmit()
    }
  }

  async compressImage(file, forBgRemoval = false) {
    const originalSizeMb = file.size / (1024 * 1024)
    
    const statusMsg = forBgRemoval 
      ? `Resizing for background removal…`
      : `Optimizing image (${originalSizeMb.toFixed(1)}MB)…`
    this.showStatus(statusMsg)
    this.disableSubmit()

    try {
      // Determine output type
      // If removing background, we'll still compress first (server converts to PNG after)
      // Otherwise, use WebP for best compression (falls back to JPEG on unsupported browsers)
      const useWebP = this.supportsWebP()
      
      // Use stricter limits for background removal since Cloudinary's BG removal API is more demanding
      const targetSizeMB = forBgRemoval ? this.bgRemovalMaxSizeMbValue : this.maxSizeMbValue
      const targetDimension = forBgRemoval ? this.bgRemovalMaxDimensionValue : this.maxWidthOrHeightValue
      
      const options = {
        maxSizeMB: targetSizeMB,
        maxWidthOrHeight: targetDimension,
        useWebWorker: true,
        fileType: useWebP ? "image/webp" : "image/jpeg",
        initialQuality: 0.92  // High quality - preserves detail for specimen gallery
      }

      // For HEIC, the library handles conversion automatically
      const compressedFile = await imageCompression(file, options)
      const compressedSizeMb = compressedFile.size / (1024 * 1024)

      // Check if still too large
      if (compressedSizeMb > this.hardLimitMbValue) {
        this.hideStatus()
        this.showWarning(
          `Could not compress enough (${compressedSizeMb.toFixed(1)}MB). Please choose a smaller image.`,
          "error"
        )
        this.disableSubmit()
        return
      }

      // Success!
      this.compressedFile = compressedFile
      this.updateFileInfo(compressedFile, originalSizeMb)
      this.hideStatus()
      
      const successMsg = forBgRemoval
        ? `Resized for background removal (${compressedSizeMb.toFixed(1)}MB) ✓`
        : `Compressed: ${originalSizeMb.toFixed(1)}MB → ${compressedSizeMb.toFixed(1)}MB ✓`
      this.showWarning(successMsg, "success")
      this.enableSubmit()

    } catch (error) {
      console.error("Compression failed:", error)
      this.hideStatus()
      
      // Fall back to original if it's under the hard limit
      const sizeMb = file.size / (1024 * 1024)
      if (sizeMb <= this.hardLimitMbValue) {
        this.showWarning(
          `Compression unavailable, but file size (${sizeMb.toFixed(1)}MB) is acceptable.`,
          "info"
        )
        this.enableSubmit()
      } else {
        this.showWarning(
          `Could not optimize image. Please use a smaller file (under ${this.hardLimitMbValue}MB).`,
          "error"
        )
        this.disableSubmit()
      }
    }
  }

  handleSubmit(event) {
    // If we have a compressed file, swap it into the form
    if (this.compressedFile && this.hasFileInputTarget) {
      // Create a new DataTransfer to set the file input
      const dataTransfer = new DataTransfer()
      
      // Create a new File with the original name (but new content)
      const originalName = this.fileInputTarget.files[0]?.name || "image.jpg"
      const extension = this.compressedFile.type === "image/webp" ? ".webp" : ".jpg"
      const newName = originalName.replace(/\.[^.]+$/, extension)
      
      const newFile = new File([this.compressedFile], newName, {
        type: this.compressedFile.type,
        lastModified: Date.now()
      })
      
      dataTransfer.items.add(newFile)
      this.fileInputTarget.files = dataTransfer.files
    }
  }

  // UI Helpers
  showFileInfo(file) {
    if (!this.hasFileInfoTarget) return
    
    const sizeMb = file.size / (1024 * 1024)
    if (this.hasFileNameTarget) this.fileNameTarget.textContent = file.name
    if (this.hasFileSizeTarget) this.fileSizeTarget.textContent = `${sizeMb.toFixed(1)} MB`
    this.fileInfoTarget.classList.remove("hidden")
  }

  updateFileInfo(file, originalSizeMb) {
    if (!this.hasFileSizeTarget) return
    const newSizeMb = file.size / (1024 * 1024)
    this.fileSizeTarget.innerHTML = `<span class="line-through text-stone-400">${originalSizeMb.toFixed(1)} MB</span> → <span class="text-emerald-600 dark:text-emerald-400 font-medium">${newSizeMb.toFixed(1)} MB</span>`
  }

  hideFileInfo() {
    if (this.hasFileInfoTarget) this.fileInfoTarget.classList.add("hidden")
  }

  showWarning(message, type = "warning") {
    if (!this.hasWarningTarget) return
    
    this.warningTarget.classList.remove("hidden")
    if (this.hasWarningTextTarget) this.warningTextTarget.textContent = message
    
    // Style based on type
    this.warningTarget.classList.remove(
      "bg-amber-50", "border-amber-200", "text-amber-800",
      "bg-red-50", "border-red-200", "text-red-800",
      "bg-emerald-50", "border-emerald-200", "text-emerald-800",
      "bg-blue-50", "border-blue-200", "text-blue-800",
      "dark:bg-amber-900/20", "dark:border-amber-800", "dark:text-amber-300",
      "dark:bg-red-900/20", "dark:border-red-800", "dark:text-red-300",
      "dark:bg-emerald-900/20", "dark:border-emerald-800", "dark:text-emerald-300",
      "dark:bg-blue-900/20", "dark:border-blue-800", "dark:text-blue-300"
    )
    
    const styles = {
      warning: ["bg-amber-50", "border-amber-200", "text-amber-800", "dark:bg-amber-900/20", "dark:border-amber-800", "dark:text-amber-300"],
      error: ["bg-red-50", "border-red-200", "text-red-800", "dark:bg-red-900/20", "dark:border-red-800", "dark:text-red-300"],
      success: ["bg-emerald-50", "border-emerald-200", "text-emerald-800", "dark:bg-emerald-900/20", "dark:border-emerald-800", "dark:text-emerald-300"],
      info: ["bg-blue-50", "border-blue-200", "text-blue-800", "dark:bg-blue-900/20", "dark:border-blue-800", "dark:text-blue-300"]
    }
    
    this.warningTarget.classList.add(...(styles[type] || styles.warning))
  }

  hideWarning() {
    if (this.hasWarningTarget) this.warningTarget.classList.add("hidden")
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.classList.remove("hidden")
    if (this.hasStatusTextTarget) this.statusTextTarget.textContent = message
  }

  hideStatus() {
    if (this.hasStatusTarget) this.statusTarget.classList.add("hidden")
  }

  disableSubmit() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
      this.submitButtonTarget.classList.remove("hover:bg-amber-700", "cursor-pointer")
    }
  }

  enableSubmit() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
      this.submitButtonTarget.classList.add("hover:bg-amber-700", "cursor-pointer")
    }
  }

  supportsWebP() {
    const canvas = document.createElement("canvas")
    canvas.width = 1
    canvas.height = 1
    return canvas.toDataURL("image/webp").startsWith("data:image/webp")
  }
}

