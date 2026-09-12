import 'package:flutter/material.dart';
import 'package:smriti/app_colors.dart';
import 'package:smriti/core/auth/pairing_service.dart';
import 'package:smriti/core/db/app_database.dart';
import 'package:smriti/core/repo/ability_repo.dart';
import 'package:smriti/screens/pairing/code_entry_screen.dart';
import 'package:smriti/screens/pairing/scan_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.pairingService, this.onPaired});

  /// Injectable for tests; production builds it from the shared database.
  final PairingService? pairingService;

  /// Called once pairing succeeds by either path, so the shell can leave the
  /// login screen and start the first content pull.
  final VoidCallback? onPaired;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final PairingService _pairingService = widget.pairingService ??
      PairingService(
        configs: appDatabase.appConfigsDao,
        abilityRepo: AbilityRepo(appDatabase),
      );

  /// Opens the QR scanner.
  Future<void> _openPairingScanner() async {
    final paired = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(pairingService: _pairingService),
      ),
    );

    if (paired == true && mounted) {
      widget.onPaired?.call();
    }
  }

  /// Opens direct pairing code entry.
  Future<void> _openCodeEntry() async {
    final paired = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CodeEntryScreen(pairingService: _pairingService),
      ),
    );

    if (paired == true && mounted) {
      widget.onPaired?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Stack(
          children: [
            // Bottom leaves and wave decoration
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 150,
              child: IgnorePointer(
                child: CustomPaint(painter: BottomDecorationPainter()),
              ),
            ),

            // Main screen content
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 140),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/smriti_login_logo.png',
                        width: 260,
                        height: 150,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Memories for a brighter tomorrow',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.secondaryText,
                          fontStyle: FontStyle.italic,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // PAIRING OPTIONS CARD
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
                        decoration: BoxDecoration(
                          color: AppColors.raisedSurface,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: AppColors.border, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.terracottaDeep.withValues(alpha: 0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Device Pairing',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Connect this tablet with the caregiver app to begin',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: AppColors.secondaryText,
                              ),
                            ),

                            const SizedBox(height: 28),

                            // 1. SCAN QR CODE BUTTON
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                key: const Key('scan_qr_button'),
                                onPressed: _openPairingScanner,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.terracotta,
                                  foregroundColor: AppColors.onColor,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.qr_code_scanner,
                                        size: 32,
                                        color: AppColors.onColor,
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            'Scan QR Code',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.onColor,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Hold up tablet to caregiver phone screen',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.onColor
                                                  .withValues(alpha: 0.85),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 18,
                                      color: AppColors.onColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // OR DIVIDER
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: AppColors.border,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: AppColors.border,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // 2. ENTER CODE BUTTON
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                key: const Key('enter_code_button'),
                                onPressed: _openCodeEntry,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.border,
                                    width: 1.5,
                                  ),
                                  backgroundColor: AppColors.pageBackground,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: AppColors.raisedSurface,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AppColors.border,
                                          width: 1,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.pin_outlined,
                                        size: 30,
                                        color: AppColors.terracotta,
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Enter Pairing Code',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primaryText,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Type 8-character code from caregiver app',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.secondaryText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 18,
                                      color: AppColors.secondaryText,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// BOTTOM WAVE + LEAVES
class BottomDecorationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // WAVE
    final wavePaint = Paint()
      ..color = AppColors.wovenMat
      ..style = PaintingStyle.fill;
    final wavePath = Path();
    wavePath.moveTo(0, size.height * 0.45);

    wavePath.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.10,
      size.width * 0.50,
      size.height * 0.45,
    );

    wavePath.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.80,
      size.width,
      size.height * 0.30,
    );

    wavePath.lineTo(size.width, size.height);
    wavePath.lineTo(0, size.height);
    wavePath.close();

    canvas.drawPath(wavePath, wavePaint);

    // LEAVES
    final leafPaint = Paint()
      ..color = AppColors.leafGreen
      ..style = PaintingStyle.fill;

    final stemPaint = Paint()
      ..color = AppColors.leafGreenDark
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Main stem
    final stem = Path();
    stem.moveTo(55, size.height);

    stem.quadraticBezierTo(
      55,
      size.height * 0.55,
      110,
      size.height * 0.10,
    );

    canvas.drawPath(stem, stemPaint);

    // Left leaf
    final leftLeaf = Path();
    leftLeaf.moveTo(55, size.height * 0.68);

    leftLeaf.quadraticBezierTo(
      10,
      size.height * 0.48,
      10,
      size.height * 0.20,
    );

    leftLeaf.quadraticBezierTo(
      55,
      size.height * 0.28,
      55,
      size.height * 0.68,
    );

    leftLeaf.close();

    canvas.drawPath(leftLeaf, leafPaint);

    // Tall leaf
    final tallLeaf = Path();
    tallLeaf.moveTo(78, size.height * 0.52);

    tallLeaf.quadraticBezierTo(
      70,
      size.height * 0.10,
      110,
      0,
    );

    tallLeaf.quadraticBezierTo(
      125,
      size.height * 0.30,
      78,
      size.height * 0.52,
    );

    tallLeaf.close();

    canvas.drawPath(tallLeaf, leafPaint);

    // Right leaf
    final rightLeaf = Path();
    rightLeaf.moveTo(88, size.height * 0.75);

    rightLeaf.quadraticBezierTo(
      125,
      size.height * 0.38,
      160,
      size.height * 0.40,
    );

    rightLeaf.quadraticBezierTo(
      150,
      size.height * 0.70,
      88,
      size.height * 0.75,
    );

    rightLeaf.close();

    canvas.drawPath(rightLeaf, leafPaint);

    // LEAF VEINS
    final veinPaint = Paint()
      ..color = AppColors.leafGreenDark
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(55, size.height * 0.65),
      Offset(25, size.height * 0.35),
      veinPaint,
    );

    canvas.drawLine(
      Offset(82, size.height * 0.48),
      Offset(103, size.height * 0.18),
      veinPaint,
    );

    canvas.drawLine(
      Offset(94, size.height * 0.70),
      Offset(140, size.height * 0.48),
      veinPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}