import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import '../core/db/database.dart';
import 'debug_sheet.dart';
import 'games_menu_screen.dart';
import 'my_people_screen.dart';

/// Screen 01: The Elder Home Screen.
///
/// Designed for a 1280×800 landscape tablet in North-East India.
/// Four large touch cards carry the core capabilities (Play, My People,
/// Today, Call Contact) with a central microphone button. No white, no red,
/// no error state, no connectivity/sync indicators visible to the elder.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<_HomeData> _data = _load();

  Future<_HomeData> _load() async {
    final services = widget.services;
    final elderName =
        await services.db.appConfigsDao.getValue('elderName') ?? '';
    final primaryContact =
        await services.db.appConfigsDao.getValue('primaryContactName') ?? 'Bina';

    return _HomeData(
      elderName: elderName,
      primaryContactName: primaryContact.isEmpty ? 'Bina' : primaryContact,
      contentVersion: await services.contentRepo.getContentVersion(),
      medications: await services.contentRepo.getMedications(),
      routineItems: await services.contentRepo.getRoutineItems(),
      people: await services.contentRepo.getPeople(),
    );
  }

  Future<void> _openGamesMenu() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GamesMenuScreen(
          services: widget.services,
        ),
      ),
    );
  }

  Future<void> _openDebugSheet() => DebugSheet.show(context, widget.services);

  Future<void> _onMyPeopleTapped(_HomeData data) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyPeopleScreen(
          services: widget.services,
        ),
      ),
    );
  }

  void _onTodayTapped(_HomeData data) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Today'),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.marigold,
      ),
    );
  }

  void _onCallTapped(_HomeData data) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling ${data.primaryContactName}...'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.leafGreen,
      ),
    );
  }

  void _onMicTapped() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Listening...'),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.terracotta,
      ),
    );
  }

  String _formatGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning, ';
    if (hour < 17) return 'Good afternoon, ';
    return 'Good evening, ';
  }

  String _formatCurrentTime() {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: FutureBuilder<_HomeData>(
          future: _data,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.terracotta),
              );
            }
            final data = snapshot.data!;
            final name =
                data.elderName.isEmpty ? 'Ibemhal' : data.elderName;

            return Column(
              children: [
                // TOP BAR: Greeting & Time
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 14, 28, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      GestureDetector(
                        onLongPress: _openDebugSheet,
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatGreeting(),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primaryText,
                                    fontFamily: 'Noto Sans',
                                  ),
                                ),
                                Text(
                                  name,
                                  key: const Key('home_title'),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryText,
                                    fontFamily: 'Noto Sans',
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'content v${data.contentVersion ?? '-'} · ${data.people.length} people',
                              key: const Key('home_content_version'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.secondaryText,
                                fontFamily: 'Noto Sans',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatCurrentTime(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ],
                  ),
                ),

                // 4 CARDS: 2x2 Balanced Grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 6, 28, 14),
                    child: Row(
                      children: [
                        // Left Column: Play & Today
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: _buildPlayCard()),
                              const SizedBox(height: 18),
                              Expanded(child: _buildTodayCard(data)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        // Right Column: My People & Call
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: _buildMyPeopleCard(data)),
                              const SizedBox(height: 18),
                              Expanded(child: _buildCallCard(data)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // BOTTOM BAR: Ground strip with overlapping center microphone
                _buildBottomBar(),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CARD 1: Play (Terracotta)
  // ─────────────────────────────────────────────
  Widget _buildPlayCard() {
    return InkWell(
      key: const Key('play_market_basket'),
      onTap: _openGamesMenu,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.terracotta, width: 3),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Center(
                child: CustomPaint(
                  size: const Size(120, 68),
                  painter: const _BasketPainter(),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.terracotta,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Play',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onColor,
                  letterSpacing: 0.5,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CARD 2: My People (Indigo)
  // ─────────────────────────────────────────────
  Widget _buildMyPeopleCard(_HomeData data) {
    return InkWell(
      onTap: () => _onMyPeopleTapped(data),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.indigo,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.indigoDark, width: 3),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE9DFCE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 54,
                    color: AppColors.indigoDark,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: const Text(
                'My People',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onColor,
                  letterSpacing: 0.5,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CARD 3: Today (Marigold)
  // ─────────────────────────────────────────────
  Widget _buildTodayCard(_HomeData data) {
    return InkWell(
      onTap: () => _onTodayTapped(data),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.marigold, width: 3),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(120, 52),
                      painter: const _LandscapePainter(),
                    ),
                    if (data.routineItems.isEmpty)
                      const Text(
                        'No routine yet',
                        key: Key('routine_empty'),
                        style: TextStyle(
                            fontSize: 11, color: AppColors.secondaryText),
                      )
                    else
                      for (final item in data.routineItems)
                        Container(
                          key: Key('routine_${item.id}'),
                          margin: const EdgeInsets.only(top: 1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatMinutes(item.timeMin),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item.labelKey,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                    if (data.medications.isEmpty)
                      const Text(
                        'No medicines yet',
                        key: Key('medications_empty'),
                        style: TextStyle(
                            fontSize: 11, color: AppColors.secondaryText),
                      )
                    else
                      for (final medication in data.medications)
                        Container(
                          key: Key('medication_${medication.id}'),
                          margin: const EdgeInsets.only(top: 1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${medication.name} · ${medication.dose}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatMinutes(medication.chosenTimeMin),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.marigold,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Today',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                  letterSpacing: 0.5,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CARD 4: Call Bina (Leaf Green)
  // ─────────────────────────────────────────────
  Widget _buildCallCard(_HomeData data) {
    final contact = data.primaryContactName;
    return InkWell(
      onTap: () => _onCallTapped(data),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.leafGreen, width: 3),
        ),
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Center(
                child: Transform.rotate(
                  angle: -0.4,
                  child: const Icon(
                    Icons.phone_rounded,
                    size: 58,
                    color: Color(0xFF386144),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.leafGreen,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              alignment: Alignment.center,
              child: Text(
                'Call $contact',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onColor,
                  letterSpacing: 0.5,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BOTTOM STRIP & CENTER MICROPHONE
  // ─────────────────────────────────────────────
  Widget _buildBottomBar() {
    return SizedBox(
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            top: 14,
            child: Container(
              color: AppColors.bottomStrip,
            ),
          ),
          Positioned(
            top: -12,
            child: GestureDetector(
              onTap: _onMicTapped,
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF8),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryText, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic_none_rounded,
                  size: 36,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _HomeData {
  const _HomeData({
    required this.elderName,
    required this.primaryContactName,
    required this.contentVersion,
    required this.medications,
    required this.routineItems,
    required this.people,
  });

  final String elderName;
  final String primaryContactName;
  final String? contentVersion;
  final List<Medication> medications;
  final List<RoutineItem> routineItems;
  final List<PeopleData> people;
}

/// Custom painter for the Market Basket icon on the Play card.
class _BasketPainter extends CustomPainter {
  const _BasketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = const Color(0xFF8D4B34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Fruits behind basket rim
    fillPaint.color = const Color(0xFFC74B39);
    canvas.drawCircle(Offset(cx - 18, cy - 8), 13, fillPaint);
    canvas.drawCircle(Offset(cx - 18, cy - 8), 13, strokePaint);

    fillPaint.color = const Color(0xFF3E6F4B);
    canvas.drawCircle(Offset(cx + 1, cy - 10), 12, fillPaint);
    canvas.drawCircle(Offset(cx + 1, cy - 10), 12, strokePaint);

    fillPaint.color = const Color(0xFFDE9928);
    canvas.drawCircle(Offset(cx + 18, cy - 7), 13, fillPaint);
    canvas.drawCircle(Offset(cx + 18, cy - 7), 13, strokePaint);

    // Woven basket trapezoid
    final basketPath = Path()
      ..moveTo(cx - 30, cy + 2)
      ..lineTo(cx + 30, cy + 2)
      ..lineTo(cx + 22, cy + 26)
      ..lineTo(cx - 22, cy + 26)
      ..close();

    fillPaint.color = const Color(0xFFFFFDF8);
    canvas.drawPath(basketPath, fillPaint);
    canvas.drawPath(basketPath, strokePaint);

    // Weave lines
    canvas.drawLine(
        Offset(cx - 27, cy + 10), Offset(cx + 27, cy + 10), strokePaint);
    canvas.drawLine(
        Offset(cx - 25, cy + 18), Offset(cx + 25, cy + 18), strokePaint);
    canvas.drawLine(
        Offset(cx - 14, cy + 2), Offset(cx - 11, cy + 26), strokePaint);
    canvas.drawLine(Offset(cx, cy + 2), Offset(cx, cy + 26), strokePaint);
    canvas.drawLine(
        Offset(cx + 14, cy + 2), Offset(cx + 11, cy + 26), strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for the sunrise over green hills on the Today card.
class _LandscapePainter extends CustomPainter {
  const _LandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final sunPaint = Paint()
      ..color = const Color(0xFFDE9928)
      ..style = PaintingStyle.fill;

    final rayPaint = Paint()
      ..color = const Color(0xFFDE9928)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final sunCenter = Offset(cx, cy - 6);
    canvas.drawCircle(sunCenter, 12, sunPaint);

    const rayAngles = [-2.4, -1.8, -1.57, -1.3, -0.7];
    for (final angle in rayAngles) {
      final p1 = Offset(
          sunCenter.dx + 16 * cos(angle), sunCenter.dy + 16 * sin(angle));
      final p2 = Offset(
          sunCenter.dx + 21 * cos(angle), sunCenter.dy + 21 * sin(angle));
      canvas.drawLine(p1, p2, rayPaint);
    }

    final hillPaint = Paint()
      ..color = const Color(0xFF386144)
      ..style = PaintingStyle.fill;

    final hillStroke = Paint()
      ..color = const Color(0xFF2B4732)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final hillPath = Path()
      ..moveTo(cx - 45, cy + 18)
      ..quadraticBezierTo(cx - 30, cy + 6, cx - 12, cy + 14)
      ..quadraticBezierTo(cx + 15, cy + 6, cx + 45, cy + 18)
      ..lineTo(cx + 45, cy + 22)
      ..lineTo(cx - 45, cy + 22)
      ..close();

    canvas.drawPath(hillPath, hillPaint);
    canvas.drawPath(hillPath, hillStroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A local file, or null when the media never downloaded. Screens skip missing
/// media silently (APP-BUILD-SPEC.md §6).
File? existingFile(String? path) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  return file.existsSync() ? file : null;
}
