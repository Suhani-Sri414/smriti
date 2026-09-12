import 'package:flutter/material.dart';

import '../../core/app_services.dart';

/// Caregiver PIN Entry Dialog.
///
/// Guard for kiosk exit and diagnostics screen per APP-BUILD-SPEC.md §12.
/// Protects system diagnostics, sync triggers, and health checks from accidental
/// elder interactions. Defaults to PIN '1234' if not yet configured.
class CaregiverPinDialog extends StatefulWidget {
  const CaregiverPinDialog({
    super.key,
    required this.services,
    this.defaultPin = '1234',
  });

  final AppServices services;
  final String defaultPin;

  /// Shows the dialog and returns true if the correct PIN was entered.
  static Future<bool> show(BuildContext context, AppServices services) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CaregiverPinDialog(services: services),
    );
    return result ?? false;
  }

  @override
  State<CaregiverPinDialog> createState() => _CaregiverPinDialogState();
}

class _CaregiverPinDialogState extends State<CaregiverPinDialog> {
  final TextEditingController _pinController = TextEditingController();
  String _configuredPin = '';
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPin();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadPin() async {
    final storedPin =
        await widget.services.db.appConfigsDao.getValue('caregiverPin');
    if (mounted) {
      setState(() {
        _configuredPin =
            (storedPin != null && storedPin.isNotEmpty) ? storedPin : widget.defaultPin;
        _isLoading = false;
      });
    }
  }

  void _verifyPin() {
    final entered = _pinController.text.trim();
    if (entered == _configuredPin) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = 'Incorrect PIN. Please try again.';
        _pinController.clear();
      });
    }
  }

  void _onDigitPressed(String digit) {
    if (_pinController.text.length < 6) {
      setState(() {
        _errorMessage = null;
        _pinController.text += digit;
      });
      if (_pinController.text.length == _configuredPin.length) {
        _verifyPin();
      }
    }
  }

  void _onBackspacePressed() {
    if (_pinController.text.isNotEmpty) {
      setState(() {
        _errorMessage = null;
        _pinController.text =
            _pinController.text.substring(0, _pinController.text.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: _isLoading
              ? const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.lock_rounded,
                                  color: Colors.blueGrey, size: 24),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Caregiver PIN',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter PIN to access device diagnostics & sync controls.',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),

                    // Masked PIN indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _configuredPin.length,
                        (index) {
                          final isFilled = index < _pinController.text.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFilled ? Colors.blueGrey.shade700 : Colors.transparent,
                              border: Border.all(
                                color: Colors.blueGrey.shade400,
                                width: 2,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Error Message
                    if (_errorMessage != null)
                      Text(
                        _errorMessage!,
                        key: const Key('pin_error_text'),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Numeric Keypad
                    _buildKeypad(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var col = 1; col <= 3; col++)
                  _buildKeypadButton('${row * 3 + col}'),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Clear button
              SizedBox(
                width: 72,
                height: 52,
                child: TextButton(
                  onPressed: () => setState(() {
                    _pinController.clear();
                    _errorMessage = null;
                  }),
                  child: const Text('Clear', style: TextStyle(fontSize: 14)),
                ),
              ),
              _buildKeypadButton('0'),
              // Backspace
              SizedBox(
                width: 72,
                height: 52,
                child: IconButton(
                  key: const Key('pin_backspace_button'),
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: _onBackspacePressed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit) {
    return SizedBox(
      width: 72,
      height: 52,
      child: OutlinedButton(
        key: Key('pin_digit_$digit'),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: Colors.grey.shade300),
          padding: EdgeInsets.zero,
        ),
        onPressed: () => _onDigitPressed(digit),
        child: Text(
          digit,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
