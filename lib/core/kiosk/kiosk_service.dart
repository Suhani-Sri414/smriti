import 'package:flutter/foundation.dart';
import 'package:kiosk_mode/kiosk_mode.dart' as km;

import '../db/dao/app_configs_dao.dart';

/// Abstraction seam for OS screen pinning / lock task mode.
///
/// Allows unit and widget tests to run without touching native platform channels.
abstract class KioskHandler {
  Future<bool> get isKioskMode;
  Future<bool> startKioskMode();
  Future<bool> stopKioskMode();
  Stream<bool> watchKioskMode();
}

/// Production implementation using `package:kiosk_mode`.
class RealKioskHandler implements KioskHandler {
  const RealKioskHandler();

  @override
  Future<bool> get isKioskMode async {
    try {
      final mode = await km.getKioskMode();
      return mode == km.KioskMode.enabled;
    } catch (e) {
      debugPrint('Error getting kiosk mode: $e');
      return false;
    }
  }

  @override
  Future<bool> startKioskMode() async {
    try {
      return await km.startKioskMode();
    } catch (e) {
      debugPrint('Error starting kiosk mode: $e');
      return false;
    }
  }

  @override
  Future<bool> stopKioskMode() async {
    try {
      final res = await km.stopKioskMode();
      return res ?? false;
    } catch (e) {
      debugPrint('Error stopping kiosk mode: $e');
      return false;
    }
  }

  @override
  Stream<bool> watchKioskMode() {
    try {
      return km
          .watchKioskMode()
          .map((mode) => mode == km.KioskMode.enabled)
          .handleError((e) {
        debugPrint('Error watching kiosk mode: $e');
      });
    } catch (e) {
      debugPrint('Error initiating kiosk mode stream: $e');
      return const Stream<bool>.empty();
    }
  }
}

/// Manages kiosk lockdown state and preferences for the Smriti Elder App.
///
/// APP-BUILD-SPEC.md §12 / TASKS.md A15:
/// Ensures the elder is locked inside the Smriti application so accidental
/// navigation gestures or home button presses never escape to the Android OS.
/// Caregivers can release kiosk mode from within DiagnosticsScreen.
class KioskService {
  KioskService({
    required this.configs,
    KioskHandler? handler,
  }) : _handler = handler ?? const RealKioskHandler();

  final AppConfigsDao configs;
  final KioskHandler _handler;

  static const String kioskEnabledKey = 'kioskEnabled';

  /// Whether kiosk mode is currently active at the OS level (screen pinned).
  Future<bool> isKioskActive() => _handler.isKioskMode;

  /// Whether the tablet is configured to run in kiosk mode.
  Future<bool> isKioskConfigured() async {
    final val = await configs.getValue(kioskEnabledKey);
    return val == 'true';
  }

  /// Engages kiosk mode (pins the screen) and persists preference.
  Future<bool> enableKiosk() async {
    await configs.setValue(kioskEnabledKey, 'true');
    return _handler.startKioskMode();
  }

  /// Releases kiosk mode (unpins the screen) and persists preference.
  Future<bool> disableKiosk() async {
    await configs.setValue(kioskEnabledKey, 'false');
    return _handler.stopKioskMode();
  }

  /// Automatically locks down if configured.
  Future<bool> autoLockdownIfConfigured() async {
    if (await isKioskConfigured()) {
      return _handler.startKioskMode();
    }
    return false;
  }

  /// Stream of active kiosk status changes.
  Stream<bool> watchKioskMode() => _handler.watchKioskMode();
}
