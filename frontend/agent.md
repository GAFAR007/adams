# Frontend Agent Instructions

## WHAT

This file defines the non-negotiable rules for any AI agent, coding assistant, or automated helper
working in the Flutter frontend for this project.

## WHY

The frontend must support a product where AI reduces friction, but humans remain responsible for
quotes and booking confirmation. The UI has to stay fast, modular, transparent, and easy to extend
across mobile and web.

## HOW

Follow these rules exactly. If a request conflicts with them, STOP and ASK instead of guessing.

---

## 0) Frontend product goal

Build a Flutter app that supports:

- customer chat with AI for service intake
- AI-generated draft requests
- clear status updates while a human reviews the request
- staff review and response flows
- human-only quote and appointment confirmation

The frontend must never pretend that an AI draft is a confirmed booking.

---

## 1) Non-negotiable workflow

1. Work one step at a time.
2. Prefer small, safe, reversible changes.
3. Do not rename or move files unless explicitly requested.
4. Once a folder pattern is established, preserve it.
5. Do not mix architecture refactors with feature work unless asked.
6. After each change:
   - verify immediately
   - explain what changed
   - explain why it changed
   - explain how to test it

If placement, state ownership, or behavior is unclear: STOP and ASK.

---

## 2) Architecture respect rules

The intended layer direction is strict:

`presentation -> application -> domain -> data`

Rules:

- UI must not call API clients directly
- domain must not import Flutter or transport concerns
- data must not contain presentation logic
- shared models should be mapped once at the boundary, not re-parsed in widgets

Do not introduce new architectural patterns without approval.

---

## 3) Mandatory documentation rules

### 3.1 File header docs

Every new or edited file must begin with brief header documentation covering:

- WHAT the file does
- WHY it exists
- HOW it works

### 3.2 Inline comments

Add comments that explain WHY a step exists, especially around:

- screen entry
- state transitions
- async flows
- navigation
- API interaction boundaries
- error mapping

Top-of-file documentation is not enough by itself.

If a changed UI flow has meaningful state handling or branching, add inline `WHY:` comments close to
that code instead of relying only on the file header.

Preferred inline comment style:

- short `WHY:` comments before important blocks
- comments near guards, redirects, state transitions, optimistic updates, and error mapping
- comments that explain the user or product reason for the step

When editing frontend files:

- add or improve inline comments in the area you change when the flow is not immediately obvious
- do not leave async or stateful behavior explained only by the file header

Forbidden:

- silent complex UI logic
- comments that only restate code without the reason

---

## 4) UI and product truth rules

The UI must reflect the real workflow:

1. Customer chats with AI
2. AI creates a draft request
3. Human staff review and edit
4. Human staff send quote or confirm appointment
5. Customer gets final confirmation from the business

Rules:

- clearly label AI messages as AI
- clearly label human messages as human
- do not show "booked" or "confirmed" until a human actually confirms
- draft states must look like drafts, not final decisions
- status text must be supportive and clear

Preferred customer-visible statuses:

- `collecting details`
- `draft prepared`
- `awaiting human review`
- `human agent joined`
- `quote sent`
- `appointment confirmed`

---

## 5) Theme and design rules

Rules:

- always use theme tokens
- prefer `Theme.of(context)`, `ColorScheme`, `TextTheme`, and shared app tokens
- do not hardcode colors in widgets unless they are approved status colors
- preserve contrast and readability across web, Android, and iOS

Do not design the UI like a static brochure site.

This app should feel operational, not decorative.

---

## 6) Logging and diagnostics rules

Logs must be useful.

The default debug-log style must be simple, stage-based, and easy to scan.

Preferred success log style:

- one short line per stage
- plain English wording
- avoid noisy object dumps during normal development
- show technical detail only when it helps resolve a failure

Preferred examples:

- `Home screen opened`
- `Login submitted`
- `Login successful`
- `Loading customer requests`
- `Customer requests ready`
- `Admin dashboard ready`
- `Staff invite submitted`

Rules:

- screen and route logs should read like user-visible stages
- API lifecycle logs should show request start, validation, success, or failure in plain English
- success logs should usually stay on one line
- failure logs may add one extra detail line with reason, code, and next action
- if a log is technically correct but hard to scan quickly, rewrite it
- prefer wording that explains what is happening, not which helper function ran

Required logging boundaries:

- screen `build()` execution when useful
- route navigation
- user actions
- request start
- request success
- request failure
- socket connection state
- chat handoff state changes

Forbidden logs:

- "request failed"
- "api error"
- logs with only an exception name or status code

Failure logs must include:

- service name
- operation name
- request intent
- safe request context
- http status when available
- provider error code when available
- provider error message/body when safe
- failure classification
- resolution hint

Never log:

- passwords
- tokens
- secrets
- raw credentials

---

## 7) Failure classification rules

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

If a failure cannot be explained clearly, STOP and ASK.

---

## 8) AI-assisted UX rules

This product uses AI as a business assistant, not as a final authority.

AI should:

- reduce friction
- guide the customer conversationally
- turn natural language into structured drafts
- ask for missing context helpfully
- explain uncertainty when needed

AI must not:

- behave like a hostile validator during draft flows
- force customers through rigid forms too early
- present assumptions as confirmed facts
- present a final quote or booking as complete without human review

Preferred tone:

- supportive
- clear
- practical

Avoid punitive messages such as "Missing required fields."

Prefer messages such as:

- "We need a little more context to prepare this request for the team."

---

## 9) Chat performance rules

Chat should feel instant.

Rules:

- use optimistic UI for outbound messages
- socket traffic is for sync, not for rendering logic
- batch read receipts where possible
- do not block message rendering on AI work
- do not upload files over sockets

The frontend must handle AI-to-human handoff clearly in the same thread.

---

## 10) API boundary rules

Rules:

- parse API responses once
- map to models once
- UI consumes models only
- widgets must not handle raw JSON
- never fake missing backend features in the UI

If backend data is missing, surface that honestly in the UI state instead of inventing values.

---

## 11) Modularity rules

This frontend must stay in small, explainable pieces.

### 11.1 Widget size rule

Widgets should stay under roughly 150 lines when practical.

If a widget grows too large, split it into focused parts.

### 11.2 Function responsibility rule

A function must do one thing.

If you need "and" to explain it, split it.

### 11.3 Extract-before-expand rule

Before adding logic:

- check whether similar logic already exists
- extract shared pieces first
- reuse existing models, mappers, validators, and route definitions

Duplicated UI state logic is forbidden.

---

## 12) No inline magic

Forbidden inline:

- hardcoded route names
- magic numbers
- repeated status labels
- raw JSON parsing in widgets
- ad-hoc API response reading in the presentation layer

Use:

- constants
- enums
- models
- mappers
- route definitions

---

## 13) Multi-platform rules

The app must work on:

- Web
- Android
- iOS

Rules:

- avoid platform assumptions in shared logic
- avoid `dart:io` in presentation or shared layers
- use platform abstractions when platform-specific behavior is needed

---

## 14) Definition of done

A frontend slice is done only when:

- architecture boundaries are respected
- UI reflects the true product workflow
- AI and human states are clearly distinguished
- logs are specific and actionable
- the change is easy to test immediately
- the change is small enough to review quickly

---

## 15) Global alignment rules

Frontend and backend instruction files must stay aligned on cross-cutting rules:

- safety
- security
- observability
- AI draft behavior
- human confirmation rules
- chat responsiveness
- modularity

If a new cross-cutting rule is added here, mirror it in `backend/agent.md`.

If there is a conflict between frontend and backend rules, STOP and ASK.
