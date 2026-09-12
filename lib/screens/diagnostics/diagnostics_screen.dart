import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/db/database.dart';
import '../../core/reminders/health_check.dart';
import '../../core/sync/sync_engine.dart';
import '../reminder_screen.dart';

/// Caregiver Diagnostics & System Management Screen.
///
/// APP-BUILD-SPEC.md §12:
/// Sits behind the kiosk exit PIN (CaregiverPinDialog). Shows:
/// - Patient / Device ID and caregiver contact
/// - Supabase auth status & network connectivity
/// - Content version, last sync time, clock skew, last sync error
/// - Pending unsynced records counter with breakdown
/// - Manual "Sync Now" trigger (SyncTrigger.manual)
/// - Health check results & re-run action
/// - Alarms scheduler state & test reminder trigger
/// - Caregiver PIN update management
///
/// Rendered in standard Material density (caregiver-facing register),
/// never surfaced to the elder (AGENTS.md rule 9).
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.services,
    this.healthCheck,
  });

  final AppServices services;
  final SetupHealthCheck? healthCheck;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsData {
  const _DiagnosticsData({
    required this.patientId,
    required this.deviceId,
    required this.elderName,
    required this.primaryContactName,
    required this.primaryContactPhone,
    required this.contentVersion,
    required this.lastSyncAt,
    required this.clockSkewMs,
    required this.lastSyncError,
    required this.isAuthenticated,
    required this.isOnline,
    required this.unsyncedEvents,
    required this.unsyncedMemos,
    required this.scheduledAlarmsCount,
    required this.activeMedications,
    required this.healthReport,
    required this.isKioskActive,
    required this.isKioskConfigured,
  });

  final String? patientId;
  final String? deviceId;
  final String? elderName;
  final String? primaryContactName;
  final String? primaryContactPhone;
  final String? contentVersion;
  final DateTime? lastSyncAt;
  final int? clockSkewMs;
  final String? lastSyncError;
  final bool isAuthenticated;
  final bool isOnline;
  final int unsyncedEvents;
  final int unsyncedMemos;
  final int scheduledAlarmsCount;
  final List<Medication> activeMedications;
  final HealthCheckReport? healthReport;
  final bool isKioskActive;
  final bool isKioskConfigured;

  int get unsyncedTotal => unsyncedEvents + unsyncedMemos;
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late SetupHealthCheck _healthCheck;
  _DiagnosticsData? _data;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isCheckingHealth = false;
  bool _isRescheduling = false;
  String? _statusBanner;
  Color _bannerColor = Colors.blueGrey;

  @override
  void initState() {
    super.initState();
    _healthCheck = widget.healthCheck ??
        SetupHealthCheck(
          configs: widget.services.db.appConfigsDao,
          scheduler: widget.services.alarmScheduler,
        );
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics({HealthCheckReport? report}) async {
    final configs = widget.services.db.appConfigsDao;
    final patientId = await configs.getValue('patientId');
    final deviceId = await configs.getValue('deviceId');
    final elderName = await configs.getValue('elderName');
    final contactName = await configs.getValue('primaryContactName');
    final contactPhone = await configs.getValue('primaryContactPhone');
    final contentVersion = await configs.getValue('contentVersion');
    final lastSyncAtRaw = await configs.getValue('lastSyncAt');
    final clockSkewRaw = await configs.getValue('clockSkewMs');
    final lastSyncError = await configs.getValue('lastSyncError');

    final isAuth = await widget.services.syncEngine.isAuthenticated();
    final isOnline = await widget.services.syncEngine.hasConnection();
    final unsyncedEvents = await widget.services.eventRepo.unsyncedCount();
    final unsyncedMemos = (await widget.services.memoRepo.pendingUploads()).length;

    final allMeds = await widget.services.contentRepo.getMedications();
    final activeMeds = allMeds.where((m) => m.active).toList();
    final scheduledAlarms =
        widget.services.alarmScheduler.lastScheduledAlarmCount;

    DateTime? lastSyncTime;
    if (lastSyncAtRaw != null && lastSyncAtRaw.isNotEmpty) {
      final ms = int.tryParse(lastSyncAtRaw);
      if (ms != null) {
        lastSyncTime = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }

    int? clockSkew;
    if (clockSkewRaw != null && clockSkewRaw.isNotEmpty) {
      clockSkew = int.tryParse(clockSkewRaw);
    }

    final isKioskActive = await widget.services.kioskService.isKioskActive();
    final isKioskConfigured =
        await widget.services.kioskService.isKioskConfigured();

    if (mounted) {
      setState(() {
        _data = _DiagnosticsData(
          patientId: patientId,
          deviceId: deviceId,
          elderName: elderName,
          primaryContactName: contactName,
          primaryContactPhone: contactPhone,
          contentVersion: contentVersion,
          lastSyncAt: lastSyncTime,
          clockSkewMs: clockSkew,
          lastSyncError: lastSyncError,
          isAuthenticated: isAuth,
          isOnline: isOnline,
          unsyncedEvents: unsyncedEvents,
          unsyncedMemos: unsyncedMemos,
          scheduledAlarmsCount: scheduledAlarms,
          activeMedications: activeMeds,
          healthReport: report ?? _data?.healthReport,
          isKioskActive: isKioskActive,
          isKioskConfigured: isKioskConfigured,
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerManualSync() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _statusBanner = 'Running full sync with Supabase...';
      _bannerColor = Colors.indigo;
    });

    try {
      final result =
          await widget.services.syncEngine.run(trigger: SyncTrigger.manual);
      await _loadDiagnostics();

      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        if (result.isOk) {
          _statusBanner = 'Sync completed successfully!';
          _bannerColor = Colors.green.shade700;
        } else if (result.status == 'skipped') {
          _statusBanner = 'Sync skipped: ${result.reason}';
          _bannerColor = Colors.orange.shade800;
        } else {
          _statusBanner = 'Sync partial errors: ${result.errors.join("; ")}';
          _bannerColor = Colors.red.shade700;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _statusBanner = 'Sync error: $e';
        _bannerColor = Colors.red.shade700;
      });
    }
  }

  Future<void> _runHealthCheck() async {
    if (_isCheckingHealth) return;
    setState(() {
      _isCheckingHealth = true;
      _statusBanner = 'Running OEM & permission health check...';
      _bannerColor = Colors.teal.shade700;
    });

    try {
      final report = await _healthCheck.run();
      await _loadDiagnostics(report: report);

      if (!mounted) return;
      setState(() {
        _isCheckingHealth = false;
        if (report.isReady) {
          _statusBanner = 'Health Check: Device is fully ready.';
          _bannerColor = Colors.green.shade700;
        } else {
          _statusBanner =
              'Health Check: Needs attention (${report.problems.join(", ")})';
          _bannerColor = Colors.orange.shade900;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingHealth = false;
        _statusBanner = 'Health check failed: $e';
        _bannerColor = Colors.red.shade700;
      });
    }
  }

  Future<void> _rescheduleAlarms() async {
    if (_isRescheduling) return;
    setState(() {
      _isRescheduling = true;
      _statusBanner = 'Rescheduling all medication alarms...';
      _bannerColor = Colors.blueGrey;
    });

    try {
      await widget.services.alarmScheduler.rescheduleAll();
      await _loadDiagnostics();

      if (!mounted) return;
      setState(() {
        _isRescheduling = false;
        _statusBanner =
            'Alarms rescheduled: ${widget.services.alarmScheduler.lastScheduledAlarmCount} alarms active.';
        _bannerColor = Colors.green.shade700;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRescheduling = false;
        _statusBanner = 'Reschedule failed: $e';
        _bannerColor = Colors.red.shade700;
      });
    }
  }

  Future<void> _fireTestReminder() async {
    final meds = _data?.activeMedications ?? [];
    if (meds.isEmpty) {
      setState(() {
        _statusBanner = 'No active medications found to test.';
        _bannerColor = Colors.orange.shade800;
      });
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReminderScreen(
          services: widget.services,
          medication: meds.first,
        ),
      ),
    );
  }

  Future<void> _scheduleLiveTestAlarm() async {
    try {
      await _healthCheck.scheduleTestAlarm();
      setState(() {
        _statusBanner =
            'Live test alarm scheduled for 60s from now. Leave the app to test background firing.';
        _bannerColor = Colors.blue.shade700;
      });
    } catch (e) {
      setState(() {
        _statusBanner = 'Could not schedule test alarm: $e';
        _bannerColor = Colors.red.shade700;
      });
    }
  }

  Future<void> _checkTestAlarm() async {
    try {
      final fired = await _healthCheck.testAlarmFired();
      if (fired == true) {
        setState(() {
          _statusBanner = 'Success: Test alarm fired and was confirmed.';
          _bannerColor = Colors.green.shade700;
        });
      } else if (await _healthCheck.testAlarmOverdue()) {
        setState(() {
          _statusBanner =
              'Failure: Test alarm is overdue and never fired (battery restrictions).';
          _bannerColor = Colors.red.shade700;
        });
      } else {
        setState(() {
          _statusBanner = 'Test alarm has not fired yet (waiting for 60s window).';
          _bannerColor = Colors.blueGrey;
        });
      }
    } catch (e) {
      setState(() {
        _statusBanner = 'Check failed: $e';
        _bannerColor = Colors.red.shade700;
      });
    }
  }

  Future<void> _changePin() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Caregiver PIN'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter a new 4-digit PIN for device diagnostics and kiosk security.',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('new_pin_input'),
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New 4-digit PIN',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.pin),
                ),
                validator: (v) {
                  if (v == null || v.trim().length != 4 || int.tryParse(v) == null) {
                    return 'PIN must be exactly 4 numeric digits';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('save_new_pin_button'),
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );

    if (newPin != null && newPin.isNotEmpty) {
      await widget.services.db.appConfigsDao.setValue('caregiverPin', newPin);
      if (mounted) {
        setState(() {
          _statusBanner = 'Caregiver PIN updated successfully.';
          _bannerColor = Colors.green.shade700;
        });
      }
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('diagnostics_screen'),
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: const Text(
          'Device & System Diagnostics',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh info',
            onPressed: _isLoading ? null : () => _loadDiagnostics(),
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded),
            tooltip: 'Exit Diagnostics',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                if (_statusBanner != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _bannerColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _statusBanner!,
                            key: const Key('diagnostics_status_banner'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close,
                              color: Colors.white70, size: 18),
                          onPressed: () =>
                              setState(() => _statusBanner = null),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 2-Column Responsive Layout for Tablet
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 900;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildIdentityCard(),
                                const SizedBox(height: 16),
                                _buildSyncCard(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                _buildRemindersCard(),
                                const SizedBox(height: 16),
                                _buildHealthCard(),
                                const SizedBox(height: 16),
                                _buildSecurityCard(),
                              ],
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildIdentityCard(),
                          const SizedBox(height: 16),
                          _buildSyncCard(),
                          const SizedBox(height: 16),
                          _buildRemindersCard(),
                          const SizedBox(height: 16),
                          _buildHealthCard(),
                          const SizedBox(height: 16),
                          _buildSecurityCard(),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildIdentityCard() {
    final d = _data!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, color: Colors.blueGrey.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Identity & Pairing',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildRow('Patient ID', d.patientId ?? 'Unpaired', key: 'diag_patient_id'),
            _buildRow('Device ID', d.deviceId ?? 'Not provisioned', key: 'diag_device_id'),
            _buildRow('Elder Name', d.elderName ?? 'Not configured'),
            _buildRow(
              'Primary Contact',
              '${d.primaryContactName ?? "Not set"} (${d.primaryContactPhone ?? "None"})',
            ),
            _buildRow(
              'Supabase Session',
              d.isAuthenticated ? 'Authenticated (Active)' : 'Not authenticated',
              key: 'diag_auth_status',
              statusColor: d.isAuthenticated ? Colors.green.shade700 : Colors.red.shade700,
            ),
            _buildRow(
              'Network Status',
              d.isOnline ? 'Online' : 'Offline',
              key: 'diag_network_status',
              statusColor: d.isOnline ? Colors.green.shade700 : Colors.orange.shade800,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncCard() {
    final d = _data!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.sync_rounded, color: Colors.indigo.shade600),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Sync Operations',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSyncing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
              ],
            ),
            const Divider(height: 20),
            _buildRow('Content Version', d.contentVersion ?? 'None', key: 'diag_content_version'),
            _buildRow('Last Sync Time', _formatDateTime(d.lastSyncAt), key: 'diag_last_sync'),
            _buildRow(
              'Clock Skew',
              d.clockSkewMs != null ? '${d.clockSkewMs} ms' : '0 ms',
              key: 'diag_clock_skew',
            ),
            _buildRow(
              'Pending Unsynced',
              '${d.unsyncedTotal} records (${d.unsyncedEvents} events, ${d.unsyncedMemos} memos)',
              key: 'diag_pending_count',
              statusColor: d.unsyncedTotal > 0 ? Colors.orange.shade800 : Colors.green.shade700,
            ),
            _buildRow(
              'Last Sync Error',
              (d.lastSyncError != null && d.lastSyncError!.isNotEmpty)
                  ? d.lastSyncError!
                  : 'None',
              key: 'diag_last_error',
              statusColor: (d.lastSyncError != null && d.lastSyncError!.isNotEmpty)
                  ? Colors.red.shade700
                  : Colors.grey.shade700,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                key: const Key('diagnostics_sync_now_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSyncing ? null : _triggerManualSync,
                icon: const Icon(Icons.sync_rounded),
                label: Text(
                  _isSyncing ? 'Syncing...' : 'Sync Now',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemindersCard() {
    final d = _data!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.alarm_on_rounded, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Reminders & Alarms',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildRow(
              'Active Medications',
              '${d.activeMedications.length} active',
              key: 'diag_meds_count',
            ),
            _buildRow(
              'Scheduled Alarms',
              '${d.scheduledAlarmsCount} alarms armed',
              key: 'diag_alarms_count',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const Key('diagnostics_fire_test_reminder_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _fireTestReminder,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Fire test reminder'),
                ),
                OutlinedButton.icon(
                  key: const Key('diagnostics_reschedule_alarms_button'),
                  onPressed: _isRescheduling ? null : _rescheduleAlarms,
                  icon: const Icon(Icons.alarm_add_rounded, size: 18),
                  label: const Text('Reschedule all'),
                ),
                OutlinedButton.icon(
                  key: const Key('diagnostics_test_alarm_button'),
                  onPressed: _scheduleLiveTestAlarm,
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text('Test alarm (60s)'),
                ),
                OutlinedButton.icon(
                  key: const Key('diagnostics_check_test_alarm_button'),
                  onPressed: _checkTestAlarm,
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Did alarm fire?'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCard() {
    final report = _data?.healthReport;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.health_and_safety_outlined, color: Colors.blueGrey.shade700),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'OEM & Health Checks',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isCheckingHealth)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
              ],
            ),
            const Divider(height: 20),
            if (report == null) ...[
              const Text(
                'Health check has not run in this session.',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ] else ...[
              _buildRow('Manufacturer', report.manufacturer),
              _buildRow(
                'Readiness',
                report.isReady ? 'Device Ready' : 'Incomplete',
                key: 'diag_health_status',
                statusColor: report.isReady ? Colors.green.shade700 : Colors.red.shade700,
              ),
              _buildRow('Exact Alarm', report.exactAlarm.name),
              _buildRow('Notifications', report.notifications.name),
              _buildRow('Battery Exemption', report.batteryExemption.name),
              _buildRow('Microphone', report.microphone.name),
              _buildRow('Autostart Screen', report.autostartOpened ? 'Opened' : 'Not needed'),
              _buildRow(
                'Live Alarm Proof',
                report.testAlarmFired == true
                    ? 'Confirmed Fired'
                    : (report.testAlarmFired == false ? 'Failed' : 'Pending Test'),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('diagnostics_rerun_health_check_button'),
                onPressed: _isCheckingHealth ? null : _runHealthCheck,
                icon: const Icon(Icons.refresh),
                label: const Text('Re-run Health Check'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleKioskMode() async {
    final active = _data?.isKioskActive ?? false;
    setState(() {
      _statusBanner = active
          ? 'Releasing kiosk lockdown...'
          : 'Engaging kiosk lockdown...';
      _bannerColor = Colors.indigo;
    });

    try {
      if (active) {
        await widget.services.kioskService.disableKiosk();
        _statusBanner = 'Kiosk mode disabled (Screen unpinned).';
        _bannerColor = Colors.orange.shade900;
      } else {
        await widget.services.kioskService.enableKiosk();
        _statusBanner = 'Kiosk mode enabled (Screen locked).';
        _bannerColor = Colors.green.shade700;
      }
      await _loadDiagnostics();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusBanner = 'Failed to toggle kiosk mode: $e';
        _bannerColor = Colors.red.shade700;
      });
    }
  }

  Widget _buildSecurityCard() {
    final d = _data!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security_rounded, color: Colors.blueGrey.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Caregiver Security & Kiosk',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildRow(
              'Kiosk Lockdown',
              d.isKioskActive ? 'Active (Screen Pinned)' : 'Disabled (Unpinned)',
              key: 'diag_kiosk_status',
              statusColor: d.isKioskActive
                  ? Colors.green.shade700
                  : Colors.orange.shade800,
            ),
            _buildRow(
              'Auto-Lockdown',
              d.isKioskConfigured ? 'Enabled on boot' : 'Disabled',
              key: 'diag_kiosk_auto_status',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('diagnostics_toggle_kiosk_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: d.isKioskActive
                      ? Colors.orange.shade800
                      : Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: _toggleKioskMode,
                icon: Icon(d.isKioskActive
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded),
                label: Text(d.isKioskActive
                    ? 'Exit Kiosk Mode (Unpin Screen)'
                    : 'Engage Kiosk Lockdown'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('diagnostics_change_pin_button'),
                onPressed: _changePin,
                icon: const Icon(Icons.password_rounded),
                label: const Text('Change Caregiver PIN'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value, {
    String? key,
    Color? statusColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(
              value,
              key: key != null ? Key(key) : null,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: statusColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
