import 'dart:async';
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import '../games/cognitive_game.dart';
import '../games/faces_of_my_family/faces_of_my_family_screen.dart';
import '../games/game_content_loader.dart';
import '../games/ghost_hand.dart';
import '../games/market_basket/market_basket_screen.dart';
import '../games/sort_the_harvest/sort_the_harvest_screen.dart';
import '../games/sounds_of_home/sounds_of_home_screen.dart';

/// Screen 03: Game host — ghost demo.
///
/// Designed for a 1280×800 landscape tablet in North-East India.
/// Specification (Prototype Board 03):
/// "Before any round, a ghost hand plays one move so the rule is never explained in words."
///
/// Key Invariants:
/// 1. Non-verbal instruction: A translucent ghost hand traces the correct
///    demonstration gesture so the elder learns by watching rather than reading.
/// 2. Replay tracking: The elder can tap "Watch again" as many times as desired.
///    Each replay increments `demoReplays` on the session row in SQLite.
/// 3. Zero shame (AGENTS.md rule 11): Warm, respectful visual register with no
///    hurry, no error indicators, and equal emphasis on taking time.
class GhostDemoScreen extends StatefulWidget {
  const GhostDemoScreen({
    super.key,
    required this.services,
    this.gameId = 'market_basket',
    this.content,
    this.sessionId,
    this.onStartGame,
    this.onBack,
    this.autoStartDemo = true,
    this.demoStepDuration = const Duration(milliseconds: 650),
  });

  final AppServices services;
  final String gameId;
  final GameContent? content;
  final String? sessionId;
  final VoidCallback? onStartGame;
  final VoidCallback? onBack;
  final bool autoStartDemo;
  final Duration demoStepDuration;

  @override
  State<GhostDemoScreen> createState() => _GhostDemoScreenState();
}

class _GhostDemoScreenState extends State<GhostDemoScreen> {
  late final GhostHandController _ghostController;
  late String _currentGameId;
  GameContent? _gameContent;
  int _replaysCount = 0;
  bool _isLoadingContent = true;

  @override
  void initState() {
    super.initState();
    _currentGameId = widget.gameId;
    _ghostController = GhostHandController(stepDuration: widget.demoStepDuration);
    _initContentAndStart();
  }

  @override
  void dispose() {
    _ghostController.dispose();
    super.dispose();
  }

  Future<void> _initContentAndStart() async {
    if (widget.content != null) {
      _gameContent = widget.content;
      _isLoadingContent = false;
    } else {
      _gameContent = await loadMockGameContent();
      _isLoadingContent = false;
    }

    if (mounted) {
      setState(() {});
      if (widget.autoStartDemo) {
        // Allow layout to settle before launching initial ghost demonstration
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _playCurrentDemo();
          }
        });
      }
    }
  }

  List<Offset> _getPathForGame(String id) {
    switch (id) {
      case 'sort_the_harvest':
        return const [
          Offset(0.5, 0.74), // center crop card in hand
          Offset(0.35, 0.32), // left woven sorting basket
        ];
      case 'faces_of_my_family':
        return const [
          Offset(0.5, 0.30), // prompt photo
          Offset(0.32, 0.74), // matching family name tile
        ];
      case 'sounds_of_home':
        return const [
          Offset(0.5, 0.34), // speaker bell pulsing
          Offset(0.35, 0.72), // matching sound illustration card
        ];
      case 'market_basket':
      default:
        return const [
          Offset(0.5, 0.22), // shopping list
          Offset(0.32, 0.68), // first target good on mat
          Offset(0.68, 0.68), // second target good on mat
        ];
    }
  }

  Future<void> _playCurrentDemo() async {
    final path = _getPathForGame(_currentGameId);
    await _ghostController.play(path);
  }

  Future<void> _onWatchAgainPressed() async {
    setState(() {
      _replaysCount++;
    });

    final sId = widget.sessionId;
    if (sId != null && sId.isNotEmpty) {
      await widget.services.eventRepo.bumpDemoReplays(sId);
    }

    await _playCurrentDemo();
  }

  void _onPlayPressed() {
    if (widget.onStartGame != null) {
      widget.onStartGame!();
      return;
    }

    final content = _gameContent;
    if (content == null) return;

    Widget targetScreen;
    switch (_currentGameId) {
      case 'sort_the_harvest':
        targetScreen = SortTheHarvestScreen(
          services: widget.services,
          content: content,
        );
        break;
      case 'faces_of_my_family':
        targetScreen = FacesOfMyFamilyScreen(
          services: widget.services,
          content: content,
        );
        break;
      case 'sounds_of_home':
        targetScreen = SoundsOfHomeScreen(
          services: widget.services,
          content: content,
        );
        break;
      case 'market_basket':
      default:
        targetScreen = MarketBasketScreen(
          services: widget.services,
          content: content,
        );
        break;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => targetScreen),
    );
  }

  void _onBackPressed() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).pop();
    }
  }

  String _formatCurrentTime() {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _gameTitle(String id) {
    switch (id) {
      case 'sort_the_harvest':
        return 'Sort the Harvest';
      case 'faces_of_my_family':
        return 'Faces of My Family';
      case 'sounds_of_home':
        return 'Sounds of Home';
      case 'market_basket':
      default:
        return 'Market Basket';
    }
  }

  String _gameDomainTag(String id) {
    switch (id) {
      case 'sort_the_harvest':
        return 'Executive • Set-Shifting';
      case 'faces_of_my_family':
        return 'Memory • Family Recognition';
      case 'sounds_of_home':
        return 'Auditory • Sound Matching';
      case 'market_basket':
      default:
        return 'Memory • Shopping Span';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR: Screen 03 header, title, back button, clock
            _buildTopBar(context),

            // MAIN STAGE: Live game preview canvas with animated Ghost Hand
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF8),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.border, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryText.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Stage layout for currently selected game
                      Positioned.fill(
                        child: _isLoadingContent
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.terracotta,
                                ),
                              )
                            : _buildStagePreview(_currentGameId),
                      ),

                      // Non-verbal guidance banner ("Watch first")
                      Positioned(
                        top: 16,
                        left: 20,
                        right: 20,
                        child: Center(
                          child: _buildGuidanceBanner(),
                        ),
                      ),

                      // High-fidelity vector Ghost Hand overlay
                      Positioned.fill(
                        child: GhostHandOverlay(
                          key: const Key('ghost_demo_overlay'),
                          controller: _ghostController,
                          showTrail: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // BOTTOM BAR: "Watch again" replay action & "Play" / "I'm ready" action
            _buildBottomControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 24, 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          width: 1220,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Back button
              InkWell(
                key: const Key('ghost_demo_back_button'),
                onTap: _onBackPressed,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primaryText, width: 2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded,
                          size: 26, color: AppColors.primaryText),
                      SizedBox(width: 8),
                      Text(
                        'Games',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Center Screen 03 identity & game title badge
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '03',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD99A2B),
                      letterSpacing: 0.1,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Game host — ghost demo',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.wovenMat,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.6), width: 1.5),
                    ),
                    child: Text(
                      _gameTitle(_currentGameId),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText,
                        fontFamily: 'Noto Sans',
                      ),
                    ),
                  ),
                ],
              ),

              // Clock display
              Text(
                _formatCurrentTime(),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidanceBanner() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 820),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD99A2B), width: 2.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD99A2B).withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFFBF4E4),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.visibility_rounded,
              color: Color(0xFF8A5A00),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Watch first',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                    fontFamily: 'Noto Sans',
                  ),
                ),
                Text(
                  'Before any round, a ghost hand plays one move so the rule is never explained in words.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.secondaryText,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStagePreview(String gameId) {
    switch (gameId) {
      case 'sort_the_harvest':
        return _buildSortTheHarvestStage();
      case 'faces_of_my_family':
        return _buildFacesStage();
      case 'sounds_of_home':
        return _buildSoundsStage();
      case 'market_basket':
      default:
        return _buildMarketBasketStage();
    }
  }

  /// Screen 04 preview stage: Woven mat with shopping prompt & market goods
  Widget _buildMarketBasketStage() {
    return Container(
      color: const Color(0xFFFAF7F0),
      padding: const EdgeInsets.fromLTRB(36, 68, 36, 20),
      child: Column(
        children: [
          // Shopping target card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD99A2B), width: 2),
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_basket_rounded,
                      color: Color(0xFF8A5A00), size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Market Basket — Remember these goods',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Woven mat with items
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.wovenMat,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: SizedBox(
                  width: 820,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildMarketItemCard('Assam Tea', Icons.emoji_food_beverage_rounded,
                          const Color(0xFF386641), isTarget: true),
                      _buildMarketItemCard('Fresh Ginger', Icons.grass_rounded,
                          const Color(0xFFD4A373), isTarget: false),
                      _buildMarketItemCard('Aromatic Rice', Icons.rice_bowl_rounded,
                          const Color(0xFFC85A32), isTarget: true),
                      _buildMarketItemCard('Papaya', Icons.spa_rounded,
                          const Color(0xFFE07A5F), isTarget: false),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketItemCard(
      String name, IconData icon, Color tint, {required bool isTarget}) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTarget ? const Color(0xFFD99A2B) : AppColors.border,
          width: isTarget ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: tint),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
              fontFamily: 'Noto Sans',
            ),
          ),
        ],
      ),
    );
  }

  /// Screen 07 preview stage: Two sorting trays and harvest card
  Widget _buildSortTheHarvestStage() {
    return Container(
      color: const Color(0xFFFAF7F0),
      padding: const EdgeInsets.fromLTRB(40, 72, 40, 20),
      child: Column(
        children: [
          // Two sorting trays
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 720,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSortingTray('Left Tray: Greens & Leaves', Icons.eco_rounded,
                      const Color(0xFF436048), isLeft: true),
                  _buildSortingTray('Right Tray: Roots & Tubers',
                      Icons.nature_rounded, const Color(0xFF9E5738), isLeft: false),
                ],
              ),
            ),
          ),
          const Spacer(),

          // Card in hand ready to sort
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD99A2B), width: 2.5),
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.eco_rounded, color: Color(0xFF436048), size: 36),
                  SizedBox(width: 12),
                  Text(
                    'Bitter Gourd',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildSortingTray(
      String title, IconData icon, Color color, {required bool isLeft}) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.wovenMat,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLeft ? const Color(0xFFD99A2B) : AppColors.border,
          width: isLeft ? 3.0 : 2.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
              fontFamily: 'Noto Sans',
            ),
          ),
        ],
      ),
    );
  }

  /// Screen 06 preview stage: Family photo & 3 name tiles
  Widget _buildFacesStage() {
    return Container(
      color: const Color(0xFFFAF7F0),
      padding: const EdgeInsets.fromLTRB(40, 72, 40, 20),
      child: Column(
        children: [
          // Photo card
          Container(
            width: 200,
            height: 140,
            decoration: BoxDecoration(
              color: const Color(0xFFE9E3D5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border, width: 2),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_rounded, size: 64, color: AppColors.terracotta),
                SizedBox(height: 6),
                Text(
                  'Who is this?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryText,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),

          // Three name tiles
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 720,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNameTile('Bina', isCorrect: true),
                  _buildNameTile('Pari', isCorrect: false),
                  _buildNameTile('Deepak', isCorrect: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildNameTile(String name, {required bool isCorrect}) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCorrect ? const Color(0xFFD99A2B) : AppColors.border,
          width: isCorrect ? 2.5 : 1.5,
        ),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryText,
          fontFamily: 'Noto Sans',
        ),
      ),
    );
  }

  /// Screen 08 preview stage: Pulsing sound speaker & sound cards
  Widget _buildSoundsStage() {
    return Container(
      color: const Color(0xFFFAF7F0),
      padding: const EdgeInsets.fromLTRB(40, 72, 40, 20),
      child: Column(
        children: [
          // Pulsing audio speaker
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD99A2B), width: 2.2),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.volume_up_rounded,
                    size: 40, color: Color(0xFF8A5A00)),
                SizedBox(width: 14),
                Text(
                  'Listen to the sound...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),

          // 3 sound options
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 720,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSoundCard('Temple Bell', Icons.notifications_active_rounded,
                      isTarget: true),
                  _buildSoundCard('Monsoon Rain', Icons.water_drop_rounded,
                      isTarget: false),
                  _buildSoundCard('Morning Hornbill', Icons.flutter_dash_rounded,
                      isTarget: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildSoundCard(String title, IconData icon, {required bool isTarget}) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isTarget ? const Color(0xFFD99A2B) : AppColors.border,
          width: isTarget ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.terracotta),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
              fontFamily: 'Noto Sans',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(
          width: 1220,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // "Watch again" button
              InkWell(
                key: const Key('ghost_demo_watch_again_button'),
                onTap: _onWatchAgainPressed,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 230, minHeight: 64),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD99A2B), width: 2.4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD99A2B).withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.replay_rounded,
                        size: 30,
                        color: Color(0xFF8A5A00),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Watch again',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A5A00),
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                          if (_replaysCount > 0)
                            Text(
                              'Watched $_replaysCount ${_replaysCount == 1 ? "time" : "times"}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.secondaryText,
                                fontFamily: 'Noto Sans',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Domain info pill
              Text(
                _gameDomainTag(_currentGameId),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryText,
                  fontFamily: 'Noto Sans',
                ),
              ),

              // "Play" / "I'm ready" button
              InkWell(
                key: const Key('ghost_demo_play_button'),
                onTap: _onPlayPressed,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 230, minHeight: 64),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.terracotta,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF9E3D1B), width: 2.2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.terracotta.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'I\'m ready',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                      SizedBox(width: 12),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 30,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
