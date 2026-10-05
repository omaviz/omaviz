.pragma library

// Pure state machine for one asynchronous writer. null means no pending write;
// an empty document is still a valid value. QML owns I/O and error reporting.
function create(text) {
  return { disk: text || "", desired: null, inFlight: null, awaitingRead: false }
}
function current(queue) { return queue.desired === null ? queue.disk : queue.desired }
function edit(queue, text) {
  if (text === current(queue)) return false
  queue.desired = text
  return true
}
function next(queue) {
  if (queue.inFlight !== null || queue.awaitingRead || queue.desired === null) return null
  if (queue.desired === queue.disk) { queue.desired = null; return null }
  queue.inFlight = queue.desired
  return queue.inFlight
}
function saved(queue) {
  if (queue.inFlight === null) return
  queue.disk = queue.inFlight
  if (queue.desired === queue.inFlight) queue.desired = null
  queue.inFlight = null
  queue.awaitingRead = true
}
function loaded(queue, text) {
  if (queue.inFlight !== null) return
  queue.disk = text
  queue.awaitingRead = false
}
function failed(queue) {
  queue.inFlight = null
  queue.desired = null
  queue.awaitingRead = false
}
if (typeof module !== "undefined") module.exports = { create, current, edit, next, saved, loaded, failed }
