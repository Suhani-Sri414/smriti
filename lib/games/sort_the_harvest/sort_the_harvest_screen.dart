import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core/app_services.dart';
import '../../screens/session_end_screen.dart';
import '../../ui/widgets/rest_card_dialog.dart';
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
    progressionService: widget.services.progressionService,
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

    Future.delayed(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final restState = await widget.services.progressionRepo.getRestState();
      if (!mounted) return;
      if (restState.shouldRest()) {
        final canContinue = await maybeShowRestCardDialog(
          context,
          progressionService: widget.services.progressionService,
        );
        if (!canContinue && mounted) {
          Navigator.of(context).pop();
          return;
        }
      }
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

    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final isCompact = media.size.shortestSide < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF261D18),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 14 : 20,
                isCompact ? 8 : 12,
                isCompact ? 14 : 20,
                isCompact ? 6 : 8,
              ),
              child: Row(
                children: [
                  // Back button
                  InkWell(
                    key: const Key('harvest_back_button'),
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 12 : 16,
                        vertical: isCompact ? 6 : 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFD6CDB8),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: isCompact ? 22 : 24,
                            color: AppColors.primaryText,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Home',
                            style: TextStyle(
                              fontSize: isCompact ? 16 : 18,
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'Sort the Harvest · $_trialsDone sorted',
                            style: TextStyle(
                              fontSize: isCompact ? 19 : 22,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFF5EFE6),
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(width: isCompact ? 16 : 80),
                ],
              ),
            ),

            // Main Play Area
            Expanded(
              child: Container(
                margin: EdgeInsets.fromLTRB(
                  isCompact ? 14 : 20,
                  0,
                  isCompact ? 14 : 20,
                  isCompact ? 12 : 16,
                ),
                padding: EdgeInsets.all(isCompact ? 12 : 20),
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
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left side: Instruction, Center Crop, feedback
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Which basket does this harvest belong to?',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF261D18),
                                      fontFamily: 'Noto Sans',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _buildCropCard(crop, isCompact: isCompact),
                                ),
                                if (_feedbackMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      _feedbackMessage!,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF388E3C),
                                        fontFamily: 'Noto Sans',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(width: isCompact ? 12 : 20),
                          // Right side: Trays vertically
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                for (int i = 0; i < trays.length; i++)
                                  _buildTrayCard(
                                    trays[i],
                                    i,
                                    isCompact: isCompact,
                                    isRowLayout: true,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
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
                            child: _buildCropCard(crop, isCompact: isCompact),
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
                                  _buildTrayCard(
                                    trays[i],
                                    i,
                                    isCompact: isCompact,
                                    isRowLayout: false,
                                  ),
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

  Widget _buildCropCard(SortCrop crop, {required bool isCompact}) {
    return Center(
      child: Container(
        key: Key('crop_card_${crop.id}'),
        constraints: BoxConstraints(
          maxWidth: isCompact ? 220 : 280,
          maxHeight: isCompact ? 180 : 240,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 16 : 20,
          vertical: isCompact ? 10 : 16,
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
                width: isCompact ? 64 : 80,
                height: isCompact ? 64 : 80,
                decoration: BoxDecoration(
                  color: crop.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  crop.icon,
                  size: isCompact ? 40 : 52,
                  color: crop.color,
                ),
              ),
              SizedBox(height: isCompact ? 6 : 10),
              Text(
                crop.name,
                style: TextStyle(
                  fontSize: isCompact ? 22 : 26,
                  fontWeight: FontWeight.w800,
                  color: crop.color,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrayCard(
    SortTray tray,
    int index, {
    required bool isCompact,
    required bool isRowLayout,
  }) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isRowLayout ? (isCompact ? 4 : 8) : (isCompact ? 6 : 10),
          vertical: isRowLayout ? (isCompact ? 4 : 6) : (isCompact ? 4 : 6),
        ),
        child: InkWell(
          key: Key('sort_tray_$index'),
          onTap: () => _onTrayTapped(tray),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              color: tray.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: tray.color,
                width: 2.5,
              ),
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(isCompact ? 8 : 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: isRowLayout
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_basket_rounded,
                              size: isCompact ? 30 : 38,
                              color: tray.color,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tray.label,
                              style: TextStyle(
                                fontSize: isCompact ? 18 : 22,
                                fontWeight: FontWeight.w700,
                                color: tray.color,
                                fontFamily: 'Noto Sans',
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_basket_rounded,
                              size: isCompact ? 32 : 40,
                              color: tray.color,
                            ),
                            SizedBox(height: isCompact ? 4 : 8),
                            Text(
                              tray.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isCompact ? 16 : 20,
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
          ),
        ),
      ),
    );
  }
}
