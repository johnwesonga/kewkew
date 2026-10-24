// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/kewkew"
import topbar from "../vendor/topbar"
import QRCode from "qrcode"

const formatLocationTimes = root => {
  const times = []
  if (root.matches?.("time[data-location-time]")) times.push(root)
  times.push(...root.querySelectorAll?.("time[data-location-time]") || [])

  for (const time of times) {
    const key = `${time.dateTime}:${time.dataset.timezone}`
    if (time.dataset.formattedKey === key) continue

    try {
      time.textContent = new Intl.DateTimeFormat(undefined, {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: time.dataset.timezone,
      }).format(new Date(time.dateTime))
      time.dataset.formattedKey = key
    } catch (_error) {
      // Keep the ISO UTC timestamp if the browser cannot format this timezone.
    }
  }
}

formatLocationTimes(document)
new MutationObserver(records => {
  for (const record of records) {
    for (const node of record.addedNodes) {
      if (node.nodeType === Node.ELEMENT_NODE) formatLocationTimes(node)
    }

    if (record.type === "attributes" && record.target.matches("time[data-location-time]")) {
      formatLocationTimes(record.target)
    }
  }
}).observe(document.documentElement, {
  subtree: true,
  childList: true,
  attributes: true,
  attributeFilter: ["datetime", "data-timezone"],
})

document.addEventListener("click", async event => {
  const button = event.target.closest("[data-copy-target]")
  if (!button) return

  const input = document.getElementById(button.dataset.copyTarget)
  const value = button.dataset.copyValue || input?.value
  const status = document.getElementById(button.dataset.copyStatus || "visitor-tracking-link-status")
  if (!value || !status) return

  const fallbackCopy = () => {
    const textArea = document.createElement("textarea")
    textArea.value = value
    textArea.setAttribute("readonly", "")
    textArea.style.position = "fixed"
    textArea.style.opacity = "0"
    document.body.appendChild(textArea)
    textArea.select()

    const copied = document.execCommand("copy")
    textArea.remove()
    return copied
  }

  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value)
      status.textContent = button.dataset.copyMessage || "Private link copied."
    } else {
      status.textContent = fallbackCopy()
        ? button.dataset.copyMessage || "Private link copied."
        : button.dataset.copyFallback || "Select and copy your private link."
    }
  } catch (_error) {
    status.textContent = fallbackCopy()
      ? button.dataset.copyMessage || "Private link copied."
      : button.dataset.copyFallback || "Select and copy your private link."
  }
})

const queueQr = document.getElementById("staff-queue-qr")

if (queueQr) {
  QRCode.toString(queueQr.dataset.queueUrl, {
    type: "svg",
    errorCorrectionLevel: "M",
    margin: 4,
    width: 300,
    color: {dark: "#17251f", light: "#ffffff"},
  }).then(svgMarkup => {
    const svgDocument = new DOMParser().parseFromString(svgMarkup, "image/svg+xml")
    const svg = svgDocument.documentElement

    if (svg.localName !== "svg" || svgDocument.querySelector("parsererror")) {
      throw new Error("Could not parse generated QR code SVG")
    }

    svg.setAttribute("role", "img")
    svg.setAttribute("aria-label", `QR code for ${queueQr.dataset.queueUrl}`)
    queueQr.replaceChildren(document.importNode(svg, true))

    const qrFallback = document.getElementById("staff-queue-qr-fallback")
    if (qrFallback) qrFallback.hidden = true

    const downloadButton = document.getElementById("staff-download-queue-qr")
    if (downloadButton) downloadButton.hidden = false

    const printButton = document.getElementById("staff-print-queue-qr")
    if (printButton) printButton.hidden = false
  }).catch(_error => {
    const qrFallback = document.getElementById("staff-queue-qr-fallback")
    if (qrFallback) qrFallback.textContent = "The QR code could not be generated. Use the public link instead."
  })
}

document.addEventListener("click", event => {
  const downloadButton = event.target.closest("[data-download-queue-qr]")
  if (downloadButton) {
    const queueQr = document.getElementById("staff-queue-qr")
    const svg = queueQr?.querySelector("svg")
    if (!svg) return

    const svgBlob = new Blob([new XMLSerializer().serializeToString(svg)], {
      type: "image/svg+xml;charset=utf-8",
    })
    const downloadUrl = URL.createObjectURL(svgBlob)
    const downloadLink = document.createElement("a")
    downloadLink.href = downloadUrl
    downloadLink.download = `${queueQr.dataset.queueSlug}-qr.svg`
    downloadLink.click()
    window.setTimeout(() => URL.revokeObjectURL(downloadUrl), 1000)
    return
  }

  const printButton = event.target.closest("[data-print-queue-qr]")
  if (printButton) window.print()
})

document.addEventListener("submit", event => {
  const form = event.target.closest("form[data-confirm]")
  if (form && !window.confirm(form.dataset.confirm)) event.preventDefault()
})

document.addEventListener("click", event => {
  const target = event.target.closest("button[data-confirm], a[data-confirm]")
  if (target && !window.confirm(target.dataset.confirm)) {
    event.preventDefault()
    event.stopImmediatePropagation()
  }
}, true)

const visitorTicket = document.getElementById("visitor-ticket")

const visitorQueuePage = document.querySelector("[data-availability-url]")

if (visitorQueuePage) {
  const refreshQueueAvailability = async () => {
    if (document.hidden) return

    try {
      const response = await fetch(visitorQueuePage.dataset.availabilityUrl, {
        headers: {Accept: "application/json"},
        cache: "no-store",
      })

      if (!response.ok) return

      const availability = await response.json()
      if (availability.state !== visitorQueuePage.dataset.availabilityState) {
        window.location.reload()
      }
    } catch (_error) {
      // Keep the current page and retry shortly if the status endpoint is unavailable.
    }
  }

  window.setInterval(refreshQueueAvailability, 3000)
  document.addEventListener("visibilitychange", refreshQueueAvailability)
}

if (visitorTicket) {
  const status = document.getElementById("visitor-ticket-status")
  const position = document.getElementById("visitor-ticket-position")
  const progress = document.getElementById("visitor-queue-progress")
  const cancellationForm = document.getElementById("visitor-cancel-form")
  const statusUrl = visitorTicket.dataset.statusUrl
  let lastPosition = progress?.dataset.position ? Number(progress.dataset.position) : null
  let lastStatus = visitorTicket.dataset.ticketStatus

  if (progress) {
    progress.dataset.progressActive = String(lastStatus === "waiting" && lastPosition !== null)
  }

  const refreshTicketStatus = async () => {
    if (document.hidden) return

    try {
      const response = await fetch(statusUrl, {
        headers: {Accept: "application/json"},
        cache: "no-store",
      })

      if (response.status === 404) {
        window.location.reload()
        return
      }

      if (!response.ok) return

      const ticket = await response.json()
      const positionLabel = ticket.position ? `${ticket.position} in line` : "No longer waiting"
      const positionChanged = ticket.position !== lastPosition
      const statusChanged = ticket.status !== lastStatus

      if (status.textContent !== ticket.status_label) status.textContent = ticket.status_label
      if (position.textContent.trim() !== positionLabel) position.textContent = positionLabel
      if (cancellationForm) cancellationForm.hidden = ticket.status !== "waiting"

      if (progress) {
        progress.dataset.progressActive = String(ticket.status === "waiting" && ticket.position !== null)
        if (positionChanged || (statusChanged && ticket.status !== "waiting")) {
          progress.classList.remove("is-advancing")
          if (positionChanged && ticket.status === "waiting" && ticket.position !== null) {
            void progress.offsetWidth
            progress.classList.add("is-advancing")
          }
        }
      }

      lastPosition = ticket.position
      lastStatus = ticket.status
    } catch (_error) {
      // Keep the last persisted state on screen and retry on the next interval.
    }
  }

  refreshTicketStatus()
  window.setInterval(refreshTicketStatus, 3000)
  document.addEventListener("visibilitychange", refreshTicketStatus)
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

