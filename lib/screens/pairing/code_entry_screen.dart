import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_colors.dart';
import '../../core/auth/pairing_service.dart';

/// Typed-code fallback when the QR scan will not work — bad light, cracked
/// camera, code read aloud over the phone.
///
/// Caregiver-facing setup screen, so it uses normal density and does show
/// errors. The elder never reaches it (AGENTS.md non-negotiable #9).
class CodeEntryScreen extends StatefulWidget {
  const CodeEntryScreen({
    super.key,
    required this.pairingService,
    this.onPaired,
  });

  final PairingService pairingService;
  final VoidCallback? onPaired;

  @override
  State<CodeEntryScreen> createState() => _CodeEntryScreenState();
}

class _CodeEntryScreenState extends State<CodeEntryScreen> {
  static const int _boxes = PairingService.codeLength;

  late final List<TextEditingController> _controllers =
      List.generate(_boxes, (_) => TextEditingController());
  late final List<FocusNode> _focusNodes =
      List.generate(_boxes, (_) => FocusNode());

  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  bool get _isComplete => _code.length == _boxes;

  void _onChanged(int index, String value) {
    setState(() => _error = null);

    if (value.isEmpty) return;

    // Paste of a whole code lands in one box; spread it across the row.
    if (value.length > 1) {
      final chars = PairingService.normalize(value).split('');
      for (var i = 0; i < _boxes; i++) {
        final char = index + i < chars.length ? chars[index + i] : '';
        if (index + i < _boxes) _controllers[index + i].text = char;
      }
      _focusNodes[_boxes - 1].requestFocus();
      setState(() {});
      return;
    }

    if (index < _boxes - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_isComplete || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await widget.pairingService.redeemCode(_code);
      if (!mounted) return;
      widget.onPaired?.call();
      Navigator.of(context).pop(true);
    } on PairingException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Could not reach the server. Check the connection and retry.';
      });
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
        title: const Text('Enter pairing code'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Type the 8-character code shown in the web app.',
                style: TextStyle(fontSize: 16, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < _boxes; i++) _buildBox(i),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('pairing_error'),
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.terracottaDark,
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  key: const Key('pairing_submit'),
                  onPressed: _isComplete && !_isSubmitting ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.terracotta,
                    foregroundColor: AppColors.onColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Text(
                          'Pair this tablet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBox(int index) {
    return SizedBox(
      width: 38,
      child: TextField(
        key: Key('code_box_$index'),
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        enabled: !_isSubmitting,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryText,
        ),
        inputFormatters: [
          UpperCaseFormatter(),
          // Only the exact pairing alphabet can be typed at all, so an
          // ambiguous character never reaches the server.
          FilteringTextInputFormatter.allow(
            RegExp('[${PairingService.codeAlphabet}]'),
          ),
        ],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.raisedSurface,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.terracotta, width: 2),
          ),
        ),
        onChanged: (value) => _onChanged(index, value),
      ),
    );
  }
}

/// Upper-cases as the caregiver types, so a lower-case letter is accepted
/// rather than silently filtered away by the alphabet formatter.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
