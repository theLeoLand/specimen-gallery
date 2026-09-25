import { Controller } from "@hotwired/stimulus"

// Admin image resize/reframe editor.
// Reuses the same canvas zoom/pan/recenter/auto-trim logic as the upload-page
// bg-preview editor, but operates on an already-attached specimen image and
// writes the reframed result into a hidden file field on submit.
export default class extends Controller {
  static targets = [
    "canvas", "editor", "staticPreview", "toggleButton", "fileField",
    "zoomSlider", "zoomValue",
    "panXSlider", "panXValue",
    "panYSlider", "panYValue",
    "statusMsg"
  ]

  static values = {
    url: String
  }

  static MAX_CANVAS = 1024

  previewImage = null
  zoom = 100
  // panX/panY are fractions of frameSize/2 in [-1, 1].
  // 0 = centered. Positive X = right, positive Y = down.
  panX = 0
  panY = 0
  // rotation in degrees, always a multiple of 90.
  rotation = 0
  trimBounds = null
  active = false
  loaded = false
  editing = false
  dragging = false
  dragStart = null

  connect() {
    this.formEl = this.element.querySelector("form")
    if (this.formEl) {
      this.boundHandleSubmit = this.handleSubmit.bind(this)
      this.formEl.addEventListener("submit", this.boundHandleSubmit)
    }

    this.boundRestoreCanvas = this.restoreCanvas.bind(this)
    document.addEventListener("visibilitychange", this.boundRestoreCanvas)

    this.boundPointerDown = this.onPointerDown.bind(this)
    this.boundPointerMove = this.onPointerMove.bind(this)
    this.boundPointerUp = this.onPointerUp.bind(this)
    if (this.hasCanvasTarget) {
      this.canvasTarget.addEventListener("pointerdown", this.boundPointerDown)
      this.canvasTarget.style.cursor = "grab"
      this.canvasTarget.style.touchAction = "none"
    }
    window.addEventListener("pointermove", this.boundPointerMove)
    window.addEventListener("pointerup", this.boundPointerUp)
    window.addEventListener("pointercancel", this.boundPointerUp)
  }

  disconnect() {
    if (this.formEl) this.formEl.removeEventListener("submit", this.boundHandleSubmit)
    document.removeEventListener("visibilitychange", this.boundRestoreCanvas)
    if (this.hasCanvasTarget) {
      this.canvasTarget.removeEventListener("pointerdown", this.boundPointerDown)
    }
    window.removeEventListener("pointermove", this.boundPointerMove)
    window.removeEventListener("pointerup", this.boundPointerUp)
    window.removeEventListener("pointercancel", this.boundPointerUp)
  }

  restoreCanvas() {
    if (document.visibilityState === "visible" && this.editing && this.previewImage) {
      this.redrawCanvas()
    }
  }

  // Toggle the editor open/closed. Lazily loads the image the first time.
  async toggle() {
    if (this.editing) {
      this.closeEditor()
      return
    }

    if (!this.loaded) {
      try {
        await this.loadImage(this.urlValue)
        this.loaded = true
      } catch (_) {
        this.flashStatus("Could not load image for editing")
        return
      }
    }

    this.openEditor()
  }

  openEditor() {
    this.editing = true
    if (this.hasStaticPreviewTarget) this.staticPreviewTarget.classList.add("hidden")
    if (this.hasEditorTarget) this.editorTarget.classList.remove("hidden")
    if (this.hasToggleButtonTarget) this.toggleButtonTarget.textContent = "Cancel resize"
    this.redrawCanvas()
  }

  // Close the editor and discard any pending edits so save leaves the image untouched.
  closeEditor() {
    this.editing = false
    this.active = false
    this.resetEdits(true)
    if (this.hasFileFieldTarget) this.fileFieldTarget.value = ""
    if (this.hasStaticPreviewTarget) this.staticPreviewTarget.classList.remove("hidden")
    if (this.hasEditorTarget) this.editorTarget.classList.add("hidden")
    if (this.hasToggleButtonTarget) this.toggleButtonTarget.textContent = "Resize / reframe image"
  }

  loadImage(url) {
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.crossOrigin = "anonymous"
      img.onload = () => {
        this.previewImage = img
        this.zoom = 100
        this.panX = 0
        this.panY = 0
        this.rotation = 0
        this.trimBounds = null
        this.resetSliders()
        resolve()
      }
      img.onerror = () => reject(new Error("Failed to load image"))
      img.src = url
    })
  }

  redrawCanvas() {
    if (!this.previewImage || !this.hasCanvasTarget) return

    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")
    const img = this.previewImage

    const bounds = this.trimBounds || { x: 0, y: 0, w: img.width, h: img.height }

    const rawFrame = Math.max(img.width, img.height)
    const frameSize = Math.min(rawFrame, this.constructor.MAX_CANVAS)
    const ratio = frameSize / rawFrame

    canvas.width = frameSize
    canvas.height = frameSize

    const scale = (this.zoom / 100) * ratio
    const drawW = Math.round(bounds.w * scale)
    const drawH = Math.round(bounds.h * scale)
    const offsetX = Math.round(this.panX * frameSize / 2)
    const offsetY = Math.round(this.panY * frameSize / 2)

    ctx.clearRect(0, 0, frameSize, frameSize)
    ctx.save()
    // Pan first (screen space), then rotate about the panned center so the
    // drag/pan direction stays intuitive regardless of orientation.
    ctx.translate(frameSize / 2 + offsetX, frameSize / 2 + offsetY)
    if (this.rotation) ctx.rotate((this.rotation * Math.PI) / 180)
    ctx.drawImage(img, bounds.x, bounds.y, bounds.w, bounds.h, -drawW / 2, -drawH / 2, drawW, drawH)
    ctx.restore()

    this.active = true
  }

  // Rotate the image 90° clockwise per click (cycles 0 → 90 → 180 → 270 → 0).
  rotate() {
    if (!this.previewImage) return
    this.rotation = (this.rotation + 90) % 360
    this.redrawCanvas()
    this.flashStatus(`Rotated ${this.rotation}°`)
  }

  adjustZoom(event) {
    this.zoom = parseInt(event.target.value, 10)
    if (this.hasZoomValueTarget) this.zoomValueTarget.textContent = `${this.zoom}%`
    this.redrawCanvas()
  }

  adjustPanX(event) {
    this.panX = parseInt(event.target.value, 10) / 100
    this.updatePanLabels()
    this.redrawCanvas()
  }

  adjustPanY(event) {
    this.panY = parseInt(event.target.value, 10) / 100
    this.updatePanLabels()
    this.redrawCanvas()
  }

  recenter() {
    this.panX = 0
    this.panY = 0
    this.syncPanSliders()
    this.redrawCanvas()
    this.flashStatus("Recentered")
  }

  onPointerDown(event) {
    if (!this.editing || !this.previewImage) return
    event.preventDefault()
    this.dragging = true
    this.canvasTarget.setPointerCapture(event.pointerId)
    this.canvasTarget.style.cursor = "grabbing"
    this.dragStart = {
      x: event.clientX,
      y: event.clientY,
      panX: this.panX,
      panY: this.panY
    }
  }

  onPointerMove(event) {
    if (!this.dragging || !this.previewImage || !this.hasCanvasTarget) return
    const rect = this.canvasTarget.getBoundingClientRect()
    if (rect.width === 0 || rect.height === 0) return

    const dx = event.clientX - this.dragStart.x
    const dy = event.clientY - this.dragStart.y

    // CSS pixels → canvas fraction (canvas spans -1..1 across full width/height).
    const fracX = (dx / rect.width) * 2
    const fracY = (dy / rect.height) * 2

    this.panX = this.clamp(this.dragStart.panX + fracX, -1, 1)
    this.panY = this.clamp(this.dragStart.panY + fracY, -1, 1)
    this.syncPanSliders()
    this.redrawCanvas()
  }

  onPointerUp(event) {
    if (!this.dragging) return
    this.dragging = false
    if (this.hasCanvasTarget) {
      try { this.canvasTarget.releasePointerCapture(event.pointerId) } catch (_) {}
      this.canvasTarget.style.cursor = "grab"
    }
  }

  clamp(v, min, max) {
    return Math.max(min, Math.min(max, v))
  }

  syncPanSliders() {
    if (this.hasPanXSliderTarget) this.panXSliderTarget.value = Math.round(this.panX * 100)
    if (this.hasPanYSliderTarget) this.panYSliderTarget.value = Math.round(this.panY * 100)
    this.updatePanLabels()
  }

  updatePanLabels() {
    if (this.hasPanXValueTarget) {
      const v = Math.round(this.panX * 100)
      this.panXValueTarget.textContent = v === 0 ? "0" : (v > 0 ? `+${v}` : `${v}`)
    }
    if (this.hasPanYValueTarget) {
      const v = Math.round(this.panY * 100)
      this.panYValueTarget.textContent = v === 0 ? "0" : (v > 0 ? `+${v}` : `${v}`)
    }
  }

  autoTrim() {
    if (!this.previewImage) return

    const img = this.previewImage
    const maxScan = this.constructor.MAX_CANVAS
    const scanScale = Math.min(1, maxScan / Math.max(img.width, img.height))
    const sw = Math.round(img.width * scanScale)
    const sh = Math.round(img.height * scanScale)

    const offscreen = document.createElement("canvas")
    offscreen.width = sw
    offscreen.height = sh
    const ctx = offscreen.getContext("2d")
    ctx.drawImage(img, 0, 0, sw, sh)

    const imageData = ctx.getImageData(0, 0, sw, sh)
    const { data, width, height } = imageData

    let minX = width, minY = height, maxX = 0, maxY = 0

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const alpha = data[(y * width + x) * 4 + 3]
        if (alpha > 10) {
          if (x < minX) minX = x
          if (x > maxX) maxX = x
          if (y < minY) minY = y
          if (y > maxY) maxY = y
        }
      }
    }

    if (maxX >= minX && maxY >= minY) {
      const invScale = 1 / scanScale
      const pad = Math.max(8, Math.round(Math.max(maxX - minX, maxY - minY) * invScale * 0.03))
      const newBounds = {
        x: Math.max(0, Math.round(minX * invScale) - pad),
        y: Math.max(0, Math.round(minY * invScale) - pad),
        w: Math.min(img.width, Math.round((maxX - minX) * invScale) + pad * 2),
        h: Math.min(img.height, Math.round((maxY - minY) * invScale) + pad * 2)
      }

      const old = this.trimBounds || { x: 0, y: 0, w: img.width, h: img.height }
      const changed = Math.abs(newBounds.x - old.x) > 2 || Math.abs(newBounds.y - old.y) > 2 ||
                      Math.abs(newBounds.w - old.w) > 2 || Math.abs(newBounds.h - old.h) > 2

      this.trimBounds = newBounds
      this.redrawCanvas()
      this.flashStatus(changed ? "Trimmed!" : "Already tight — nothing to trim")
    } else {
      this.flashStatus("No specimen found to trim")
    }
  }

  resetEdits(silent = false) {
    this.zoom = 100
    this.panX = 0
    this.panY = 0
    this.rotation = 0
    this.trimBounds = null
    this.resetSliders()
    if (this.previewImage && this.hasCanvasTarget) this.redrawCanvas()
    if (!silent) this.flashStatus("Reset to original")
  }

  resetSliders() {
    if (this.hasZoomSliderTarget) this.zoomSliderTarget.value = 100
    if (this.hasZoomValueTarget) this.zoomValueTarget.textContent = "100%"
    this.syncPanSliders()
  }

  flashStatus(message) {
    if (!this.hasStatusMsgTarget) return
    const el = this.statusMsgTarget
    el.textContent = message
    el.classList.remove("hidden", "opacity-0")
    el.classList.add("opacity-100")
    clearTimeout(this._statusTimer)
    this._statusTimer = setTimeout(() => {
      el.classList.replace("opacity-100", "opacity-0")
      setTimeout(() => el.classList.add("hidden"), 300)
    }, 2500)
  }

  handleSubmit(_event) {
    // Only swap in a reframed image if the editor is open and an edit was rendered.
    if (!this.editing || !this.active || !this.hasCanvasTarget || !this.hasFileFieldTarget) return

    const dataUrl = this.canvasTarget.toDataURL("image/png")
    const blob = this.dataUrlToBlob(dataUrl)
    const file = new File([blob], "specimen_resized.png", { type: "image/png", lastModified: Date.now() })

    const dt = new DataTransfer()
    dt.items.add(file)
    this.fileFieldTarget.files = dt.files
  }

  dataUrlToBlob(dataUrl) {
    const parts = dataUrl.split(",")
    const mime = parts[0].match(/:(.*?);/)[1]
    const bstr = atob(parts[1])
    const arr = new Uint8Array(bstr.length)
    for (let i = 0; i < bstr.length; i++) arr[i] = bstr.charCodeAt(i)
    return new Blob([arr], { type: mime })
  }
}
