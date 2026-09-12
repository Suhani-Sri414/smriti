# App Tasks

Rules: one task per session. Run `flutter analyze`, paste full output. Commit. Then start
a new session for the next task.

## Phase 0 — already done, do not redo
- [x] **A01** Drift schema + DAOs — verified correct against spec
- [x] **A02** File path service — verified correct

## Phase 1 — fix and unblock
- [ ] **A03** Fix `AbilityEstimator` per APP-BUILD-SPEC.md §3.
      AC: `seed()`, `update()`, `nextDifficulty()` all present, θ clamp in place,
      RT tracking present, convergence test passes (`flutter test`).
- [ ] **A04** Delete counter-app boilerplate from `main.dart`. Add `supabase_flutter` to
      `pubspec.yaml`, call `Supabase.initialize()` before `runApp()`.
      AC: app still builds and shows the login screen, no boilerplate remains.

## Phase 2 — local-only, no backend needed
- [ ] **A05** Repositories: `content_repo.dart`, `event_repo.dart`, `ability_repo.dart`,
      `memo_repo.dart` in `lib/core/repo/`. Read/write Drift only.
      AC: unit test proving a round-trip write+read for each repo.
- [ ] **A06** Session runner + `CognitiveGame` interface + ghost-hand widget +
      one game (Market Basket) built end to end against a mock content JSON.
      AC: playing the game locally writes a fully-populated `TrialEvents` row
      (every column from §5 non-null where required) and updates `AbilityStates`.
- [ ] **A06b** Post-pairing navigation: home screen with entry point into
      a playable game session (using the A06 harness), so sessions can
      actually be triggered and synced through real UI rather than tests
      only. Should exist before A11's reminder-to-screen return path can
      be meaningfully tested.

## Phase 3 — pairing (unblocks everything backend-facing)
- [x] **A07** Wire the existing login screen's QR button to `redeem-pairing-token` via
      `pairing_service.dart`. Add code-entry fallback using the exact alphabet from
      APP-BUILD-SPEC.md §7.
      AC: a real pairing token/code generated from the web app successfully
      authenticates the device and writes `patientId` etc. into `AppConfigs`.
      Verified on physical hardware against the live backend.
- [x] **A08** Caregiver-login pairing path (`pair-device-authenticated`), with mandatory
      `signOut()` before establishing the device session.
      AC: after pairing this way, `Supabase.instance.client.auth.currentUser` reflects
      the device identity, not the caregiver's.
      Verified on physical hardware: device identity correct (synthetic device
      address, not the caregiver's), `app_metadata.patient_id` matched, patient
      list resolved from `patient_members`, and sign-out-on-cancel confirmed
      when the flow is abandoned at the confirmation screen.

## Phase 4 — sync
- [ ] **A09** `ContentPuller` + `MediaDownloader`. Media → verify → DB swap → reschedule.
      AC: pulling content for a real patient populates `People`/`Medications`/
      `RoutineItems` and downloads their photos/voice to disk.
- [ ] **A10** `EventPusher`, `MemoUploader`, `EscalationWriter`, heartbeat.
      AC: playing a session while online results in rows appearing in Supabase's
      `events`/`sessions` tables with matching IDs. No `.select()` used anywhere in
      this code (verify by grep).
- [ ] **A10b** Wire connectivity_plus into SyncEngine's hasConnection
      callback, replacing the injected stub. Depends on A10.

## Phase 4.5 — navigation shell (unblocks observing any of the above)
- [ ] **A10.5** Minimal app shell, so pairing leads somewhere and A11 has a
      target to return the elder to. Deliberately ugly — bare functional
      widgets only.
      1. Startup gate in `main.dart`: paired → home, unpaired → login.
      2. `SyncEngine` constructed at startup; a pull triggered right after
         pairing succeeds (this is what first puts real medications on the
         device — `rescheduleAll()` has nothing to schedule without it).
      3. Stub home screen: routine strip + one button into Market Basket.
      4. Reminder screen (the future full-screen-intent target): pill photo,
         caregiver voice playback, taken / not now, writes `outcome` +
         `respondedAt`, returns home.
      5. "Fire test reminder now" hidden trigger, pulled forward from §12 —
         waiting for a real medication window on a physical device is not a
         workable test loop.
      6. `ContentPuller.onContentChanged` wired to `AlarmScheduler.rescheduleAll()`.
         The scheduler stays a no-op stub until A11; only the call site is built.

      Out of scope, do not touch: visual design beyond bare functional widgets,
      the actual alarm scheduler / isolate logic (A11), OEM permission and
      manifest work (A11, per §10).

      AC: pairing a fresh device, running a real content pull, and landing on a
      home screen showing real medication and routine data from the live
      backend. First task where a human can observe real synced content in the
      running app rather than in a test assertion.

## Phase 5 — reminders (highest risk, budget real time)
- [ ] **A11** Alarm scheduler + reminder isolate + full-screen notification + ladder
      steps 0–1, tested on a real Android device.
      AC: an alarm fires with the app fully killed, and again after a device reboot.
- [ ] **A12** Setup health check with OEM autostart handling and a live test-alarm
      confirmation step.
      AC: on a Xiaomi/Oppo/Vivo test device, a scheduled test alarm actually fires
      after the health check completes.

## Phase 6 — remaining
- [ ] **A13** Remaining games on the harness from A06.
- [x] **A14** Diagnostics screen behind kiosk PIN.
- [x] **A15** Kiosk mode lockdown on the main activity.
- [ ] **A16** Voice output (pre-recorded phrase playback) + constrained voice input for
      home-screen commands.
- [ ] **A17** 48-hour airplane-mode test. Play across two days offline, reconnect,
      confirm full sync with zero duplicates and zero data loss.
