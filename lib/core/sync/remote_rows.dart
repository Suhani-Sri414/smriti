import 'dart:convert';

import '../db/database.dart';

/// Maps local Drift rows to the remote table shapes.
///
/// Column names and types here are confirmed against `information_schema` on
/// the live backend, not inferred.
///
/// Two consequences of the real types worth keeping in mind:
///
///  * Every timestamp the device writes — `events.ts`, `sessions.started_at`
///    and `ended_at` and `abandoned_at_ms`, `reminder_events.scheduled_at` /
///    `fired_at` / `responded_at`, `memos.recorded_at`,
///    `escalations.requested_at` — is `bigint`, so epoch milliseconds go up
///    exactly as they are stored locally. No ISO-8601 conversion anywhere.
///    (The `timestamptz` columns on those tables — `server_received_at`,
///    `executed_at`, `created_at`, `not_before`, `read_at` — are written by the
///    server, never by the device.)
///  * `events.metrics` is `jsonb` while `events.trial_context` is `text`, so
///    they are NOT treated alike: see [_jsonb].
///
/// `escalations.id` is `text` rather than `uuid`, which is what lets the
/// deterministic `{reminderEventId}_{step}` id work (AGENTS.md #2).
class RemoteRows {
  const RemoteRows._();

  /// Remote table names, per §7.
  static const String eventsTable = 'events';
  static const String sessionsTable = 'sessions';
  static const String reminderEventsTable = 'reminder_events';
  static const String memosTable = 'memos';
  static const String escalationsTable = 'escalations';

  static Map<String, dynamic> trial(TrialEvent row, String patientId) => {
        'id': row.id,
        'patient_id': patientId,
        'session_id': row.sessionId,
        'game_id': row.gameId,
        'domain': row.domain,
        'item_id': row.itemId,
        'item_difficulty': row.itemDifficulty,
        'theta_before': row.thetaBefore,
        'correct': row.correct,
        'initiation_ms': row.initiationMs,
        'movement_ms': row.movementMs,
        'response_time_ms': row.responseTimeMs,
        'chosen_id': row.chosenId,
        'error_class': remoteErrorClass(row.errorClass),
        'trial_index': row.trialIndex,
        // text: the encoded JSON string is the value.
        'trial_context': row.trialContext,
        'hint_level': row.hintLevel,
        // jsonb: must go up as a decoded object, not a string.
        'metrics': _jsonb(row.metrics),
        'ts': row.ts,
        'hour_of_day': row.hourOfDay,
        'tz_offset_min': row.tzOffsetMin,
      };

  /// Decodes a locally-stored JSON string for a `jsonb` column.
  ///
  /// `TrialEvents.metrics` holds the string `jsonEncode` produced. Passing that
  /// string straight through would store a jsonb *string scalar*
  /// (`"{\"picked\":3}"`) rather than an object, and every downstream query
  /// like `metrics->>'picked'` would return null — silently, with no error at
  /// insert time. So it is decoded here.
  ///
  /// Anything unparseable is wrapped rather than dropped: losing a trial's
  /// metrics outright would be worse than storing them awkwardly.
  static Object? _jsonb(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return jsonDecode(encoded);
    } on FormatException {
      return {'raw': encoded};
    }
  }

  static Map<String, dynamic> session(Session row, String patientId) => {
        'id': row.id,
        'patient_id': patientId,
        'started_at': row.startedAt,
        'ended_at': row.endedAt,
        'game_ids': row.gameIds,
        'completed': row.completed,
        'abandoned_at_ms': row.abandonedAtMs,
        'demo_replays': row.demoReplays,
      };

  /// Maps device reminder outcomes to the backend vocabulary (§7 / 0004_events.sql).
  /// Backend check: `outcome in ('confirmed','declined','no_response')`.
  static String? remoteOutcome(String? localOutcome) {
    if (localOutcome == null) return null;
    switch (localOutcome.toLowerCase().trim()) {
      case 'taken':
      case 'confirmed':
        return 'confirmed';
      case 'snoozed':
      case 'declined':
      case 'not_now':
        return 'declined';
      case 'missed':
      case 'no_response':
        return 'no_response';
      default:
        return localOutcome;
    }
  }

  /// Maps device error classes to backend analytics vocabulary.
  /// Backend daily_play aggregates: 'perseverative', 'repeat_selection', 'semantic'.
  static String? remoteErrorClass(String? err) {
    if (err == null) return null;
    if (err.startsWith('semantic')) return 'semantic';
    if (err == 'perseveration') return 'perseverative';
    return err;
  }

  static Map<String, dynamic> reminderEvent(
    ReminderEvent row,
    String patientId,
  ) =>
      {
        'id': row.id,
        'patient_id': patientId,
        'medication_id': row.medicationId,
        'scheduled_at': row.scheduledAt,
        'fired_at': row.firedAt,
        'responded_at': row.respondedAt,
        'outcome': remoteOutcome(row.outcome),
        'channel': row.channel,
        'ladder_step': row.ladderStep,
      };

  /// The device only ever writes `status: 'requested'` (§7). Any other status
  /// seen coming back is the server's business, not an error.
  static Map<String, dynamic> escalation(
    EscalationRequest row,
    String patientId,
  ) =>
      {
        'id': row.id,
        'patient_id': patientId,
        'reminder_event_id': row.reminderEventId,
        'medication_id': row.medicationId,
        'step': row.step,
        'requested_at': row.requestedAt,
        'status': 'requested',
      };

  /// [objectPath] is the uploaded storage object, not the local file path —
  /// the server cannot resolve a path on the tablet.
  static Map<String, dynamic> memo(
    VoiceMemo row,
    String patientId,
    String objectPath,
  ) =>
      {
        'id': row.id,
        'patient_id': patientId,
        'storage_path': objectPath,
        'duration_ms': row.durationMs,
        'recorded_at': row.recordedAt,
        'context_tag': row.contextTag,
      };
}
