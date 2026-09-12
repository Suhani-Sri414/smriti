import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core/app_services.dart';
import '../../screens/session_end_screen.dart';
import '../cognitive_game.dart';
import '../session_runner.dart';
import 'sort_the_harvest_game.dart';

/// Playable UI screen for Sort the Harvest (Screen 02 game 2).
///
/// Executive function / set-shifting card sorting game for the 1280×800 tablet.
/// The elder inspects the center produce card and taps the appropriate basket.
/// Adheres strictly to AGENTS.md rule 11: no red, no "wrong", neutral return
/// on incorrect sort.
class SortTheHarvestScreen extends StatefulWidget {
  const SortTheHarvestScreen({
    super.key,
    required this.services,
    required this.content,
  });

  final AppServices services;
  final GameContent content;

  @override
  State<SortTheHarvestScreen> createState() => _SortTheHarvestScreenState();
}

class _SortTheHarvestScreenState extends State<SortTheHarvestScreen> {
  late final SortTheHarvestGame _game = SortTheHarvestGame();
  late final SessionRunner _runner = SessionRunner(
    eventRepo: widget.services.eventRepo,
    abilityRepo: widget.services.abilityRepo,
    content: widget.content,
  );

  GameItem? _item;
  int _trialsDone = 0;
  DateTime? _shownAt;
  DateTime? _firstTouchAt;
  bool _isProcessing = false;
  String? _feedbackMessage;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _runner.end(completed: false);
    _game.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await _runner.start([_game]);
    await _nextItem();
  }

  Future<void> _nextItem() async {
    final item = await _runner.nextItem(_game);
    if (!mounted) return;

    if (item == null) {
      await _runner.end(completed: true);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SessionEndScreen(
              services: widget.services,
              gameTitle: 'Sort the Harvest',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _item = item;
      _shownAt = DateTime.now();
      _firstTouchAt = null;
      _isProcessing = false;
      _feedbackMessage = null;
    });
  }

  void _onTrayTapped(SortTray tray) {
    if (_isProcessing || _item == null) return;
    _isProcessing = true;
    _firstTouchAt ??= DateTime.now();

    final now = DateTime.now();
    final initiationMs =
        (_firstTouchAt ?? now).difference(_shownAt ?? now).inMilliseconds;
    final movementMs =
        now.difference(_firstTouchAt ?? now).inMilliseconds.clamp(50, 10000);

    final targetTray = _item!.payload['targetTray'] as SortTray;
    final isCorrect = tray.id == targetTray.id;

    _game.submitSort(
      item: _item!,
      chosenTrayId: tray.id,
      initiationMs: initiationMs,
      movementMs: movementMs,
    );

    setState(() {
      _trialsDone++;
      if (isCorrect) {
        _feedbackMessage = 'Well sorted!';
      }
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _nextItem();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_item == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF261D18),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE5A93C)),
        ),
      );
    }

    final crop = _item!.payload['crop'] as SortCrop;
    final trays = (_item!.payload['trays'] as List<Object?>).cast<SortTray>();

    return Scaffold(
      backgroundColor: const Color(0xFF261D18),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  // Back button
                  InkWell(
                    key: const Key('harvest_back_button'),
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFD6CDB8),
                          width: 1.5,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: 24,
                            color: AppColors.primaryText,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Home',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Title & score
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Sort the Harvest · $_trialsDone sorted',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF5EFE6),
                            fontFamily: 'Noto Sans',
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 80),
                ],
              ),
            ),

            // Main Play Area
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F2E7),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x25000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Instruction Banner
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Which basket does this harvest belong to?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF261D18),
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Center Crop Card
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Container(
                          key: Key('crop_card_${crop.id}'),
                          width: 260,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFDF8),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: crop.color.withValues(alpha: 0.6),
                              width: 3,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x15000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: crop.color.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    crop.icon,
                                    size: 52,
                                    color: crop.color,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  crop.name,
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: crop.color,
                                    fontFamily: 'Noto Sans',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (_feedbackMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _feedbackMessage!,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF388E3C),
                            fontFamily: 'Noto Sans',
                          ),
                        ),
                      ),

                    // Trays Row
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (int i = 0; i < trays.length; i++)
                            _buildTrayCard(trays[i], i),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrayCard(SortTray tray, int index) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: InkWell(
          key: Key('sort_tray_$index'),
          onTap: () => _onTrayTapped(tray),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: tray.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: tray.color,
                width: 2.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_basket_rounded,
                  size: 40,
                  color: tray.color,
                ),
                const SizedBox(height: 8),
                Text(
                  tray.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: tray.color,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
