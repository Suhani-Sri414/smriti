import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/kiosk/kiosk_service.dart';

import '../repo/_test_db.dart';

class _FakeKioskHandler implements KioskHandler {
  _FakeKioskHandler({bool initialActive = false}) : _isActive = initialActive;

  bool _isActive;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> get isKioskMode async => _isActive;

  @override
  Future<bool> startKioskMode() async {
    startCalls++;
    _isActive = true;
    _controller.add(true);
    return true;
  }

  @override
  Future<bool> stopKioskMode() async {
    stopCalls++;
    _isActive = false;
    _controller.add(false);
    return true;
  }

  @override
  Stream<bool> watchKioskMode() => _controller.stream;

  void dispose() {
    _controller.close();
  }
}

void main() {
  late SmritiDatabase db;
  late _FakeKioskHandler handler;
  late KioskService service;

  setUp(() {
    db = newTestDb();
    handler = _FakeKioskHandler();
    service = KioskService(configs: db.appConfigsDao, handler: handler);
  });

  tearDown(() async {
    handler.dispose();
    await db.close();
  });

  group('KioskService', () {
    test('starts inactive and unconfigured by default', () async {
      expect(await service.isKioskActive(), isFalse);
      expect(await service.isKioskConfigured(), isFalse);
    });

    test('enableKiosk sets config to true and calls startKioskMode', () async {
      final result = await service.enableKiosk();

      expect(result, isTrue);
      expect(handler.startCalls, 1);
      expect(await service.isKioskActive(), isTrue);
      expect(await service.isKioskConfigured(), isTrue);
      expect(await db.appConfigsDao.getValue(KioskService.kioskEnabledKey), 'true');
    });

    test('disableKiosk sets config to false and calls stopKioskMode', () async {
      await service.enableKiosk();
      expect(await service.isKioskActive(), isTrue);

      final result = await service.disableKiosk();

      expect(result, isTrue);
      expect(handler.stopCalls, 1);
      expect(await service.isKioskActive(), isFalse);
      expect(await service.isKioskConfigured(), isFalse);
      expect(await db.appConfigsDao.getValue(KioskService.kioskEnabledKey), 'false');
    });

    test('autoLockdownIfConfigured starts kiosk when configured', () async {
      await db.appConfigsDao.setValue(KioskService.kioskEnabledKey, 'true');

      final result = await service.autoLockdownIfConfigured();

      expect(result, isTrue);
      expect(handler.startCalls, 1);
      expect(await service.isKioskActive(), isTrue);
    });

    test('autoLockdownIfConfigured does not start when not configured', () async {
      await db.appConfigsDao.setValue(KioskService.kioskEnabledKey, 'false');

      final result = await service.autoLockdownIfConfigured();

      expect(result, isFalse);
      expect(handler.startCalls, 0);
      expect(await service.isKioskActive(), isFalse);
    });

    test('watchKioskMode emits active changes', () async {
      final states = <bool>[];
      final sub = service.watchKioskMode().listen(states.add);

      await service.enableKiosk();
      await service.disableKiosk();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(states, [true, false]);
      await sub.cancel();
    });
  });
}
