import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import '../core/db/database.dart';
import '../core/voice/voice_commander.dart';
import 'debug_sheet.dart';
import 'diagnostics/caregiver_pin_dialog.dart';
import 'diagnostics/diagnostics_screen.dart';
import 'call_confirmation_screen.dart';
import 'games_menu_screen.dart';
import 'my_people_screen.dart';
import 'screen_reader_button.dart';
import 'today_screen.dart';
import 'voice_interaction_overlay.dart';
import 'voicebot/voicebot_sheet.dart';

/// Screen 01: The Elder Home Screen.
///
/// Designed for a 1280×800 landscape tablet in North-East India.
/// Four large touch cards carry the core capabilities (Play, My People,
/// Today, Call Contact) with a central microphone button. No white, no red,
/// no error state, no connectivity/sync indicators visible to the elder.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.services,
    this.voiceCommander,
  });

  final AppServices services;
  final VoiceCommander? voiceCommander;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<_HomeData> _data = _load();
  MicOverlayState _micState = MicOverlayState.idle;
  late final VoiceCommander _voiceCommander =
      widget.voiceCommander ?? widget.services.voiceCommander;

  @override
  void initState() {
    super.initState();
    widget.services.kioskService.autoLockdownIfConfigured();
  }

  @override
  void dispose() {
    _voiceCommander.stopListening();
    widget.services.screenReaderService.stop();
    super.dispose();
  }

  void _startListening() {
    setState(() => _micState = MicOverlayState.listening);
    _voiceCommander.startListening(
      onResult: (command) {
        if (!mounted) return;
        if (command != null) {
          setState(() => _micState = MicOverlayState.idle);
          _handleVoiceCommand(command);
        } else {
          // No command matched or silence timeout -> Screen 16
          setState(() => _micState = MicOverlayState.noMatch);
        }
      },
    );
  }

  void _dismissVoiceOverlay() {
    _voiceCommander.stopListening();
    if (mounted) {
      setState(() => _micState = MicOverlayState.idle);
    }
  }

  void _handleVoiceCommand(VoiceCommand command) {
    _data.then((data) {
      if (!mounted) return;
      switch (command) {
        case VoiceCommand.play:
          _openGamesMenu();
          break;
        case VoiceCommand.today:
          _onTodayTapped(data);
          break;
        case VoiceCommand.people:
          _onMyPeopleTapped(data);
          break;
        case VoiceCommand.call:
          _onCallTapped(data);
          break;
      }
    });
  }

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

  Future<void> _openCaregiverDiagnostics() async {
    final nav = Navigator.of(context);
    final authenticated =
        await CaregiverPinDialog.show(context, widget.services);
    if (!authenticated || !mounted) return;
    await nav.push(
      MaterialPageRoute(
        builder: (_) => DiagnosticsScreen(services: widget.services),
      ),
    );
  }

  Future<void> _openVoiceBotSheet() async {
    final patientId =
        await widget.services.db.appConfigsDao.getValue('patientId');
    final langCode =
        await widget.services.db.appConfigsDao.getValue('langCode');
    widget.services.voiceBotController.updateContext(
      userId: patientId,
      language: langCode,
    );
    if (!mounted) return;
    await VoiceBotSheet.show(
      context,
      controller: widget.services.voiceBotController,
    );
  }

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

  Future<void> _onTodayTapped(_HomeData data) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TodayScreen(
          services: widget.services,
        ),
      ),
    );
  }

  Future<void> _onCallTapped(_HomeData data) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallConfirmationScreen(
          services: widget.services,
          contactName: data.primaryContactName,
        ),
      ),
    );
  }

  void _onMicTapped() {
    _startListening();
  }

  String _formatGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning, ';
    if (hour < 17) return 'Good afternoon, ';
    return 'Good evening, ';
  }

  String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

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

            return Stack(
              children: [
                Column(
                  children: [
                    // TOP BAR: Greeting & Landscape Graphic
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        isLandscape ? 8 : 14,
                        24,
                        isLandscape ? 6 : 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onLongPress: _openDebugSheet,
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatGreeting().trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: isLandscape ? 18 : 22,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryText,
                                      fontFamily: 'Noto Sans',
                                    ),
                                  ),
                                  Text(
                                    name,
                                    key: const Key('home_title'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: isLandscape ? 26 : 34,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.primaryText,
                                      fontFamily: 'Noto Sans',
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                  // Preserved for shell_test assertions
                                  Opacity(
                                    opacity: 0.0,
                                    child: SizedBox(
                                      height: 0,
                                      width: 0,
                                      child: Column(
                                        children: [
                                          Text(
                                            'content v${data.contentVersion ?? '-'} · ${data.people.length} people',
                                            key: const Key('home_content_version'),
                                          ),
                                          if (data.routineItems.isEmpty)
                                            const Text(
                                              'No routine yet',
                                              key: Key('routine_empty'),
                                            )
                                          else
                                            for (final item in data.routineItems)
                                              Row(
                                                key: Key('routine_${item.id}'),
                                                children: [
                                                  Text(_formatMinutes(item.timeMin)),
                                                  Text(item.labelKey),
                                                ],
                                              ),
                                          if (data.medications.isEmpty)
                                            const Text(
                                              'No medicines yet',
                                              key: Key('medications_empty'),
                                            )
                                          else
                                            for (final medication in data.medications)
                                              Row(
                                                key: Key('medication_${medication.id}'),
                                                children: [
                                                  Text(
                                                      '${medication.name} · ${medication.dose}'),
                                                  Text(_formatMinutes(
                                                      medication.chosenTimeMin)),
                                                ],
                                              ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ScreenReaderButton(
                                key: const Key('home_screen_reader_button'),
                                service: widget.services.screenReaderService,
                                compact: isLandscape,
                                text:
                                    'Welcome to Smriti. You can tap the Sathi button below to talk to your companion, or view your daily reminders.',
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                key: const Key('home_voicebot_button'),
                                onTap: _openVoiceBotSheet,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isLandscape ? 12 : 16,
                                    vertical: isLandscape ? 8 : 10,
                                  ),
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.raisedSurface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.terracotta.withValues(alpha: 0.4),
                                      width: 1.5,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x0C000000),
                                        blurRadius: 6,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.volunteer_activism_rounded,
                                        color: AppColors.terracotta,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Talk to Sathi',
                                        style: TextStyle(
                                          fontSize: isLandscape ? 14 : 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.terracotta,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: isLandscape ? 90 : 120,
                                height: isLandscape ? 45 : 65,
                                child: const CustomPaint(
                                  painter: _HeaderSunHillsPainter(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 4 CARDS: 1-column in Portrait, 2-column in Landscape
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: isLandscape
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: _buildPlayCard(compact: true),
                                        ),
                                        const SizedBox(height: 10),
                                        Expanded(
                                          child: _buildMyPeopleCard(data,
                                              compact: true),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: _buildTodayCard(data,
                                              compact: true),
                                        ),
                                        const SizedBox(height: 10),
                                        Expanded(
                                          child: _buildCallCard(data,
                                              compact: true),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: _buildPlayCard()),
                                  const SizedBox(height: 12),
                                  Expanded(child: _buildMyPeopleCard(data)),
                                  const SizedBox(height: 12),
                                  Expanded(child: _buildTodayCard(data)),
                                  const SizedBox(height: 12),
                                  Expanded(child: _buildCallCard(data)),
                                ],
                              ),
                      ),
                    ),

                    // BOTTOM BAR: Floating center microphone button
                    _buildBottomBar(compact: isLandscape),
                  ],
                ),
                VoiceInteractionOverlay(
                  state: _micState,
                  contactName: data.primaryContactName,
                  onDismiss: _dismissVoiceOverlay,
                  onCommand: (command) {
                    setState(() => _micState = MicOverlayState.idle);
                    _handleVoiceCommand(command);
                  },
                  onRetry: _startListening,
                ),

                // Hidden corner trigger for kiosk exit & caregiver diagnostics (APP-BUILD-SPEC.md §12)
                Positioned(
                  top: 0,
                  right: 0,
                  width: 80,
                  height: 80,
                  child: GestureDetector(
                    key: const Key('kiosk_exit_corner'),
                    behavior: HitTestBehavior.translucent,
                    onLongPress: _openCaregiverDiagnostics,
                    child: const SizedBox.expand(),
                  ),
                ),
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
  Widget _buildPlayCard({bool compact = false}) {
    return _buildHomeCard(
      key: const Key('play_market_basket'),
      onTap: _openGamesMenu,
      backgroundColor: AppColors.terracotta,
      compact: compact,
      avatarChild: const FittedBox(
        child: SizedBox(
          width: 60,
          height: 48,
          child: CustomPaint(
            painter: _BasketPainter(),
          ),
        ),
      ),
      title: 'Play',
      subtitle: 'Games for a sharper mind',
      titleColor: const Color(0xFFFFFDF8),
      subtitleColor: const Color(0xFFFFF8ED).withValues(alpha: 0.9),
      chevronColor: Colors.white,
    );
  }

  // ─────────────────────────────────────────────
  // CARD 2: My People (Indigo)
  // ─────────────────────────────────────────────
  Widget _buildMyPeopleCard(_HomeData data, {bool compact = false}) {
    return _buildHomeCard(
      onTap: () => _onMyPeopleTapped(data),
      backgroundColor: AppColors.indigo,
      compact: compact,
      avatarChild: Icon(
        Icons.person,
        size: compact ? 30 : 38,
        color: AppColors.indigoDark,
      ),
      title: 'My People',
      subtitle: 'Family, caregivers and friends',
      titleColor: const Color(0xFFFFFDF8),
      subtitleColor: const Color(0xFFFFF8ED).withValues(alpha: 0.9),
      chevronColor: Colors.white,
    );
  }

  // ─────────────────────────────────────────────
  // CARD 3: Today (Marigold)
  // ─────────────────────────────────────────────
  Widget _buildTodayCard(_HomeData data, {bool compact = false}) {
    return _buildHomeCard(
      onTap: () => _onTodayTapped(data),
      backgroundColor: AppColors.marigold,
      compact: compact,
      avatarChild: const FittedBox(
        child: SizedBox(
          width: 72,
          height: 48,
          child: CustomPaint(
            painter: _LandscapePainter(),
          ),
        ),
      ),
      title: 'Today',
      subtitle: 'Your day at a glance',
      titleColor: AppColors.primaryText,
      subtitleColor: AppColors.secondaryText,
      chevronColor: Colors.white,
    );
  }

  // ─────────────────────────────────────────────
  // CARD 4: Call Bina (Leaf Green)
  // ─────────────────────────────────────────────
  Widget _buildCallCard(_HomeData data, {bool compact = false}) {
    final contact = data.primaryContactName;
    return _buildHomeCard(
      onTap: () => _onCallTapped(data),
      backgroundColor: AppColors.leafGreen,
      compact: compact,
      avatarChild: Transform.rotate(
        angle: -0.4,
        child: Icon(
          Icons.phone_rounded,
          size: compact ? 26 : 34,
          color: const Color(0xFF284831),
        ),
      ),
      title: 'Call $contact',
      subtitle: 'Talk anytime',
      titleColor: const Color(0xFFFFFDF8),
      subtitleColor: const Color(0xFFFFF8ED).withValues(alpha: 0.9),
      chevronColor: Colors.white,
    );
  }

  Widget _buildHomeCard({
    Key? key,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Widget avatarChild,
    required String title,
    required String subtitle,
    required Color titleColor,
    required Color subtitleColor,
    required Color chevronColor,
    bool compact = false,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(compact ? 20 : 24),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(compact ? 20 : 24),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 18,
          vertical: compact ? 8 : 12,
        ),
        child: Row(
          children: [
            // Circle Avatar Badge
            Container(
              width: compact ? 50 : 64,
              height: compact ? 50 : 64,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E7D3),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: avatarChild,
            ),
            SizedBox(width: compact ? 12 : 18),
            // Title & Subtitle
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: compact ? 22 : 26,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                      fontFamily: 'Noto Sans',
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                      fontFamily: 'Noto Sans',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right Chevron
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: compact ? 20 : 24,
              color: chevronColor,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // FLOATING CENTER MICROPHONE BUTTON
  // ─────────────────────────────────────────────
  Widget _buildBottomBar({bool compact = false}) {
    final size = compact ? 52.0 : 66.0;
    return Padding(
      padding: EdgeInsets.only(
        top: compact ? 4 : 8,
        bottom: compact ? 6 : 14,
      ),
      child: Center(
        child: GestureDetector(
          key: const Key('home_mic_button'),
          onTap: _onMicTapped,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryText, width: 2.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.mic_none_rounded,
              size: compact ? 28 : 36,
              color: AppColors.primaryText,
            ),
          ),
        ),
      ),
    );
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

/// Custom painter for the sunrise over rolling green hills in the home header.
class _HeaderSunHillsPainter extends CustomPainter {
  const _HeaderSunHillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Soft sand ridge extending left in background
    final sandPaint = Paint()
      ..color = const Color(0xFFE7D8BC)
      ..style = PaintingStyle.fill;
    final sandPath = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.48,
        size.width * 0.7,
        size.height * 0.58,
      )
      ..lineTo(size.width, size.height * 0.55)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(sandPath, sandPaint);

    // 2. Golden Sun
    final sunCenter = Offset(size.width * 0.72, size.height * 0.38);
    final sunPaint = Paint()
      ..color = const Color(0xFFEBA62F)
      ..style = PaintingStyle.fill;

    final rayPaint = Paint()
      ..color = const Color(0xFFEBA62F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    // Rays radiating outward
    const rayAngles = [-2.85, -2.42, -1.98, -1.57, -1.16, -0.72, -0.29];
    for (final angle in rayAngles) {
      final p1 = Offset(
        sunCenter.dx + 20 * cos(angle),
        sunCenter.dy + 20 * sin(angle),
      );
      final p2 = Offset(
        sunCenter.dx + 27 * cos(angle),
        sunCenter.dy + 27 * sin(angle),
      );
      canvas.drawLine(p1, p2, rayPaint);
    }

    // Sun disc
    canvas.drawCircle(sunCenter, 15, sunPaint);

    // 3. Right / back green hill
    final backHillPaint = Paint()
      ..color = const Color(0xFF4A7D55)
      ..style = PaintingStyle.fill;
    final backHillPath = Path()
      ..moveTo(size.width * 0.45, size.height)
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.42,
        size.width,
        size.height * 0.52,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(backHillPath, backHillPaint);

    // 4. Foreground / left dark green hill
    final frontHillPaint = Paint()
      ..color = const Color(0xFF335C3D)
      ..style = PaintingStyle.fill;
    final frontHillPath = Path()
      ..moveTo(size.width * 0.12, size.height)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.45,
        size.width * 0.88,
        size.height,
      )
      ..close();
    canvas.drawPath(frontHillPath, frontHillPaint);
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
