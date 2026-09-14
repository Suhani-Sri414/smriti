import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_colors.dart';
import '../../core/auth/pairing_service.dart';
import 'code_entry_screen.dart';

/// Scans the pairing QR shown by the caregiver web app, then redeems it.
///
/// Caregiver-facing setup screen — it shows progress and errors, which the
/// elder-facing app never does (AGENTS.md non-negotiable #9).
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.pairingService,
    this.onPaired,
  });

  final PairingService pairingService;
  final VoidCallback? onPaired;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  /// Guards against the camera firing the same code many times a second.
  bool _handled = false;
  bool _isRedeeming = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;

    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (raw == null) return;

    _handled = true;
    setState(() {
      _isRedeeming = true;
      _error = null;
    });
    await _controller.stop();

    await _redeem(raw);
  }

  Future<void> _redeem(String token) async {
    try {
      await widget.pairingService.redeemToken(token);
      if (!mounted) return;
      widget.onPaired?.call();
      Navigator.of(context).pop(true);
    } on PairingException catch (e) {
      _failed(e.message);
    } catch (_) {
      _failed('Could not reach the server. Check the connection and retry.');
    }
  }

  void _failed(String message) {
    if (!mounted) return;
    setState(() {
      _isRedeeming = false;
      _error = message;
    });
  }

  Future<void> _rescan() async {
    setState(() {
      _handled = false;
      _error = null;
    });
    await _controller.start();
  }

  Future<void> _openCodeEntry() async {
    final paired = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CodeEntryScreen(
          pairingService: widget.pairingService,
          onPaired: widget.onPaired,
        ),
      ),
    );
    if (paired == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.pageBackground,
        foregroundColor: AppColors.primaryText,
        elevation: 0,
        title: const Text('Scan pairing code'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                  if (_isRedeeming)
                    Container(
                      color: AppColors.pageBackground.withValues(alpha: 0.85),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
              child: Column(
                children: [
                  Text(
                    'Point the camera at the code in the web app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const Key('scan_error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.terracottaDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _rescan,
                      child: const Text('Try scanning again'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('enter_code_instead'),
                    onPressed: _isRedeeming ? null : _openCodeEntry,
                    child: Text(
                      'Enter the code by hand instead',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.terracottaDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
