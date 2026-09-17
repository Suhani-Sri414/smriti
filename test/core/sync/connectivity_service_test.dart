import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/sync/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectivityService', () {
    test('checkConnection returns false when interface is none', () async {
      final service = ConnectivityService(
        checkConnectivity: () async => [ConnectivityResult.none],
        verifyInternet: () async => true,
      );
      addTearDown(service.dispose);

      expect(await service.checkConnection(), isFalse);
    });

    test('checkConnection returns true when interface is wifi and internet reachable',
        () async {
      final service = ConnectivityService(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        verifyInternet: () async => true,
      );
      addTearDown(service.dispose);

      expect(await service.checkConnection(), isTrue);
    });

    test('checkConnection returns false when wifi present but internet unreachable',
        () async {
      final service = ConnectivityService(
        checkConnectivity: () async => [ConnectivityResult.wifi],
        verifyInternet: () async => false,
      );
      addTearDown(service.dispose);

      expect(await service.checkConnection(), isFalse);
    });

    test('onConnectionRestored fires when transitioning from offline to online',
        () async {
      final streamController =
          StreamController<List<ConnectivityResult>>.broadcast();
      addTearDown(streamController.close);

      var isReachable = false;
      final service = ConnectivityService(
        onConnectivityChanged: streamController.stream,
        verifyInternet: () async => isReachable,
      );
      addTearDown(service.dispose);

      final restoredEvents = <void>[];
      final sub = service.onConnectionRestored.listen((e) => restoredEvents.add(e));
      addTearDown(sub.cancel);

      // 1. Initial state: offline
      streamController.add([ConnectivityResult.none]);
      await pumpEventQueue();
      expect(service.isConnected, isFalse);
      expect(restoredEvents, isEmpty);

      // 2. Connectivity restored: wifi + reachable
      isReachable = true;
      streamController.add([ConnectivityResult.wifi]);
      await pumpEventQueue();

      expect(service.isConnected, isTrue);
      expect(restoredEvents.length, 1);
    });
  });
}
