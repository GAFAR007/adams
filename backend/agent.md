# Backend Agent Instructions

## WHAT

This file defines the non-negotiable rules for any AI agent, coding assistant, or automated helper
working in the backend for this project.

## WHY

The backend is the operational source of truth for an AI-assisted service business:
- customers chat with AI
- AI collects and structures request data
- human staff review and edit the draft
- human staff send quotes or confirm appointments
- customers receive final confirmation from the business, not from AI

The code must stay modular, safe, auditable, and easy to extend without collapsing into tightly
coupled logic.

## HOW

Follow these rules exactly. If a request conflicts with them, STOP and ASK instead of guessing.

---

## 0) Backend product goal

Build a production-grade Node.js / Express / MongoDB backend that is:

- correct
- secure
- observable
- reversible
- frontend-friendly
- AI-ready
- easy to review and maintain

This is not an autonomous booking backend.

AI is allowed to:
- collect customer intent
- ask guided follow-up questions
- create structured draft requests
- flag missing information
- suggest next actions for staff review

AI is NOT allowed to:
- promise a final price
- guarantee a time slot
- confirm a booking as final
- silently change business rules
- bypass human review for quote or appointment confirmation

---

## 1) Preferred backend stack

Use these conventions unless explicitly told otherwise:

- Runtime: Node.js
- API: Express
- Database: MongoDB with Mongoose
- Auth: `jsonwebtoken`, `bcryptjs`
- Validation: `express-validator`
- Security: `helmet`, `cors`
- Config: `dotenv`
- Logging: `morgan` plus explicit structured logs
- Uploads: `multer`
- Document parsing: `mammoth`, `pdf-parse`, `tesseract.js`
- PDF generation: `pdfkit`

Preferred scripts:

```json
{
  "dev": "nodemon server.js",
  "start": "node server.js",
  "seed": "node src/utils/seed.js"
}
```

Preferred backend entry point:

- `server.js`

If the current codebase has not reached that structure yet, do not force a refactor during an
unrelated task. Move one safe step at a time.

---

## 2) Non-negotiable workflow

1. Work one step at a time.
2. Prefer small, safe, reversible changes.
3. Do not rename or move files unless explicitly requested.
4. Once a folder pattern is established, preserve it.
5. Do not mix architecture cleanup with feature work unless asked.
6. After each change:
   - verify immediately
   - explain what changed
   - explain why it changed
   - explain how to test it

If placement, behavior, permissions, or data ownership are unclear: STOP and ASK.

---

## 3) Mandatory documentation rules

### 3.1 File header docs

Every new or edited backend file must begin with brief header documentation covering:

- WHAT the file does
- WHY it exists
- HOW it works

### 3.2 Inline comments

Inline comments must explain WHY a step exists, especially at these boundaries:

- route entry
- controller validation
- service orchestration
- database query intent
- external provider calls
- response shaping
- error mapping

Top-of-file documentation is not enough by itself.

If a file contains meaningful logic, the changed path must also carry inline comments near the code,
not only at the header.

Preferred inline comment style:

- short `WHY:` comments before important logic blocks
- short comments before guards, early returns, auth checks, query decisions, emits, and side effects
- comments that explain the business reason for the step, not just the syntax

Preferred examples:

- `// WHY: Reject stale tokens before protected work starts.`
- `// WHY: Load the customer first so the contact snapshot is built from trusted data.`
- `// WHY: Keep socket emission centralized so realtime behavior stays consistent.`
- `// WHY: Return a safe client message without leaking internal failure details.`

When editing backend files:

- add or improve inline comments in the exact area you touch if the flow is not trivially obvious
- do not leave multi-step logic, branching, or side effects explained only by the file header
- prefer several small inline comments over one distant high-level comment when the flow has stages

Forbidden:

- silent complex logic
- vague comments that restate code without explaining the reason
- relying on header comments alone for non-trivial logic

---

## 4) Architecture rules

Direction is strict:

`routes -> controllers -> services -> models`

Responsibilities are strict:

- routes: wiring only
- controllers: validation, request parsing, response shaping
- services: business logic and orchestration
- models: schema, indexes, hooks, validators
- middleware: auth, permissions, shared request guards
- utils/helpers: pure shared helpers only

Forbidden:

- routes calling MongoDB directly
- controllers containing business calculations
- services returning unsafe raw internal data
- models containing request-specific logic
- hidden side effects spread across layers

---

## 5) Modularity rules

This codebase must stay in small components.

### 5.1 File responsibility rule

A file should do one job for one feature area.

If a file becomes hard to explain quickly, split it before expanding it.

### 5.2 Function responsibility rule

A function must do one action.

If the explanation needs the word "and", split the function.

### 5.3 Extract-before-expand rule

Before adding new logic:

- check for similar existing logic
- extract shared helpers if duplication is forming
- reuse mappers, validators, and guards instead of copying logic

Duplicated business logic is forbidden.

---

## 6) Product truth rules

The backend must model this workflow clearly:

1. Customer chats with AI
2. AI creates a draft request
3. Human staff review and edit
4. Human staff send quote or confirm appointment
5. Customer receives final business confirmation

Rules:

- draft requests must be marked as drafts
- AI-generated fields must be traceable
- human edits must be traceable
- final quote/booking confirmation must record the acting human staff member
- customer-visible status must never imply final confirmation before human approval

Suggested lifecycle examples:

- `draft_collecting`
- `draft_ready_for_review`
- `awaiting_staff`
- `quoted`
- `appointment_confirmed`
- `closed`

If a status meaning is unclear, STOP and ASK before inventing one.

---

## 7) Auth, roles, and access

Expected roles:

- `admin`
- `staff`
- `customer`

Possible later roles:

- `dispatcher`
- `manager`
- `field_staff`

Rules:

- never infer role from request shape
- enforce permissions in middleware and service guards
- use least privilege
- return `403` for forbidden actions unless a route contract says otherwise
- never log passwords, tokens, secrets, or raw credential payloads

---

## 8) Scoping and data ownership

If a resource belongs to a business, branch, team, or assigned staff scope, that scope must be
enforced in every read and write.

Rules:

- resolve scope from authenticated context where possible
- validate access before query execution
- filter queries by the correct ownership key
- never trust client-provided ownership identifiers without permission checks

If ownership boundaries are unclear, STOP and ASK.

---

## 9) Validation rules

Validate at the controller boundary or dedicated validator layer.

Never let invalid inputs reach MongoDB or any external provider.

Forbidden:

- silent coercion that changes business meaning
- fuzzy parsing for money, dates, ids, or quantities
- pretending incomplete AI draft data is confirmed data

Draft-phase validation should be soft and helpful.
Final save / confirmation validation should be strict.

---

## 10) Logging rules

Logs must make failures easy to locate.

The default logging style must be simple, stage-based, and easy to scan in a terminal.

Preferred success log style:

- one short line per stage
- plain English wording
- no raw JSON blocks in normal local development output
- no internal method names unless they help explain a failure

Preferred examples:

- `MongoDB connecting`
- `MongoDB connected`
- `Server ready on port 4000`
- `POST /api/v1/auth/login received`
- `POST /api/v1/auth/login validated`
- `Login started`
- `Checking account`
- `Account found`
- `Session created`
- `Login successful`

Rules:

- startup logs should stay very short
- request logs should show the flow in order
- success logs should usually stay on one line
- error logs may add one extra detail line with reason, code, and next action
- do not dump full payloads in terminal logs just because the data is available
- prefer wording a non-technical operator can still understand quickly
- if a log reads like an internal implementation detail instead of an operational stage, rewrite it

The purpose of local logs is fast debugging, not perfect machine readability.
If structured JSON logging is needed for production transports, keep that as a separate mode.

Every meaningful request path should include these checkpoints:

1. `ROUTE_IN`
2. `AUTH_OK` or `AUTH_FAIL`
3. `VALIDATION_OK` or `VALIDATION_FAIL`
4. `SERVICE_START`
5. `DB_QUERY_START`
6. `DB_QUERY_OK` or `DB_QUERY_FAIL`
7. `PROVIDER_CALL_START` when external calls exist
8. `PROVIDER_CALL_OK` or `PROVIDER_CALL_FAIL`
9. `SERVICE_OK` or `SERVICE_FAIL`
10. `CONTROLLER_RESPONSE_OK` or `CONTROLLER_RESPONSE_FAIL`

Every log should include, when available:

- `requestId`
- route
- step
- layer
- operation
- intent
- actor role
- safe ownership context

On failure also include:

- classification
- error_code
- resolution_hint

Never log:

- tokens
- secrets
- passwords
- full PII payloads
- raw provider credentials

---

## 11) Failure classification rules

Allowed classifications:

- `INVALID_INPUT`
- `MISSING_REQUIRED_FIELD`
- `COUNTRY_UNSUPPORTED`
- `POSTAL_CODE_MISMATCH`
- `PROVIDER_REJECTED_FORMAT`
- `AUTHENTICATION_ERROR`
- `RATE_LIMITED`
- `PROVIDER_OUTAGE`
- `UNKNOWN_PROVIDER_ERROR`

Classification alone is not enough.

Every error must also include:

- `error_code`
- `step`
- `resolution_hint`

If you cannot name a precise `error_code`, STOP and ASK.

---

## 12) Error response shape

Use safe, UI-ready errors.

```json
{
  "message": "Safe message",
  "classification": "INVALID_INPUT",
  "error_code": "FEATURE_OPERATION_REASON",
  "requestId": "req_123",
  "resolution_hint": "Next action"
}
```

Forbidden:

- stack traces in responses
- raw provider payloads
- vague error bodies that hide the actual failure step

---

## 13) MongoDB and Mongoose rules

Rules:

- define schemas intentionally
- add indexes for real query patterns
- validate at schema level when useful
- paginate large lists
- never return unbounded collections
- sanitize documents before returning them

For chat and timeline-heavy features:

- index `conversationId` + `createdAt`
- index fields used for inbox views and assignment queues
- store timestamps consistently

Do not use MongoDB flexibility as an excuse for inconsistent shapes.

---

## 14) Money, dates, and time

### 14.1 Money

All money must be stored and computed as integer minor units.

Examples:

- GBP -> pence
- EUR -> cents
- USD -> cents

Do not use floats for money.

### 14.2 Time

- store timestamps in UTC
- return explicit date ranges for analytics
- do not introduce hidden timezone conversion rules
- if local appointment windows matter, store the timezone explicitly

---

## 15) Chat and realtime rules

Chat must feel instant, but the backend must stay safe.

Rules:

- never run AI inside socket events
- never upload files through sockets
- save message first, then emit
- handle receipts and secondary work asynchronously
- keep AI processing out of the realtime hot path

AI handoff rules:

- AI may collect and summarize
- AI may mark a draft as ready for human review
- only human staff may send final quote or booking confirmation
- the customer must be able to tell whether the current reply is AI or human

---

## 16) External provider rules

For any external integration:

- keep secrets on the backend only
- validate and rate-limit inputs
- sanitize provider failures
- log service name, operation, intent, safe request context, status, provider code if present,
  classification, and resolution hint

Blind retries are forbidden.

After a failure, log one of:

- `retry_allowed: true`
- `retry_skipped: true`

with the reason.

---

## 17) Definition of done

A backend slice is done only when:

- architecture boundaries are respected
- validation exists
- permissions exist where needed
- scoping exists where needed
- logs include the right checkpoints
- response shapes are safe and consistent
- changes are verified immediately
- test steps are explained clearly

---

## 18) Global alignment rules

Backend and frontend instruction files must stay aligned on cross-cutting rules:

- safety
- security
- observability
- AI draft behavior
- human confirmation rules
- chat responsiveness
- modularity

If a new cross-cutting rule is added here, mirror it in `frontend/agent.md`.

If there is a conflict between backend and frontend rules, STOP and ASK.
