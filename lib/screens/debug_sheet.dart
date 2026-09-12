import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/db/database.dart';
import '../core/reminders/health_check.dart';
import 'diagnostics/caregiver_pin_dialog.dart';
import 'diagnostics/diagnostics_screen.dart';
import 'reminder_screen.dart';

/// Caregiver-facing debug panel, reached by long-pressing the home title.
///
/// A forerunner of §12's diagnostics screen (task A14), which will sit behind
/// the kiosk PIN. The elder never sees any of this (AGENTS.md #9).
class DebugSheet extends StatefulWidget {
  const DebugSheet({super.key, required this.services});

  final AppServices services;

  static Future<void> show(BuildContext context, AppServices services) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DebugSheet(services: services),
    );
  }

  @override
  State<DebugSheet> createState() => _DebugSheetState();
}

class _DebugSheetState extends State<DebugSheet> {
  String _status = '';
  HealthCheckReport? _report;
  bool _busy = false;

  Future<void> _run(String label, Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    try {
      final result = await action();
      if (mounted) setState(() => _status = result);
    } catch (e) {
      if (mounted) setState(() => _status = '$label failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fires a reminder for the first active medication right now, without
  /// waiting on a real dose window.
  Future<void> _fireTestReminder() async {
    final medications = await widget.services.contentRepo.getMedications();
    if (medications.isEmpty) {
      setState(() => _status = 'No active medications — pull content first.');
      return;
    }
    if (!mounted) return;

    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReminderScreen(
          services: widget.services,
          medication: medications.first,
        ),
      ),
    );
  }

  SetupHealthCheck get _healthCheck => SetupHealthCheck(
        configs: widget.services.db.appConfigsDao,
        scheduler: widget.services.alarmScheduler,
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Debug',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            ElevatedButton(
              key: const Key('debug_fire_test_reminder'),
              onPressed: _busy ? null : _fireTestReminder,
              child: const Text('Fire test reminder now'),
            ),
            const SizedBox(height: 8),

            OutlinedButton.icon(
              key: const Key('debug_open_diagnostics'),
              onPressed: () async {
                final nav = Navigator.of(context);
                final authed =
                    await CaregiverPinDialog.show(context, widget.services);
                if (!authed || !mounted) return;
                nav.pop();
                await nav.push(
                  MaterialPageRoute(
                    builder: (_) =>
                        DiagnosticsScreen(services: widget.services),
                  ),
                );
              },
              icon: const Icon(Icons.settings_suggest_rounded, size: 18),
              label: const Text('Full Diagnostics Screen (PIN)'),
            ),
            const SizedBox(height: 8),

            OutlinedButton(
              key: const Key('debug_reschedule_alarms'),
              onPressed: _busy
                  ? null
                  : () => _run('Rescheduling alarms', () async {
                        await widget.services.alarmScheduler.rescheduleAll();
                        return 'Scheduled '
                            '${widget.services.alarmScheduler.lastScheduledAlarmCount} '
                            'alarms.';
                      }),
              child: const Text('Reschedule all alarms'),
            ),
            const SizedBox(height: 8),

            OutlinedButton(
              key: const Key('debug_health_check'),
              onPressed: _busy
                  ? null
                  : () => _run('Running health check', () async {
                        final report = await _healthCheck.run();
                        if (mounted) setState(() => _report = report);
                        return report.isReady
                            ? 'Ready.'
                            : 'Not ready: ${report.problems.join(', ')}';
                      }),
              child: const Text('Run setup health check'),
            ),
            const SizedBox(height: 8),

            OutlinedButton(
              key: const Key('debug_test_alarm'),
              onPressed: _busy
                  ? null
                  : () => _run('Scheduling test alarm', () async {
                        await _healthCheck.scheduleTestAlarm();
                        return 'Test alarm armed for 60s from now. '
                            'Leave the app — it must fire anyway.';
                      }),
              child: const Text('Schedule live test alarm (60s)'),
            ),
            const SizedBox(height: 8),

            OutlinedButton(
              key: const Key('debug_check_test_alarm'),
              onPressed: _busy
                  ? null
                  : () => _run('Checking test alarm', () async {
                        final fired = await _healthCheck.testAlarmFired();
                        if (fired == true) return 'Test alarm fired.';
                        if (await _healthCheck.testAlarmOverdue()) {
                          return 'Test alarm is overdue and never fired — '
                              'battery restrictions are killing it.';
                        }
                        return 'Not fired yet.';
                      }),
              child: const Text('Did the test alarm fire?'),
            ),

            const SizedBox(height: 16),
            Text(_status, key: const Key('debug_status')),
            if (_report != null)
              Text(
                'Manufacturer: ${_report!.manufacturer} · '
                'autostart opened: ${_report!.autostartOpened}',
                key: const Key('debug_report'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Convenience for callers that already hold the medication list.
extension DebugMedications on List<Medication> {
  Medication? get firstActiveOrNull =>
      where((m) => m.active).isEmpty ? null : firstWhere((m) => m.active);
}
