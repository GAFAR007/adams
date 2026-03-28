/**
 * WHAT: Preserves the legacy backend entry path while delegating to `server.js`.
 * WHY: Some tools still look for `index.js`, and this keeps that reference safe during the transition.
 * HOW: Re-export the server bootstrap module without duplicating runtime logic.
 */

module.exports = require("./server");
