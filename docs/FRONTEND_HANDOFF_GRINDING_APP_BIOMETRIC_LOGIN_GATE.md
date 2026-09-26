# Frontend Handoff — Grinding App (الجاروشة) — Biometric Login Gate

## 1. Executive Summary

Taleeb is adding a fingerprint check **before a new login** in the Grinding App (الجاروشة). The login request itself does not
change. When the employee has no recent successful punch on a factory fingerprint terminal, the backend now answers
the login with a **403** carrying a `BIOMETRIC_*` code and a short-lived *attempt token*. The app then shows a
fingerprint dialog and long-polls a status endpoint. Once the employee has scanned, the status says so and the app
**re-submits the original login once**.

- Existing sessions and tokens are **never** ended by this feature.
- The backend ships with the feature **switched off**. Nothing changes for any user until a SYSTEM_ADMIN turns it
  on. The app update must ship before that.
- An old app build stays usable: every refusal carries an Arabic message telling the employee to scan and try
  again.

Role gated in this app: **GRINDING_WORKER**. Backend context name: `GRINDING_APP`.

## 2. App Impact Matrix

| App | Affected? | Reason | Handoff file |
|---|---|---|---|
| Warehouse App | **Yes** | New fingerprint dialog on the WAREHOUSE_APP login | `FRONTEND_HANDOFF_WAREHOUSE_APP_BIOMETRIC_LOGIN_GATE.md` |
| Operator App (Thermoforming) | **Yes** | New fingerprint dialog on the THERMOFORMING_APP login | `FRONTEND_HANDOFF_OPERATOR_APP_BIOMETRIC_LOGIN_GATE.md` |
| Roll Production App | **Yes** | New fingerprint dialog on the ROLL_PRODUCTION_APP login | `FRONTEND_HANDOFF_ROLL_PRODUCTION_APP_BIOMETRIC_LOGIN_GATE.md` |
| Palletizing App | **Yes** | New fingerprint dialog on the PALLETIZING_APP login | `FRONTEND_HANDOFF_PALLETIZING_APP_BIOMETRIC_LOGIN_GATE.md` |
| Roll Worker App | **Yes** | New fingerprint dialog on the ROLL_WORKER_APP login | `FRONTEND_HANDOFF_ROLL_WORKER_APP_BIOMETRIC_LOGIN_GATE.md` |
| Grinding App (الجاروشة) **(this document)** | **Yes** | New fingerprint dialog on the GRINDING_APP login | `FRONTEND_HANDOFF_GRINDING_APP_BIOMETRIC_LOGIN_GATE.md` |
| Admin App | No | Admin App login is never gated. Its tokens simply carry no warehouse authority while enforcement is on | — |
| Maintenance App | No | Maintenance login is never gated | — |

## 3. Business Context

- The factory has ZKTeco fingerprint terminals connected through an on-site agent. Each punch reaches the backend
  within seconds.
- A SYSTEM_ADMIN links every employee to their id on a terminal. From then on, a **new** login in the targeted
  apps is accepted only if that employee punched within the validity window. The default window is 5 minutes and
  the SYSTEM_ADMIN can change it.
- Any successful punch counts. The login never "uses up" the punch: several logins inside the window are fine.
- If the factory agent goes offline, the backend temporarily suspends the check factory-wide. Logins then work with
  the PIN or password alone, and the check resumes automatically once the agent is stable again.
- The dialog must never offer a way around the check. There is no "skip", no "use PIN only", and no hidden gesture.

## 4. Backend Contract

### 4.1 Login endpoint(s) — request unchanged, new refusals

| Endpoint | Body (unchanged) | Success |
|---|---|---|
| `POST /api/v1/grinding-app/auth/pin` | `{ "pin": "1234" }` | 200 (unchanged) |

Headers: `X-Device-Key` exactly as today. The status endpoint below does **not** need it.

The gate runs after the PIN and the grinding-worker permission are verified and before the grinding session is created. This call site ships together with the Unified Grinding release.

No grinding session is created for a refused login.

### 4.2 The biometric refusal (HTTP 403)

Standard `ApiResponse` envelope. Absolute times are **UTC ISO-8601** (`…Z`). Convert them to `Asia/Hebron` for
display, never to the device timezone.

**Recoverable — fingerprint needed (token present):**

```json
{
  "success": false,
  "error": {
    "code": "BIOMETRIC_VERIFICATION_REQUIRED",
    "message": "يرجى تمرير البصمة على جهاز البصمة ثم إعادة المحاولة.",
    "details": {
      "validitySeconds": 300,
      "attemptToken": "q3Jx8d6cYt0H1m0yF3kZ0wS9gQx8B7nV2rP5aL4eK1c",
      "attemptExpiresAt": "2026-09-24T08:15:00.000Z",
      "statusPath": "/api/v1/auth/biometric/login-attempts/status",
      "attemptAvailable": true
    }
  }
}
```

`BIOMETRIC_VERIFICATION_EXPIRED` (the last fingerprint is too old) and `BIOMETRIC_DEVICE_UNAVAILABLE` (the
terminal is offline while the agent is up) have exactly the same `details`. Only `code` and `message` differ.

**Recoverable, but no attempt could be recorded (token absent):**

```json
{
  "success": false,
  "error": {
    "code": "BIOMETRIC_VERIFICATION_REQUIRED",
    "message": "يرجى تمرير البصمة على جهاز البصمة ثم إعادة المحاولة.",
    "details": { "validitySeconds": 300, "attemptAvailable": false }
  }
}
```

Show the dialog without polling: "scan, then tap **إعادة المحاولة**". Retry re-submits the login, which yields a
fresh attempt.

**Not recoverable by the employee — the SYSTEM_ADMIN must act (token never present):**

```json
{
  "success": false,
  "error": {
    "code": "BIOMETRIC_MAPPING_MISSING",
    "message": "لم يتم ربط بصمتك بحسابك بعد. يرجى مراجعة مسؤول النظام.",
    "details": { "validitySeconds": 300, "attemptAvailable": false }
  }
}
```

`BIOMETRIC_MAPPING_DISABLED` has the same shape (message «ربط البصمة الخاص بحسابك غير مفعّل. يرجى مراجعة مسؤول
النظام.»). Do not poll and do not retry automatically.

### 4.3 Attempt status — `GET /api/v1/auth/biometric/login-attempts/status`

- **Auth:** none. Do not send `Authorization` or a device key. Send the header
  `X-Biometric-Attempt-Token: <attemptToken>`.
- **Path:** use `details.statusPath` against the same base URL as the login.
- **Long-poll:** the server holds the request for up to **25 s** and answers as soon as something changes.
  Configure the HTTP receive timeout to at least **35 s**.

**200 OK** (`data` never empty):

```json
{ "success": true, "data": { "status": "PENDING", "attemptExpiresAt": "2026-09-24T08:15:00.000Z" } }
```

| `data.status` | Meaning | App action |
|---|---|---|
| `PENDING` | no valid fingerprint yet | keep waiting: poll again immediately |
| `DEVICE_UNAVAILABLE` | the terminal reports offline; the agent is up | show the device-offline state, keep polling |
| `VERIFIED` | a valid fingerprint arrived | **re-submit the original login once** |
| `ENFORCEMENT_SUSPENDED` | the agent is offline, so the check is suspended | **re-submit the original login once** |
| `NOT_REQUIRED` | an admin exempted the employee or switched the check off | **re-submit the original login once** |
| `MAPPING_MISSING` / `MAPPING_DISABLED` | the admin removed or disabled the link meanwhile | stop polling and show the admin-contact state |

**410 Gone** — unknown or expired attempt (the two are indistinguishable by design):

```json
{
  "success": false,
  "error": {
    "code": "BIOMETRIC_LOGIN_ATTEMPT_EXPIRED",
    "message": "انتهت مهلة محاولة الدخول. يرجى تسجيل الدخول مرة أخرى."
  }
}
```

Stop polling and show «إعادة المحاولة», which re-submits the login.

The status answer **never logs anyone in**. Only the re-submitted login does, and the backend checks it from
scratch. It can therefore still refuse, for example when the fingerprint expired in between. In that case the new
403 starts a new attempt.

### 4.4 Error codes

| `error.code` | HTTP | Where | Token? | Meaning |
|---|---|---|---|---|
| `BIOMETRIC_VERIFICATION_REQUIRED` | 403 | login | yes* | no valid fingerprint |
| `BIOMETRIC_VERIFICATION_EXPIRED` | 403 | login | yes* | the last fingerprint is older than the validity window |
| `BIOMETRIC_DEVICE_UNAVAILABLE` | 403 | login | yes* | the terminal is offline |
| `BIOMETRIC_MAPPING_MISSING` | 403 | login | no | no terminal id linked to the account |
| `BIOMETRIC_MAPPING_DISABLED` | 403 | login | no | the link was disabled |
| `BIOMETRIC_LOGIN_ATTEMPT_EXPIRED` | 410 | status | — | unknown or expired attempt |

\* `attemptAvailable=false` → no token (see 4.2).

Branch on `error.code` only. Never branch on the HTTP status alone: other 403s (for example missing app access)
must keep their current handling.

## 5. Required Screens / Dialogs

One modal **fingerprint dialog**, opened from the login screen. It is not dismissible by tapping outside; it has an
explicit «إلغاء» button. Its states:

| State | Shown when | Content | Buttons |
|---|---|---|---|
| Waiting | 403 with a token; status `PENDING` | fingerprint icon, «مرّر إصبعك على جهاز البصمة»; secondary line «سيكتمل تسجيل الدخول تلقائيًا بعد التحقق» | إلغاء |
| Device offline | code `BIOMETRIC_DEVICE_UNAVAILABLE` or status `DEVICE_UNAVAILABLE` | «جهاز البصمة غير متصل حاليًا. انتظر قليلًا أو أبلغ المسؤول.» (keeps polling) | إلغاء |
| Verifying | status `VERIFIED` / `ENFORCEMENT_SUSPENDED` / `NOT_REQUIRED`, while the resubmit is in flight | progress, «جارٍ تسجيل الدخول…» | — |
| Success | resubmitted login returned 2xx | the dialog closes and the app continues exactly like a normal login | — |
| Retry | 410, `attemptAvailable=false`, or attempt time passed | «انتهت مهلة المحاولة. مرّر البصمة ثم أعد المحاولة.» | إعادة المحاولة · إلغاء |
| Network | status call failed (timeout, no connection) | «تعذّر الاتصال بالخادم، جارٍ إعادة المحاولة…» (automatic backoff) | إلغاء |
| Contact admin | `BIOMETRIC_MAPPING_MISSING` / `_DISABLED` (from login or status) | the server `message` | حسنًا |

Show the server `message` as the body text for every 403 code. The Arabic strings in §10 are for dialog chrome and
states the server does not word.

## 6. Required Models / DTOs

```dart
class BiometricDenial {            // parsed from error.details of a BIOMETRIC_* 403
  final String code;                 // error.code
  final String message;              // error.message (Arabic, display as-is)
  final int validitySeconds;
  final bool attemptAvailable;
  final String? attemptToken;        // secret, see below
  final DateTime? attemptExpiresAt;  // UTC
  final String? statusPath;
}

enum BiometricAttemptStatus { pending, verified, enforcementSuspended, notRequired,
                              deviceUnavailable, mappingMissing, mappingDisabled }

class BiometricAttemptStatusResponse { final BiometricAttemptStatus status; final DateTime attemptExpiresAt; }
```

- Map an unknown `status` string to `pending`, so a future server value never crashes the dialog.
- **`attemptToken` is a secret.** Keep it in memory only, for the life of the dialog. Never log it, never persist
  it, never show it, never put it in a URL.
- There are no fields to render as actions. The payload carries no terminal name, no external id and no mapping
  details, and the app must not ask for them.

## 7. Repository / API Client Changes

- Login call(s): on a 403 whose `error.code` starts with `BIOMETRIC_`, return a typed `BiometricDenial` failure
  instead of a generic error. Do **not** clear the saved username or email, and do not count it as a wrong
  password or PIN.
- New `getBiometricAttemptStatus(statusPath, attemptToken)`:
  - `GET` with only the `X-Biometric-Attempt-Token` header;
  - receive timeout ≥ 35 s;
  - maps 200 → `BiometricAttemptStatusResponse` and 410 → an `attemptExpired` failure.
- The credentials needed for the single resubmit (PIN or password and the original body) stay in memory for the
  dialog's lifetime only. Never write them to storage for this purpose.

## 8. Provider / State Management Changes

Add a small controller for one attempt: `idle → waiting ⇄ deviceOffline → resubmitting → (success | newDenial | failed)`.

- Poll in a loop: when one long-poll answers `PENDING` or `DEVICE_UNAVAILABLE`, issue the next immediately.
- On a network error, back off (1 s, 2 s, 4 s, then at most 10 s) and keep trying until the backend returns 410.
  Use the server's 410 as the authority on expiry; the device clock may be wrong.
- On app resume, poll immediately.
- Cancel the loop and discard the token when the dialog closes, the user taps «إلغاء», or the app logs another user
  in.
- **Resubmit at most once per status result.** If the resubmitted login returns another `BIOMETRIC_*` 403, replace
  the attempt with the new one (new token) and show the matching state. Never loop resubmits without a new status
  answer.
- Only one attempt may be active at a time; ignore extra taps on «دخول» while the dialog is open.

## 9. Required UX Flow

1. The employee enters the PIN or password and taps login, exactly as today.
2. **2xx:** continue as today. With a fresh punch there is no dialog at all.
3. **403 `BIOMETRIC_*` with a token:** open the dialog in *Waiting* (or *Device offline*) and start polling.
4. The employee scans at the terminal. Within seconds the status becomes `VERIFIED`.
5. The app re-submits the same `{ "pin": … }` body, shows *Verifying*, and on 2xx closes the dialog and proceeds.
6. **403 without a token:**
   - `MAPPING_*` → *Contact admin*;
   - otherwise → *Retry* («مرّر البصمة ثم أعد المحاولة»).
7. **410** or a lost attempt → *Retry*. «إعادة المحاولة» re-submits the login (step 1 without re-typing).

Show success only after the re-submitted login returns 2xx.

## 10. Arabic UI Text

| Key (suggested) | Arabic |
|---|---|
| dialog title | التحقق بالبصمة |
| waiting | مرّر إصبعك على جهاز البصمة |
| waiting, secondary | سيكتمل تسجيل الدخول تلقائيًا بعد التحقق |
| verifying | جارٍ تسجيل الدخول… |
| device offline | جهاز البصمة غير متصل حاليًا. انتظر قليلًا أو أبلغ المسؤول. |
| retry | انتهت مهلة المحاولة. مرّر البصمة ثم أعد المحاولة. |
| network | تعذّر الاتصال بالخادم، جارٍ إعادة المحاولة… |
| button: cancel | إلغاء |
| button: retry | إعادة المحاولة |
| button: ok | حسنًا |

The server-provided `message` values (verbatim, do not rephrase):

| Code | message |
|---|---|
| `BIOMETRIC_VERIFICATION_REQUIRED` | يرجى تمرير البصمة على جهاز البصمة ثم إعادة المحاولة. |
| `BIOMETRIC_VERIFICATION_EXPIRED` | انتهت صلاحية التحقق بالبصمة. يرجى تمرير البصمة مرة أخرى ثم إعادة المحاولة. |
| `BIOMETRIC_DEVICE_UNAVAILABLE` | جهاز البصمة غير متصل حاليًا. يرجى المحاولة بعد قليل أو إبلاغ المسؤول. |
| `BIOMETRIC_MAPPING_MISSING` | لم يتم ربط بصمتك بحسابك بعد. يرجى مراجعة مسؤول النظام. |
| `BIOMETRIC_MAPPING_DISABLED` | ربط البصمة الخاص بحسابك غير مفعّل. يرجى مراجعة مسؤول النظام. |
| `BIOMETRIC_LOGIN_ATTEMPT_EXPIRED` | انتهت مهلة محاولة الدخول. يرجى تسجيل الدخول مرة أخرى. |

## 11. Edge Cases

- **Scanned before tapping login:** the login succeeds immediately, with no dialog.
- **The fingerprint expires between `VERIFIED` and the resubmit** (slow network): the resubmit gets a new 403
  `…_EXPIRED` with a new token. Show the dialog again.
- **The PIN or password was changed meanwhile:** the resubmit returns the normal credential error. Close the dialog
  and show it.
- **The agent goes offline while waiting:** the status becomes `ENFORCEMENT_SUSPENDED` (within about 35–125 s).
  Resubmit.
- **An admin exempts the employee while waiting:** `NOT_REQUIRED`. Resubmit.
- **An admin removes the link while waiting:** `MAPPING_MISSING`/`MAPPING_DISABLED`. Show *Contact admin*.
- **App killed or backgrounded for minutes:** on return, poll. A 410 leads to *Retry*.
- **Two quick taps on login:** only one attempt and one dialog.
- **Old app builds (before this update):** they show the 403 `message` as an error. The employee scans and taps
  login again, which works.
- **Already signed-in users** are not affected: no forced logout, no dialog until their next new login.
- **Device clock wrong:** never compute expiry from the device clock alone. Rely on 410.

## 12. Testing Requirements

Unit / widget tests with a mocked API:
- Every status value and both 403 variants (token / no token) map to the right dialog state.
- Resubmit happens exactly once per `VERIFIED` / `ENFORCEMENT_SUSPENDED` / `NOT_REQUIRED`.
- A resubmit that returns another biometric 403 switches to the new attempt (new token), with no loop.
- 410 → *Retry*; «إعادة المحاولة» re-submits the original login.
- Network errors back off and recover; cancel stops polling and discards the token.
- The token never appears in logs (assert on the log sink) and is never persisted.
- Unknown status string → treated as `PENDING`.
- Non-biometric 403s keep their current handling.

Manual QA against a staging backend with the feature switched on:
- Scan first, then login → no dialog.
- Login, then scan → the dialog closes by itself within a few seconds.
- Let the attempt time out (about 3 minutes) → *Retry*.
- Admin turns the switch off while the dialog waits → it proceeds.
- Unlinked employee → *Contact admin*.

## 13. Backend Compatibility / Rollout Notes

- **Additive and backward-compatible.** Request bodies, success responses and existing error codes are unchanged.
  The backend can deploy before the app update, because the feature is **off** until a SYSTEM_ADMIN activates it.
- Activation happens only after this app update is released and installed on the floor devices. The admin can
  pilot role by role.
- With the feature off, the login endpoints never return any of the codes above, so the app never opens the
  dialog. An attempt that was already waiting when the admin switched it off answers `NOT_REQUIRED`.
- Emergency: the SYSTEM_ADMIN can switch the check off at any time. No app change is needed and no session is
  affected.
- Minimum app version: the first build containing this dialog. Record it in the release notes; the admin needs it
  before activating.

## 14. Final Acceptance Criteria

- [ ] With the feature off, the login behaves byte-for-byte as before.
- [ ] A biometric 403 opens the fingerprint dialog; other 403s do not.
- [ ] After a scan, the dialog completes the login automatically with a single resubmit, without re-typing the
      PIN or password.
- [ ] `DEVICE_UNAVAILABLE`, `MAPPING_*`, 410, `attemptAvailable=false` and network loss each show their state.
- [ ] No skip or bypass exists; the token is never logged, persisted or displayed.
- [ ] Times shown (if any) are converted from UTC to `Asia/Hebron`.
- [ ] Arabic texts as in §10; server messages shown verbatim.
- [ ] The tests in §12 pass.
