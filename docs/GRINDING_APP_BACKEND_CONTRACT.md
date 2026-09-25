# Frontend Handoff — Grinding App («الجاروشة») — Backend Contract

> Self-contained contract for the team or agent building the new Grinding App. You do not need
> access to the backend repository: everything the app sends and receives is written down here.
> Backend feature: **Unified Grinding Lifecycle** (Flyway V198–V205).

## 1. Executive Summary

The factory now tracks physical grinding. Every roll or pallet destined for the grinder has one
**grinding order** (`GR-000123`), and its lifecycle is:

```
recommendation (needs manager approval) ─┐
                                         ├─► READY_FOR_GRINDING ─► IN_GRINDING ─► COMPLETED
direct SCRAP roll (no approval) ─────────┘
```

The Grinding App is the only place a person can say **«بدأ الجرش»** (start) and **«تم الجرش فعليًا»**
(complete). A `COMPLETED` order therefore means exactly one thing: an authenticated grinding worker
confirmed that the material was physically ground. The app never approves, rejects or cancels an
order; those belong to the plant manager (web portal) and to the system.

This is a new app, so nothing existing breaks. It must ship together with the backend release that
contains V198–V205.

## 2. Affected App

**Grinding App (new, «الجاروشة»)** — a shop-floor device app used by the grinding worker
(«موظف الجرش», role `GRINDING_WORKER`).

Not this document's concern: the six existing apps, which have their own handoffs
(`FRONTEND_HANDOFF_*_UNIFIED_GRINDING.md`, `PALLETIZING_GRINDING_RECOMMENDATION_HANDOFF.md`).

## 3. Business Context

- A grinding worker walks to the grinder with a roll or a pallet, **scans its 12-digit number**, sees
  whether it may be ground, taps **«بدء الجرش»**, grinds it, and taps **«تأكيد انتهاء الجرش»**.
- Who can be a grinding worker: an employee the admin created with the employee type «موظف الجرش»,
  who has a 4-digit PIN. They log in with the PIN only (no email / password).
- What the worker can grind:
  - **Direct SCRAP rolls** (rolls produced as scrap by roll production) — ready at once;
  - **Thermoforming roll remainders** and **pallets** — only after the plant manager approved the
    recommendation. Until then the scan says «بانتظار موافقة المدير».
- A different worker may complete an order another worker started (shift change).
- Rolls and pallets share the 12-digit number space: very rarely one number is both a roll and a pallet.
  The backend then looks at which of the two the worker can actually act on. If only one can be ground (or
  confirmed), it answers with that one directly; the app asks «رول أم طبلية؟» only when **both** can.

## 4. Backend Contract Changes

### 4.1 Transport, auth and envelope

- Base path: **`/api/v1/grinding-app`**
- Every request carries the device key header **`X-Device-Key: <device key>`** (the same shared factory
  device key the other shop-floor apps use; configured per installation, never hardcoded in source).
- Every request except `POST /auth/pin` also carries **`X-Session-Token: <token>`** from the PIN login.
- `Content-Type: application/json`.
- Envelope (all endpoints):

```jsonc
// success
{ "success": true, "data": { ... } }
// failure
{ "success": false, "error": { "code": "GRINDING_ORDER_NOT_READY", "message": "…", "details": { ... } } }
```
  Null fields are omitted. Show your own Arabic text per `error.code` (section 10); `error.message` is
  English and technical — never show it to the worker.
- All timestamps are **ISO-8601 UTC instants** (`2026-09-22T09:41:07.312Z`). Convert to
  **Asia/Hebron** for display — never through the device's own timezone.
- A missing or wrong `X-Device-Key` → HTTP 401/403 before any business logic (no envelope guarantee —
  treat any 401/403 without a `GRINDING_*` code as "device not authorized: contact admin").

### 4.2 Endpoints

| # | Method | Path | Session? | Purpose |
|---|---|---|---|---|
| 1 | POST | `/auth/pin` | no | PIN login, returns the session token **once** |
| 2 | GET | `/sessions/me` | yes | Current session / worker (use on app resume) |
| 3 | POST | `/auth/logout` | yes (tolerant) | End the session; idempotent |
| 4 | POST | `/check` | yes | Resolve a scanned number (read-only) |
| 5 | GET | `/orders?status=READY_FOR_GRINDING` or `IN_GRINDING` | yes | Queue, oldest first, max 100 |
| 6 | POST | `/orders/{orderId}/start` | yes | Start grinding (idempotent) |
| 7 | POST | `/orders/{orderId}/complete` | yes | Confirm physical grinding (idempotent) |

#### 1) `POST /auth/pin`

```json
{ "pin": "4821" }
```
`pin`: exactly 4 digits. Response 200:
```json
{
  "success": true,
  "data": {
    "sessionToken": "5b0f6c9e-6a1d-4b1b-9d8e-2a6c2f1b7e41",
    "expiresAt": "2026-09-22T21:41:07.312Z",
    "worker": { "operatorId": 57, "name": "محمد أحمد" }
  }
}
```
- The token is shown once. Store it in secure storage; never log it; never put it in a URL.
- A new login for the same worker ends their previous session (another device is logged out).
- Session lifetime: 12 hours (`expiresAt`). No refresh endpoint — log in again.
- Errors: `OPERATOR_PIN_INVALID` 401 (wrong PIN), `GRINDING_WORKER_NOT_ALLOWED` 403 (valid PIN but the
  employee is not a grinding worker, or inactive), `OPERATOR_BACKING_USER_INVALID` 409 (account
  misconfigured — contact admin), `VALIDATION_ERROR` 400 (not 4 digits).

#### 2) `GET /sessions/me`

```json
{
  "success": true,
  "data": {
    "sessionId": 311,
    "createdAt": "2026-09-22T09:41:07.312Z",
    "expiresAt": "2026-09-22T21:41:07.312Z",
    "worker": { "operatorId": 57, "name": "محمد أحمد" }
  }
}
```

#### 3) `POST /auth/logout` (no body)

```json
{ "success": true, "data": { "ended": true } }
```
`ended: false` means the token was already unusable (expired, replaced, unknown) — still treat as
logged out. Logout never changes any order: an order the worker left `IN_GRINDING` stays
`IN_GRINDING`, and any grinding worker can complete it later.

#### 4) `POST /check`

```json
{ "identifier": "001000000255" }
```
or, after an ambiguity answer (see below):
```json
{ "identifier": "001000000255", "sourceType": "ROLL" }
```
- `identifier` is trimmed server-side and must be **exactly 12 digits**, else 400
  `GRINDING_IDENTIFIER_INVALID`. Validate client-side too.
- `sourceType`: optional, `ROLL` or `PALLET`. Send it only when the previous answer was
  `GRINDING_IDENTIFIER_AMBIGUOUS` (the worker's choice), or when re-checking an item whose type is already
  known (a pending command, a candidate the worker tapped).

**How a number is resolved.** Each item the number names (a roll, a pallet, or both) is a *candidate*. A
candidate is **actionable** when its order is `READY_FOR_GRINDING` (the worker can start) or `IN_GRINDING`
(the worker can confirm — any worker may). `PENDING_APPROVAL` and `COMPLETED` are shown but never acted on;
a rejected or cancelled order holds nothing, so that item reads as having no order.

| The number names… | Answer | `resolution` |
|---|---|---|
| one item | its order, or `NOT_ELIGIBLE` | `SINGLE_MATCH` |
| (`sourceType` sent) | that type's order / `NOT_ELIGIBLE` / 404 | `SOURCE_TYPE_SELECTED` |
| both, **both actionable** | **409 `GRINDING_IDENTIFIER_AMBIGUOUS`** — ask the worker | `REQUIRES_SELECTION` (in `error.details`) |
| both, exactly one actionable | 200 with that one — no question | `AUTO_RESOLVED` |
| both, neither actionable, exactly one has an order (pending / completed) | 200 with that order (no action) | `AUTO_RESOLVED` |
| both, neither actionable otherwise | 200 `NOT_ELIGIBLE`, `sourceType` and `order` absent | `NONE_ACTIONABLE` |
| nothing | 404 `GRINDING_SOURCE_NOT_FOUND` | — |

Whenever the number names both items (`AUTO_RESOLVED`, `NONE_ACTIONABLE`), the response also carries
`candidates` — both items — so the app can say which other item the number names:

```json
"candidates": [
  { "sourceType": "ROLL", "label": "رول", "status": "READY_FOR_GRINDING", "statusLabel": "جاهز للجرش",
    "allowedToStartGrinding": true, "allowedToCompleteGrinding": false,
    "orderNumber": "GR-001042", "materialName": "رول أبيض 0.8" },
  { "sourceType": "PALLET", "label": "طبلية", "status": "NOT_ELIGIBLE", "statusLabel": "غير مؤهل للجرش",
    "allowedToStartGrinding": false, "allowedToCompleteGrinding": false, "materialName": "كاسة 250" }
]
```
`orderNumber` / `materialName` are omitted when unknown. The two flags keep «بدء» and «تأكيد الانتهاء»
apart: a roll `IN_GRINDING` next to a pallet `READY_FOR_GRINDING` is two different actions.

Response 200 when an order exists:
```json
{
  "success": true,
  "data": {
    "identifier": "001000000255",
    "sourceType": "ROLL",
    "status": "READY_FOR_GRINDING",
    "statusLabel": "جاهز للجرش",
    "message": "جاهز للجرش — يمكنك بدء الجرش.",
    "allowedToStartGrinding": true,
    "allowedToCompleteGrinding": false,
    "order": {
      "id": 1042,
      "orderNumber": "GR-001042",
      "status": "READY_FOR_GRINDING",
      "statusLabel": "جاهز للجرش",
      "sourceType": "ROLL",
      "sourceOrigin": "ROLL_PRODUCTION_SCRAP",
      "sourceIdentifier": "001000000255",
      "materialName": "رول أبيض 0.8",
      "expectedWeightKg": 40.000,
      "lineName": null,
      "directScrap": true,
      "legacy": false,
      "createdAt": "2026-09-22T08:12:44.019Z",
      "version": 0
    },
    "resolution": "SINGLE_MATCH"
  }
}
```
`status` values and what the app shows:

| `status` | Meaning | Primary action |
|---|---|---|
| `READY_FOR_GRINDING` | may be ground now | **«بدء الجرش»** (`allowedToStartGrinding=true`) |
| `IN_GRINDING` | a worker started it | **«تأكيد انتهاء الجرش»** (`allowedToCompleteGrinding=true`); show `startedByName` / `startedAt` |
| `PENDING_APPROVAL` | recommendation waiting for the manager | none — «بانتظار موافقة المدير — لا يمكن بدء الجرش بعد.» |
| `COMPLETED` | already ground | none — show `message`; `legacy=true` → «تم الجرش قبل تفعيل نظام تتبع الجرش الجديد» |
| `NOT_ELIGIBLE` | roll / pallet exists but has **no** grinding order — or, with `resolution=NONE_ACTIONABLE`, the number names both and neither can be acted on | none — «غير مؤهل للجرش»; `order` absent; minimal `details` (single item) or `candidates` (both) |

`NOT_ELIGIBLE` example:
```json
{
  "success": true,
  "data": {
    "identifier": "120000004411",
    "sourceType": "PALLET",
    "status": "NOT_ELIGIBLE",
    "statusLabel": "غير مؤهل للجرش",
    "message": "لا يوجد أمر جرش لهذه الطبلية.",
    "allowedToStartGrinding": false,
    "allowedToCompleteGrinding": false,
    "details": { "scannedValue": "120000004411", "productName": "كاسة 250", "quantity": 1200 },
    "resolution": "SINGLE_MATCH"
  }
}
```
Roll `details`: `generatedRollId`, `rollType`, `productionKind`.

`NONE_ACTIONABLE` example (the number names a pallet already ground and a roll without an order):
```json
{
  "success": true,
  "data": {
    "identifier": "001000000255",
    "status": "NOT_ELIGIBLE",
    "statusLabel": "غير مؤهل للجرش",
    "message": "الرقم موجود لرول وطبلية، ولا يمكن جرش أيٍّ منهما الآن.",
    "allowedToStartGrinding": false,
    "allowedToCompleteGrinding": false,
    "resolution": "NONE_ACTIONABLE",
    "candidates": [ { "sourceType": "ROLL", "label": "رول", "status": "NOT_ELIGIBLE", … },
                    { "sourceType": "PALLET", "label": "طبلية", "status": "COMPLETED", … } ]
  }
}
```
(`message` reads «…ولا يوجد أمر جرش لأيٍّ منهما.» when neither item has an order.)

Errors: `GRINDING_IDENTIFIER_INVALID` 400; `GRINDING_SOURCE_NOT_FOUND` 404 (no roll and no pallet has
this number); **`GRINDING_IDENTIFIER_AMBIGUOUS` 409** — only when the number belongs to BOTH a roll and a
pallet, `sourceType` was not sent, and the worker **can act on both** (each is `READY_FOR_GRINDING` or
`IN_GRINDING`). The backend never guesses between two grindable items:
```json
{
  "success": false,
  "error": {
    "code": "GRINDING_IDENTIFIER_AMBIGUOUS",
    "message": "The number 001000000255 names both a roll and a pallet that can be acted on; resend with sourceType.",
    "details": {
      "identifier": "001000000255",
      "resolution": "REQUIRES_SELECTION",
      "candidates": [
        { "sourceType": "ROLL", "label": "رول", "status": "IN_GRINDING", "statusLabel": "قيد الجرش",
          "allowedToStartGrinding": false, "allowedToCompleteGrinding": true, "orderNumber": "GR-001042",
          "materialName": "رول أبيض 0.8" },
        { "sourceType": "PALLET", "label": "طبلية", "status": "READY_FOR_GRINDING", "statusLabel": "جاهز للجرش",
          "allowedToStartGrinding": true, "allowedToCompleteGrinding": false, "orderNumber": "GR-001050",
          "materialName": "كاسة 250" }
      ],
      "message": "الرقم موجود لرول وطبلية، أي واحدة تريد جرشها؟"
    }
  }
}
```
→ show the two items as big buttons («رول» / «طبلية», each with its status and material), then resend
`/check` with the chosen `sourceType` and continue with that answer. `sourceType` and `label` were the only
candidate keys before the smart resolution; the others are additive.

`/check` never changes anything; call it as often as you like.

#### 5) `GET /orders?status=READY_FOR_GRINDING` | `IN_GRINDING`

```json
{ "success": true, "data": { "orders": [ { …order view as above… } ], "limit": 100 } }
```
Oldest first. Any other `status` → 400 `VALIDATION_ERROR`. Use it for a "ready for grinding" list and
an "in grinding" list; tapping a row goes to the same order card as a scan.

#### 6) `POST /orders/{orderId}/start` and 7) `POST /orders/{orderId}/complete`

```json
{ "clientRequestId": "c1f0f1b8-9a57-4a0e-9a0e-5d2f7d7d9b10" }
```
Response 200:
```json
{
  "success": true,
  "data": {
    "order": { …order view, status IN_GRINDING / COMPLETED, startedByName, startedAt, completedByName, completedAt… },
    "replayed": false,
    "message": "بدأ الجرش."
  }
}
```
`complete` returns `"message": "تم الجرش فعليًا"`. `replayed: true` means this exact request had already
succeeded (a retry) — treat it as success and show the same result.

- `start` requires `READY_FOR_GRINDING`; `complete` requires `IN_GRINDING`. Any grinding worker may
  complete, not only the one who started.
- Errors: `GRINDING_APPROVAL_REQUIRED` 409 (still waiting for the manager), `GRINDING_ORDER_NOT_READY` 409
  (start on a non-ready order, e.g. cancelled or already started), `GRINDING_ORDER_NOT_IN_PROGRESS` 409
  (complete before start), `GRINDING_ORDER_ALREADY_COMPLETED` 409, `GRINDING_SOURCE_STATE_CHANGED` 409
  (the roll/pallet changed underneath, e.g. a SCRAP roll's kind was corrected), `GRINDING_ORDER_NOT_FOUND`
  404, `GRINDING_IDEMPOTENCY_KEY_REUSED` 409 (the same `clientRequestId` was used for a different order or
  the other command), `VALIDATION_ERROR` 400 (missing / >64-char `clientRequestId`), plus the session
  errors below.

### 4.3 Session errors (any endpoint with a session)

| Code | HTTP | Meaning | App behaviour |
|---|---:|---|---|
| `GRINDING_WORKER_SESSION_REQUIRED` | 401 | no `X-Session-Token` | go to PIN screen |
| `GRINDING_WORKER_SESSION_INVALID` | 401 | token unknown / ended / replaced by another login | clear token → PIN screen |
| `GRINDING_WORKER_SESSION_EXPIRED` | 401 | 12 h passed | clear token → PIN screen |
| `GRINDING_WORKER_NOT_ALLOWED` | 403 | the admin removed the worker's grinding access or deactivated them; the session was ended | clear token → PIN screen with the message |

### 4.4 Idempotency (`clientRequestId`)

- Generate a **new UUID v4 when the worker taps** «بدء الجرش» / «تأكيد انتهاء الجرش» — one ID per user
  action, per order, per command.
- **Persist it before sending** (keyed by `orderId + command`) and reuse it for every retry of that same
  action: timeouts, lost connection, app killed and restarted.
- Clear it only after a 2xx response (including `replayed: true`) or a definitive 4xx business error.
- Never reuse an ID for a different order or for the other command (→ `GRINDING_IDEMPOTENCY_KEY_REUSED`).
- Disable the button while a request is in flight (double-tap guard); a second tap must not mint a
  second ID.

### 4.5 Refresh

No SSE for this app. Re-run `/check` for the order on screen after every action and when the app
resumes; pull the queue on screen open and with pull-to-refresh.

## 5. Required Frontend Screens / Dialogs

1. **PIN login** — title «تسجيل الدخول — الجاروشة», 4-digit PIN pad, button «دخول». Loading on the button.
   Errors inline under the pad (section 10).
2. **Home / scan** — header with worker name and «تسجيل الخروج»; a very large «مسح رقم» button (camera or
   hardware scanner) and a manual 12-digit entry field with «تحقق». Two tabs/lists: «جاهز للجرش» and
   «قيد الجرش».
3. **Selection sheet** (only on 409 `GRINDING_IDENTIFIER_AMBIGUOUS`, i.e. both items are actionable) —
   title «الرقم موجود لرول وطبلية», text «اختر المادة التي تريد جرشها», one large button per candidate
   («رول» / «طبلية», each showing its `statusLabel` and `materialName`), and «إلغاء». Never shown when only
   one item is actionable. When an answer is `AUTO_RESOLVED`, the order card names the other item the number
   also belongs to (e.g. «الرقم نفسه موجود أيضاً لطبلية — غير مؤهل للجرش»), so a worker holding that other
   item notices before starting; the start / complete confirmations name the item type.
4. **Order card** (after a scan or a tap on a list row) — order number, big status chip (`statusLabel`),
   source («رول» / «طبلية»), number, material, expected weight (kg, rolls) or quantity (pallets), line,
   «جرش مباشر» tag when `directScrap`, started by / at when `IN_GRINDING`. One primary button:
   - `READY_FOR_GRINDING` → «بدء الجرش» → confirm dialog «بدء جرش <GR-…>؟» («بدء» / «إلغاء»);
   - `IN_GRINDING` → «تأكيد انتهاء الجرش» → confirm dialog «هل تم جرش هذه المادة فعليًا؟» («نعم، تم
     الجرش» / «إلغاء»);
   - any other status → no button, just the `message`.
5. **Success** — full-width green banner: start «بدأ الجرش.», complete «تم الجرش فعليًا». Then refresh.

## 6. Required Models / DTO Changes

New models (all new):
- `PinLoginRequest { pin }`, `PinLoginResponse { sessionToken, expiresAt, worker }`,
  `Worker { operatorId, name }`, `SessionView { sessionId, createdAt, expiresAt, worker }`,
  `LogoutResponse { ended }`.
- `CheckRequest { identifier, sourceType? }`,
  `CheckResponse { identifier, sourceType?, status, statusLabel, message, allowedToStartGrinding,
  allowedToCompleteGrinding, order?, details?, resolution, candidates? }` — `status` is a **string** (order
  status or `NOT_ELIGIBLE`); `details` is a free map; `sourceType` is absent only for `NONE_ACTIONABLE`.
- `CheckCandidate { sourceType, label, status, statusLabel, allowedToStartGrinding,
  allowedToCompleteGrinding, orderNumber?, materialName? }` — in `CheckResponse.candidates` and in the 409's
  `error.details.candidates`.
- `CheckResolution { SINGLE_MATCH, SOURCE_TYPE_SELECTED, AUTO_RESOLVED, NONE_ACTIONABLE,
  REQUIRES_SELECTION }` — parse leniently.
- `GrindingOrderView { id, orderNumber, status, statusLabel, sourceType, sourceOrigin, sourceIdentifier,
  materialName?, expectedWeightKg?, sourceQuantity?, lineName?, directScrap, legacy, startedByName?,
  startedAt?, completedByName?, completedAt?, createdAt, version }`.
- `ExecutionRequest { clientRequestId }`, `ExecutionResponse { order, replayed, message }`,
  `QueueResponse { orders, limit }`.
- Enums: `GrindingOrderStatus { PENDING_APPROVAL, READY_FOR_GRINDING, REJECTED, IN_GRINDING, COMPLETED,
  CANCELLED }`, `GrindingSourceType { ROLL, PALLET }`, `GrindingSourceOrigin { ROLL_PRODUCTION_SCRAP,
  THERMOFORMING_ROLL_REMAINDER, PALLETIZING_PALLET }`. Parse unknown values leniently (future-proof).
- `expectedWeightKg` is a decimal (3 places): parse as decimal/string, display as-is, never round.

## 7. Required Repository / API Client Changes

`GrindingAppApi`: `loginWithPin(pin)`, `getSession()`, `logout()`, `check(identifier, sourceType?)`,
`getQueue(status)`, `startGrinding(orderId, clientRequestId)`, `completeGrinding(orderId,
clientRequestId)`. One interceptor adds `X-Device-Key` to all calls and `X-Session-Token` to all but
login; on any session error (4.3) it clears the token and routes to login. Map `error.code` → Arabic
(section 10); unknown codes → «تعذر تنفيذ العملية. حاول مرة أخرى.». Network errors on start/complete →
retry with the SAME `clientRequestId`.

## 8. Required Provider / State Management Changes

- `SessionState { token?, worker?, expiresAt? }` — restored from secure storage on launch, then
  verified with `GET /sessions/me`.
- `ScanState { identifier, loading, result?, ambiguity?, error? }`.
- `OrderActionState { orderId, command, clientRequestId, inFlight, error? }` — persisted pending actions
  so a restart resumes the retry.
- `QueueState { ready[], inGrinding[], loading }` refreshed on screen open, after every successful action,
  on app resume, and on pull-to-refresh.

## 9. Required UX Flow

**Happy path (direct SCRAP):** PIN → scan `001000000255` → card «جاهز للجرش» → «بدء الجرش» → confirm → banner
«بدأ الجرش.» → card now «قيد الجرش» → grind → «تأكيد انتهاء الجرش» → confirm → «تم الجرش فعليًا» → card
«تم الجرش», no button.

**Recommendation not yet approved:** scan → «بانتظار موافقة المدير — لا يمكن بدء الجرش بعد.», no button.

**Validation failure:** manual entry of 11 digits → inline «يجب أن يتكون الرقم من 12 خانة بالضبط.» before any call.

**Network failure on start/complete:** keep the button disabled with a spinner, retry automatically up to
3 times with the same ID, then show «انقطع الاتصال — أعد المحاولة» with a retry button that reuses the ID.
If the retry returns `replayed: true` → success.

**Backend business error:** show the Arabic message (section 10) in a dialog, then re-`/check` to show the
current truth (e.g. another worker already started it).

**Cancel/back:** cancelling a confirm dialog sends nothing and mints no ID.

## 10. Arabic UI Text

| Key / situation | Arabic |
|---|---|
| App title | الجاروشة |
| PIN screen title | تسجيل الدخول — الجاروشة |
| Login button | دخول |
| Logout | تسجيل الخروج |
| Scan button | مسح رقم |
| Manual entry label | رقم الرول أو الطبلية (12 خانة) |
| Check button | تحقق |
| Lists | جاهز للجرش · قيد الجرش |
| Start button | بدء الجرش |
| Complete button | تأكيد انتهاء الجرش |
| Start confirm | بدء جرش {رقم الأمر}؟ — بدء / إلغاء |
| Complete confirm | هل تم جرش هذه المادة فعليًا؟ — نعم، تم الجرش / إلغاء |
| Start success | بدأ الجرش. |
| Complete success | تم الجرش فعليًا |
| Direct tag | جرش مباشر |
| Source labels | رول · طبلية |
| Selection title/text | الرقم موجود لرول وطبلية · اختر المادة التي تريد جرشها |
| Empty list | لا توجد أوامر |
| `OPERATOR_PIN_INVALID` | الرمز السري غير صحيح. |
| `GRINDING_WORKER_NOT_ALLOWED` | هذا الموظف غير مخوّل باستخدام تطبيق الجاروشة. |
| `GRINDING_WORKER_SESSION_REQUIRED` | يلزم تسجيل الدخول في تطبيق الجاروشة. |
| `GRINDING_WORKER_SESSION_INVALID` | جلسة تطبيق الجاروشة غير صالحة. سجّل الدخول مجدداً. |
| `GRINDING_WORKER_SESSION_EXPIRED` | انتهت جلسة تطبيق الجاروشة. سجّل الدخول مجدداً. |
| `GRINDING_IDENTIFIER_INVALID` | يجب أن يتكون الرقم من 12 خانة بالضبط. |
| `GRINDING_SOURCE_NOT_FOUND` | لا يوجد رول أو طبلية بهذا الرقم. |
| `GRINDING_IDENTIFIER_AMBIGUOUS` | الرقم موجود لرول وطبلية، أي واحدة تريد جرشها؟ |
| `GRINDING_APPROVAL_REQUIRED` | أمر الجرش ما زال بانتظار موافقة المدير. |
| `GRINDING_ORDER_NOT_READY` | أمر الجرش غير جاهز للجرش. |
| `GRINDING_ORDER_NOT_IN_PROGRESS` | لم يبدأ جرش هذا الأمر بعد. |
| `GRINDING_ORDER_ALREADY_COMPLETED` | تم جرش هذا الأمر مسبقاً. |
| `GRINDING_SOURCE_STATE_CHANGED` | تغيّرت حالة الرول أو الطبلية ولم يُنفَّذ الإجراء. |
| `GRINDING_ORDER_NOT_FOUND` | أمر الجرش غير موجود. |
| `GRINDING_IDEMPOTENCY_KEY_REUSED` | تم استخدام مفتاح الطلب هذا لإجراء مختلف. |
| Unknown error | تعذر تنفيذ العملية. حاول مرة أخرى. |
| Network lost | انقطع الاتصال — أعد المحاولة |

## 11. Edge Cases

- **Double tap:** button disabled while in flight; one `clientRequestId` per action.
- **Lost network after backend success:** retry with the same ID → `replayed: true` → success.
- **Another worker started it first:** `start` → `GRINDING_ORDER_NOT_READY`; re-check shows «قيد الجرش»
  and offers «تأكيد انتهاء الجرش» (any worker may complete).
- **Manager has not approved yet:** `PENDING_APPROVAL`, no button.
- **SCRAP roll corrected to normal before start:** `/check` shows `NOT_ELIGIBLE` (the order was cancelled);
  a stale `start` → `GRINDING_ORDER_NOT_READY` or `GRINDING_SOURCE_STATE_CHANGED`.
- **Session replaced** (same worker logged in elsewhere) or **access withdrawn** mid-shift → session error →
  PIN screen; any pending action is kept and retried after re-login with the same ID.
- **Legacy orders:** `COMPLETED` + `legacy: true` → show «تم الجرش قبل تفعيل نظام تتبع الجرش الجديد»; never
  show a worker name for them (there is none).
- **App resumed:** `GET /sessions/me`, then re-check the order on screen and refresh lists.
- **Empty lists:** «لا توجد أوامر».
- **Shared number, one actionable:** e.g. roll `READY_FOR_GRINDING` + pallet without an order → the roll opens
  directly (`AUTO_RESOLVED`); the card says the number also names a pallet. Roll `IN_GRINDING` + pallet
  `READY_FOR_GRINDING` → both actionable (different actions) → selection sheet showing «قيد الجرش» and
  «جاهز للجرش».

## 12. Testing Requirements

- Unit: PIN validation; 12-digit validation; status → action mapping (all 5 `status` values);
  `clientRequestId` lifecycle (create on tap, reuse on retry, clear on 2xx/4xx, survive restart); error
  code → Arabic map; decimal weight display without rounding; UTC → Asia/Hebron display.
- Widget: PIN pad; order card for each status; confirm dialogs; selection sheet (both actionable) vs. no sheet (one actionable); disabled button while
  in flight.
- Provider: session restore / expiry; pending-action resume after restart.
- API: header injection (device key on all, session on all but login); envelope parsing; session-error
  interceptor.
- Manual smoke (**only on a test environment** — see compatibility notes): PIN → check → start → complete
  → retry the same complete (expect `replayed: true`); a number shared by a roll and a pallet (one actionable → opens directly; both → selection); pending-approval
  number; logout.
- Regression: none (new app).

## 13. Backend Compatibility Notes

- Requires the backend release containing Flyway **V198–V205** (Unified Grinding Lifecycle). Earlier
  backends return 404 for `/api/v1/grinding-app/**`.
- New app: no old version to stay compatible with. Additive for every other app.
- No feature flag. The device key is the existing shared factory device key.
- **Production smoke policy:** after the cutover, production checks are read-only — PIN login,
  `/sessions/me`, `/check` on a known legacy number, `/orders`, logout. **Never create a start/complete in
  production as a test**: `COMPLETED` must always mean material was physically ground. The full
  PIN → check → start → complete flow is verified on a disposable test copy of the database.

## 14. Final Acceptance Criteria

- A grinding worker logs in with a 4-digit PIN; a non-grinding employee sees «هذا الموظف غير مخوّل…».
- Scanning a READY order shows «بدء الجرش»; starting and then completing reaches «تم الجرش فعليًا».
- A PENDING order can never be started from the app; a COMPLETED order shows no action.
- Retrying a start/complete after a network cut never creates a second action (`replayed: true` handled).
- A number that names a roll and a pallet prompts for «رول» / «طبلية» only when both can be acted on;
  otherwise it opens the one that can (or shows why neither can) without a question.
- Session expiry, replacement and access withdrawal all return the worker to the PIN screen.
- All text is Arabic, RTL, large-target, readable at arm's length.
