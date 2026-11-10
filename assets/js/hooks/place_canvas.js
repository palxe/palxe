// Renders the shared canvas and handles pan / zoom / pixel selection.
//
// The server is the source of truth: the hook asks for the full canvas with
// the "load" event, then applies incremental "pixel" events pushed from the
// LiveView as other players place tiles.

const MIN_SCALE = 0.5
const MAX_SCALE = 64
const SELECT_SCALE = 12
const CLICK_SLOP = 6

const hexToRgb = (hex) => {
  const n = parseInt(hex.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v))

export const PlaceCanvas = {
  mounted() {
    this.width = parseInt(this.el.dataset.width, 10)
    this.height = parseInt(this.el.dataset.height, 10)
    this.world = this.el.querySelector("[data-role=world]")
    this.canvas = this.el.querySelector("[data-role=canvas]")
    this.reticle = this.el.querySelector("[data-role=reticle]")
    this.loading = this.el.querySelector("[data-role=loading]")
    this.ctx = this.canvas.getContext("2d")
    this.hoverEl = document.getElementById("hover-coords")

    this.palette = null
    this.selected = null
    this.pointers = new Map()
    this.fit()

    this.listen(this.el, "pointerdown", (e) => this.onPointerDown(e))
    this.listen(this.el, "pointermove", (e) => this.onPointerMove(e))
    this.listen(this.el, "pointerup", (e) => this.onPointerUp(e))
    this.listen(this.el, "pointercancel", (e) => this.onPointerUp(e, true))
    this.listen(this.el, "pointerleave", () => this.hoverEl?.classList.add("opacity-60"))
    this.listen(this.el, "wheel", (e) => this.onWheel(e), {passive: false})
    this.listen(this.el, "place:zoom", (e) => {
      const r = this.el.getBoundingClientRect()
      this.animateZoom(this.scale * e.detail.factor, r.width / 2, r.height / 2)
    })
    this.listen(window, "resize", () => this.applyTransform())
    this.listen(window, "keydown", (e) => {
      if (e.key === "Escape" && this.selected) this.pushEvent("deselect", {})
    })

    this.handleEvent("pixel", ({x, y, c}) => this.paint(x, y, c))
    this.handleEvent("placed", ({x, y, c}) => {
      this.paint(x, y, c)
      this.hideReticle()
      this.burst(x, y)
    })
    this.handleEvent("deselect", () => this.hideReticle())
    this.handleEvent("color", ({hex}) => {
      this.reticle.style.setProperty("--reticle-color", hex)
      this.reticle.classList.add("has-color")
    })

    this.load()
  },

  reconnected() {
    this.load()
  },

  destroyed() {
    this.cleanups?.forEach((fn) => fn())
    cancelAnimationFrame(this.anim)
  },

  listen(target, event, fn, opts) {
    target.addEventListener(event, fn, opts)
    ;(this.cleanups ||= []).push(() => target.removeEventListener(event, fn, opts))
  },

  // ---- Data ---------------------------------------------------------------

  load() {
    this.pushEvent("load", {}, ({width, height, palette, pixels}) => {
      this.palette = palette.map(hexToRgb)
      this.paletteHex = palette

      const bytes = Uint8Array.from(atob(pixels), (ch) => ch.charCodeAt(0))
      const image = this.ctx.createImageData(width, height)
      const data = image.data
      for (let i = 0; i < bytes.length; i++) {
        const [r, g, b] = this.palette[bytes[i]] || [255, 255, 255]
        const o = i * 4
        data[o] = r
        data[o + 1] = g
        data[o + 2] = b
        data[o + 3] = 255
      }
      this.ctx.putImageData(image, 0, 0)
      this.loading.classList.add("opacity-0", "pointer-events-none")
    })
  },

  paint(x, y, c) {
    if (!this.paletteHex) return // full load will include it
    this.ctx.fillStyle = this.paletteHex[c]
    this.ctx.fillRect(x, y, 1, 1)
  },

  // ---- View transform -----------------------------------------------------

  fit() {
    const r = this.el.getBoundingClientRect()
    const s = Math.max(MIN_SCALE, Math.min(r.width / this.width, r.height / this.height) * 0.9)
    this.scale = s
    this.tx = (r.width - this.width * s) / 2
    this.ty = (r.height - this.height * s) / 2
    this.applyTransform()
  },

  applyTransform() {
    this.world.style.transform = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale})`
    if (this.selected) this.positionReticle()
  },

  zoomAt(newScale, px, py) {
    const s = clamp(newScale, MIN_SCALE, MAX_SCALE)
    this.tx = px - (px - this.tx) * (s / this.scale)
    this.ty = py - (py - this.ty) * (s / this.scale)
    this.scale = s
    this.applyTransform()
  },

  animateZoom(targetScale, px, py) {
    const s = clamp(targetScale, MIN_SCALE, MAX_SCALE)
    const tx = px - (px - this.tx) * (s / this.scale)
    const ty = py - (py - this.ty) * (s / this.scale)
    this.animateTo(s, tx, ty)
  },

  animateTo(scale, tx, ty, duration = 280) {
    cancelAnimationFrame(this.anim)
    const from = {scale: this.scale, tx: this.tx, ty: this.ty}
    const start = performance.now()
    const ease = (t) => 1 - Math.pow(1 - t, 3)
    const step = (now) => {
      const t = ease(Math.min(1, (now - start) / duration))
      this.scale = from.scale + (scale - from.scale) * t
      this.tx = from.tx + (tx - from.tx) * t
      this.ty = from.ty + (ty - from.ty) * t
      this.applyTransform()
      if (t < 1) this.anim = requestAnimationFrame(step)
    }
    this.anim = requestAnimationFrame(step)
  },

  toPixel(px, py) {
    return [Math.floor((px - this.tx) / this.scale), Math.floor((py - this.ty) / this.scale)]
  },

  inBounds(x, y) {
    return x >= 0 && y >= 0 && x < this.width && y < this.height
  },

  // ---- Input --------------------------------------------------------------

  local(e) {
    const r = this.el.getBoundingClientRect()
    return [e.clientX - r.left, e.clientY - r.top]
  },

  onPointerDown(e) {
    if (e.button !== undefined && e.button !== 0 && e.pointerType === "mouse") return
    cancelAnimationFrame(this.anim)
    this.el.setPointerCapture(e.pointerId)
    const [x, y] = this.local(e)
    this.pointers.set(e.pointerId, {x, y, startX: x, startY: y})
    this.moved = this.pointers.size > 1 ? true : false
    this.pinchDist = null
  },

  onPointerMove(e) {
    const [x, y] = this.local(e)
    this.updateHover(x, y)

    const p = this.pointers.get(e.pointerId)
    if (!p) return

    if (this.pointers.size === 1) {
      this.tx += x - p.x
      this.ty += y - p.y
      if (Math.hypot(x - p.startX, y - p.startY) > CLICK_SLOP) {
        this.moved = true
        this.el.classList.add("cursor-grabbing")
      }
      p.x = x
      p.y = y
      this.applyTransform()
    } else if (this.pointers.size === 2) {
      p.x = x
      p.y = y
      const [a, b] = [...this.pointers.values()]
      const dist = Math.hypot(a.x - b.x, a.y - b.y)
      const mx = (a.x + b.x) / 2
      const my = (a.y + b.y) / 2
      if (this.pinchDist) {
        this.zoomAt(this.scale * (dist / this.pinchDist), mx, my)
        this.tx += mx - this.pinchMid[0]
        this.ty += my - this.pinchMid[1]
        this.applyTransform()
      }
      this.pinchDist = dist
      this.pinchMid = [mx, my]
    }
  },

  onPointerUp(e, cancelled = false) {
    const p = this.pointers.get(e.pointerId)
    this.pointers.delete(e.pointerId)
    this.el.classList.remove("cursor-grabbing")
    if (this.pointers.size < 2) this.pinchDist = null
    if (!p || cancelled || this.moved || this.pointers.size > 0) return

    const [x, y] = this.toPixel(p.x, p.y)
    if (this.inBounds(x, y)) this.select(x, y)
  },

  onWheel(e) {
    e.preventDefault()
    const [x, y] = this.local(e)
    if (e.ctrlKey || Math.abs(e.deltaY) >= Math.abs(e.deltaX)) {
      this.zoomAt(this.scale * Math.exp(-e.deltaY * 0.0018), x, y)
    } else {
      this.tx -= e.deltaX
      this.ty -= e.deltaY
      this.applyTransform()
    }
    this.updateHover(x, y)
  },

  updateHover(px, py) {
    if (!this.hoverEl) return
    const [x, y] = this.toPixel(px, py)
    this.hoverEl.classList.remove("opacity-60")
    if (this.inBounds(x, y)) {
      this.hoverEl.textContent = `(${x}, ${y}) ${this.scale.toFixed(1)}×`
    }
  },

  // ---- Selection ----------------------------------------------------------

  select(x, y) {
    this.selected = {x, y}
    this.pushEvent("select_pixel", {x, y})
    this.reticle.classList.remove("hidden")
    this.positionReticle()

    // Zoom in on the chosen pixel, keeping it above the bottom panel.
    const r = this.el.getBoundingClientRect()
    const s = Math.max(this.scale, SELECT_SCALE)
    const cx = r.width / 2
    const cy = r.height * 0.4
    this.animateTo(s, cx - (x + 0.5) * s, cy - (y + 0.5) * s)
  },

  hideReticle() {
    this.selected = null
    this.reticle.classList.add("hidden")
  },

  positionReticle() {
    const {x, y} = this.selected
    const s = this.scale
    Object.assign(this.reticle.style, {
      left: `${this.tx + x * s}px`,
      top: `${this.ty + y * s}px`,
      width: `${s}px`,
      height: `${s}px`,
    })
  },

  burst(x, y) {
    const el = document.createElement("div")
    el.className = "place-burst"
    const s = this.scale
    Object.assign(el.style, {
      left: `${this.tx + (x + 0.5) * s}px`,
      top: `${this.ty + (y + 0.5) * s}px`,
    })
    this.el.appendChild(el)
    setTimeout(() => el.remove(), 700)
  },
}

// Live countdown for the per-player cooldown. The server renders the
// deadline in data-until (unix ms); this keeps the text ticking client side.
export const Cooldown = {
  mounted() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 250)
  },
  updated() {
    this.tick()
  },
  destroyed() {
    clearInterval(this.timer)
  },
  tick() {
    const until = parseInt(this.el.dataset.until, 10)
    const secs = Math.max(0, Math.ceil((until - Date.now()) / 1000))
    this.el.textContent = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}`
  },
}
