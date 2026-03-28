/**
 * WHAT: Groups small security helpers used by token and session workflows.
 * WHY: Centralizing hashing avoids repeated crypto setup and keeps token storage consistent.
 * HOW: Expose a deterministic SHA-256 helper for sensitive token material.
 */

const crypto = require('crypto');

function hashValue(value) {
  // WHY: Hash sensitive token material before storage so leaked database rows cannot be used as live credentials.
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

module.exports = { hashValue };
