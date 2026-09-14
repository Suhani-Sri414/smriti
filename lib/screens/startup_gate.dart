import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import '../core/sync/sync_engine.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Decides what the app opens on: the elder's home if this tablet is paired,
/// the caregiver login if it is not.
///
/// Before A10.5 `main.dart` always opened the login screen, so a paired tablet
/// had nowhere to go after setup.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.services});

  final AppServices services;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<bool> _paired = _resolve();

  Future<bool> _resolve() async {
    final paired = await widget.services.isPaired();
    if (paired) {
      // Fire-and-forget: content and events sync in the background. Nothing on
      // screen ever waits on the network (AGENTS.md, the one principle).
      unawaited(widget.services.syncEngine.run(trigger: SyncTrigger.foreground));
    }
    return paired;
  }

  /// Pairing just succeeded. Pull content in the background (AGENTS.md, the
  /// one principle: SQLite on the tablet is the source of truth, nothing on
  /// screen ever waits on the network).
  Future<bool> _resolveAfterPairing() async {
    try {
      final paired = await widget.services.isPaired();
      if (paired) {
        unawaited(widget.services.syncEngine.run(trigger: SyncTrigger.manual));
      }
      return paired;
    } catch (_) {
      return false;
    }
  }

  /// Re-checks after pairing completes on the login screen.
  void _recheck() {
    if (mounted) {
      final next = _resolveAfterPairing();
      setState(() {
        _paired = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _paired,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.pageBackground,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == true) {
          return HomeScreen(services: widget.services);
        }

        return LoginScreen(
          pairingService: widget.services.pairingService,
          onPaired: _recheck,
        );
      },
    );
  }
}

/// Deliberately ignores the future: the UI must never wait on a sync.
void unawaited(Future<void> future) {}
