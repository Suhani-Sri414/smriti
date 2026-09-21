import 'dart:async';
import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core/app_services.dart';
import '../../screens/session_end_screen.dart';
import '../../ui/widgets/rest_card_dialog.dart';
import '../cognitive_game.dart';
import '../session_runner.dart';
import 'market_basket_game.dart';

/// Screen for Market Basket (Screens 04 & 05).
///
/// Designed for a 1280×800 landscape tablet for an elderly person with cognitive decline.
/// Phase 1: Memorization ("Remember these") shows the shopping list on an elevated card.
/// Phase 2: Shopping ("Pick from the woven mat") shows six goods on a woven mat.
/// Screen 04: "Six goods on a woven mat. A wrong touch does nothing at all — it simply waits."
/// Screen 05: "Market Basket — correct. Marigold ring, spoken praise, and the prompt line becomes the confirmation."
/// Adheres strictly to AGENTS.md rule 11: no red, no "wrong", neutral return on incorrect response.
class MarketBasketScreen extends StatefulWidget {
  const MarketBasketScreen({
    super.key,
    required this.services,
    required this.content,
  });

  final AppServices services;
  final GameContent content;

  @override
  State<MarketBasketScreen> createState() => _MarketBasketScreenState();
}

class _MarketBasketScreenState extends State<MarketBasketScreen> {
  late final MarketBasketGame _game = MarketBasketGame();
  late final SessionRunner _runner = SessionRunner(
    eventRepo: widget.services.eventRepo,
    abilityRepo: widget.services.abilityRepo,
    progressionService: widget.services.progressionService,
    content: widget.content,
  );

  GameItem? _item;
  bool _showingList = true;
  final Set<String> _picked = {};
  int _trialsDone = 0;
  DateTime? _shownAt;
  DateTime? _firstTouchAt;
  bool _isProcessing = false;
  String? _feedbackMessage;
  bool? _isCorrect;
  String? _eliminatedId;
  Timer? _advanceTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
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
      // Six-minute cap spent or session completed.
      await _runner.end(completed: true);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SessionEndScreen(
              services: widget.services,
              gameTitle: 'Market Basket',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _item = item;
      _showingList = true;
      _picked.clear();
      _shownAt = DateTime.now();
      _firstTouchAt = null;
      _isProcessing = false;
      _feedbackMessage = null;
      _isCorrect = null;
      _eliminatedId = null;
    });
  }

  List<MarketItem> get _shelf =>
      (_item!.payload['shelf']! as List<Object?>).cast<MarketItem>();

  List<MarketItem> get _targets =>
      (_item!.payload['target']! as List<Object?>).cast<MarketItem>();

  Set<String> get _targetIds =>
      (_item!.context['targetIds']! as List<Object?>).cast<String>().toSet();

  void _hideList() {
    setState(() {
      _showingList = false;
      _shownAt = DateTime.now();
      _firstTouchAt = null;
      _feedbackMessage = null;
    });
  }

  void _toggle(String id) {
    if (_isProcessing) return;
    _firstTouchAt ??= DateTime.now();
    setState(() {
      if (!_picked.remove(id)) {
        _picked.add(id);
      }
    });
  }

  Future<void> _submit() async {
    final item = _item;
    if (item == null || _isProcessing) return;

    final now = DateTime.now();
    final firstTouch = _firstTouchAt ?? now;
    final initiationMs =
        firstTouch.difference(_shownAt ?? now).inMilliseconds.clamp(50, 30000);
    final movementMs =
        now.difference(firstTouch).inMilliseconds.clamp(10, 30000);

    final targetIds = _targetIds;
    final isCorrect =
        _picked.length == targetIds.length && _picked.containsAll(targetIds);

    setState(() {
      _isProcessing = true;
      _isCorrect = isCorrect;
      if (isCorrect) {
        // Screen 05: Marigold ring & spoken praise confirmation
        _feedbackMessage = 'Yes! Everything is in the basket!';
      } else {
        // Rule 11: Zero shame, gentle neutral guidance, no "wrong", no red
        _feedbackMessage = 'Let us check the basket together';
      }
    });

    _game.submit(
      item: item,
      chosenIds: _picked.toList(),
      initiationMs: initiationMs,
      movementMs: movementMs,
    );

    await _runner.feedback.first;
    if (!mounted) return;

    setState(() => _trialsDone++);

    _advanceTimer?.cancel();
    _advanceTimer = Timer(Duration(milliseconds: isCorrect ? 1400 : 1600), () async {
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

  void _onAskHint() {
    if (_isProcessing || _item == null) return;
    final hintLevel = _runner.escalateHint();
    final targets = _targets;

    setState(() {
      if (hintLevel == 1) {
        final categories = targets.map((t) => _categoryDisplayName(t.category)).toSet().toList();
        final catStr = categories.join(' or ');
        _feedbackMessage = 'Think of items from $catStr';
      } else if (hintLevel >= 2) {
        // Eliminate one distractor from the shelf
        final shelf = _shelf;
        final targetIds = _targetIds;
        final distractor = shelf.firstWhere(
          (i) => !targetIds.contains(i.id) && i.id != _eliminatedId,
          orElse: () => shelf.first,
        );
        _eliminatedId = distractor.id;
        _feedbackMessage = 'Look closely at the items remaining';
      }
    });
  }

  String _formatCurrentTime() {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _itemDisplayName(String labelKey) {
    switch (labelKey) {
      case 'item.rice':
        return 'Rice (Chawal)';
      case 'item.atta':
        return 'Atta (Flour)';
      case 'item.poha':
        return 'Poha';
      case 'item.dal':
        return 'Dal (Lentils)';
      case 'item.chana':
        return 'Chana (Gram)';
      case 'item.tomato':
        return 'Tomato';
      case 'item.potato':
        return 'Potato (Aloo)';
      case 'item.brinjal':
        return 'Brinjal (Baingan)';
      case 'item.banana':
        return 'Banana (Kela)';
      case 'item.papaya':
        return 'Papaya';
      case 'item.milk':
        return 'Fresh Milk';
      case 'item.curd':
        return 'Curd (Dahi)';
      case 'item.tea':
        return 'Assam Tea';
      case 'item.salt':
        return 'Salt (Namak)';
      case 'item.mustardoil':
        return 'Mustard Oil';
      default:
        return labelKey.replaceAll('item.', '');
    }
  }

  static String _categoryDisplayName(String category) {
    switch (category) {
      case 'grain':
        return 'the grains';
      case 'pulse':
        return 'the lentils';
      case 'vegetable':
        return 'the vegetables';
      case 'fruit':
        return 'the fruits';
      case 'dairy':
        return 'the dairy';
      case 'pantry':
        return 'the pantry';
      default:
        return 'the market';
    }
  }

  static const String _imageAssetPrefix =
      'assets/images/market_basket_15_images_final/';

  static String _itemImageAsset(String id) {
    switch (id) {
      case 'rice':
        return '${_imageAssetPrefix}rice.png';
      case 'atta':
        return '${_imageAssetPrefix}atta.png';
      case 'poha':
        return '${_imageAssetPrefix}poha.png';
      case 'dal':
        return '${_imageAssetPrefix}dal.png';
      case 'chana':
        return '${_imageAssetPrefix}chana.png';
      case 'tomato':
        return '${_imageAssetPrefix}tomato.png';
      case 'potato':
        return '${_imageAssetPrefix}potato.png';
      case 'brinjal':
        return '${_imageAssetPrefix}brinjal.png';
      case 'banana':
        return '${_imageAssetPrefix}banana.png';
      case 'papaya':
        return '${_imageAssetPrefix}papaya.png';
      case 'milk':
        return '${_imageAssetPrefix}milk.png';
      case 'curd':
        return '${_imageAssetPrefix}curd.png';
      case 'tea':
        return '${_imageAssetPrefix}tea.png';
      case 'salt':
        return '${_imageAssetPrefix}salt.png';
      case 'mustardoil':
        return '${_imageAssetPrefix}mustardoil.png';
      default:
        return '$_imageAssetPrefix$id.png';
    }
  }

  static Widget _buildItemVisual({
    required MarketItem item,
    double? size,
  }) {
    final assetPath = _itemImageAsset(item.id);
    return Image.asset(
      assetPath,
      width: size ?? double.infinity,
      height: size ?? double.infinity,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final fallbackSize = size ??
                (constraints.biggest.shortestSide > 0
                    ? constraints.biggest.shortestSide * 0.75
                    : 56.0);
            return Center(
              child: Icon(
                _itemIcon(item.id, item.category),
                size: fallbackSize,
                color: _categoryColor(item.category),
              ),
            );
          },
        );
      },
    );
  }

  static IconData _itemIcon(String id, String category) {
    switch (id) {
      case 'rice':
        return Icons.rice_bowl_rounded;
      case 'atta':
        return Icons.bakery_dining_rounded;
      case 'poha':
        return Icons.breakfast_dining_rounded;
      case 'dal':
        return Icons.soup_kitchen_rounded;
      case 'chana':
        return Icons.grain_rounded;
      case 'tomato':
        return Icons.eco_rounded;
      case 'potato':
        return Icons.spa_rounded;
      case 'brinjal':
        return Icons.grass_rounded;
      case 'banana':
        return Icons.wb_sunny_rounded;
      case 'papaya':
        return Icons.yard_rounded;
      case 'milk':
        return Icons.local_drink_rounded;
      case 'curd':
        return Icons.icecream_rounded;
      case 'tea':
        return Icons.emoji_food_beverage_rounded;
      case 'salt':
        return Icons.kitchen_rounded;
      case 'mustardoil':
        return Icons.opacity_rounded;
      default:
        switch (category) {
          case 'grain':
            return Icons.rice_bowl_rounded;
          case 'pulse':
            return Icons.grain_rounded;
          case 'vegetable':
            return Icons.eco_rounded;
          case 'fruit':
            return Icons.yard_rounded;
          case 'dairy':
            return Icons.local_drink_rounded;
          default:
            return Icons.shopping_basket_rounded;
        }
    }
  }

  static Color _categoryColor(String category) {
    switch (category) {
      case 'grain':
        return const Color(0xFFD99A2B); // Marigold
      case 'pulse':
        return AppColors.terracotta;
      case 'vegetable':
        return AppColors.leafGreen;
      case 'fruit':
        return const Color(0xFFD97724);
      case 'dairy':
        return AppColors.indigo;
      case 'pantry':
        return const Color(0xFF7D5836);
      default:
        return AppColors.terracotta;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final isCompact = size.width < 600 || size.height < 500;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 24,
                vertical: isCompact ? 6 : 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  InkWell(
                    key: const Key('mb_back_button'),
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
                          color: AppColors.primaryText,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: isCompact ? 22 : 28,
                            color: AppColors.primaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Games',
                            style: TextStyle(
                              fontSize: isCompact ? 16 : 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Title and trial count
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CustomPaint(
                                size: isCompact
                                    ? const Size(26, 16)
                                    : const Size(32, 20),
                                painter: const _BasketMiniPainter(),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Market Basket · $_trialsDone completed',
                                style: TextStyle(
                                  fontSize: isCompact ? 18 : 24,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryText,
                                  fontFamily: 'Noto Sans',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Hint Button & Time
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('mb_hint_button'),
                        onPressed: _onAskHint,
                        tooltip: 'Hint',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Container(
                          padding: EdgeInsets.all(isCompact ? 6 : 8),
                          decoration: BoxDecoration(
                            color: AppColors.marigold.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.marigold,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.lightbulb_outline_rounded,
                            size: isCompact ? 22 : 26,
                            color: AppColors.marigoldDark,
                          ),
                        ),
                      ),
                      SizedBox(width: isCompact ? 8 : 14),
                      Text(
                        _formatCurrentTime(),
                        style: TextStyle(
                          fontSize: isCompact ? 18 : 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // MAIN INTERACTIVE AREA
            Expanded(
              child: item == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.terracotta,
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 12 : 24,
                        4,
                        isCompact ? 12 : 24,
                        isCompact ? 10 : 16,
                      ),
                      child: _showingList
                          ? _buildList(
                              isLandscape: isLandscape, isCompact: isCompact)
                          : _buildShelf(
                              isLandscape: isLandscape, isCompact: isCompact),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PHASE 1: Memorization Screen ("Remember these")
  // ─────────────────────────────────────────────
  Widget _buildList({required bool isLandscape, required bool isCompact}) {
    final targets = _targets;

    return Container(
      key: const Key('mb_list'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.raisedSurface,
        borderRadius: BorderRadius.circular(isCompact ? 20 : 28),
        border: Border.all(color: AppColors.border, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 14 : 32,
        vertical: isCompact ? 10 : 20,
      ),
      child: Column(
        children: [
          // Prompt Header
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: isCompact ? 26 : 32,
                  color: AppColors.terracotta,
                ),
                const SizedBox(width: 10),
                Text(
                  'Remember these items for your basket',
                  style: TextStyle(
                    fontSize: isCompact ? 20 : 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                    fontFamily: 'Noto Sans',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isCompact ? 8 : 16),

          // Target Goods Display
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cardHeight =
                      (constraints.maxHeight - 8).clamp(130.0, 270.0);
                  final cardWidth = isLandscape
                      ? (cardHeight * 0.95).clamp(140.0, 240.0)
                      : (cardHeight * 0.85).clamp(140.0, 240.0);

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final target in targets)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 8 : 14,
                            ),
                            child: Container(
                              key: Key('mb_target_${target.id}'),
                              width: cardWidth,
                              height: cardHeight,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFDF8),
                                borderRadius: BorderRadius.circular(
                                    isCompact ? 16 : 22),
                                border: Border.all(
                                  color: _categoryColor(target.category),
                                  width: 3,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x12000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: EdgeInsets.fromLTRB(
                                isCompact ? 10 : 14,
                                isCompact ? 10 : 14,
                                isCompact ? 10 : 14,
                                isCompact ? 8 : 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Real food image takes ~70% of the card
                                  Expanded(
                                    flex: 70,
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        child: _buildItemVisual(item: target),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Item name and category below image (secondary)
                                  Expanded(
                                    flex: 30,
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.center,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                _itemDisplayName(
                                                    target.labelKey),
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize:
                                                      isCompact ? 16 : 20,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primaryText,
                                                  fontFamily: 'Noto Sans',
                                                  height: 1.15,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                target.category.toUpperCase(),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize:
                                                      isCompact ? 11 : 13,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1.2,
                                                  color: _categoryColor(
                                                      target.category),
                                                  fontFamily: 'Noto Sans',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: isCompact ? 8 : 16),

          // "Ready" Action Button
          SizedBox(
            width: isCompact ? 240 : 280,
            height: isCompact ? 48 : 58,
            child: ElevatedButton(
              key: const Key('mb_ready'),
              onPressed: _hideList,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.terracotta,
                foregroundColor: AppColors.onColor,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: isCompact ? 24 : 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'I am ready',
                      style: TextStyle(
                        fontSize: isCompact ? 20 : 24,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Noto Sans',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PHASE 2 & 3: Six goods on a woven mat (Screens 04 & 05)
  // ─────────────────────────────────────────────
  Widget _buildShelf({required bool isLandscape, required bool isCompact}) {
    final shelf = _shelf;
    final targets = _targets;
    final isPraise = _isCorrect == true;

    return Container(
      key: const Key('mb_shelf'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.raisedSurface,
        borderRadius: BorderRadius.circular(isCompact ? 20 : 28),
        border: Border.all(
          color: isPraise ? AppColors.marigold : AppColors.border,
          width: isPraise ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isPraise ? const Color(0x35D99A2B) : const Color(0x15000000),
            blurRadius: isPraise ? 20 : 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 20,
        vertical: isCompact ? 8 : 16,
      ),
      child: Column(
        children: [
          // Prompt & Feedback Banner (Screen 05 praise banner)
          Container(
            key: const Key('mb_feedback_banner'),
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 20,
              vertical: isCompact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: isPraise
                  ? AppColors.marigold.withValues(alpha: 0.22)
                  : _feedbackMessage != null
                      ? AppColors.leafGreen.withValues(alpha: 0.15)
                      : const Color(0xFFFFFDF8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPraise
                    ? AppColors.marigold
                    : _feedbackMessage != null
                        ? AppColors.leafGreen
                        : AppColors.border,
                width: 2,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPraise
                        ? Icons.stars_rounded
                        : Icons.shopping_basket_rounded,
                    size: isCompact ? 24 : 28,
                    color: isPraise
                        ? AppColors.marigoldDark
                        : AppColors.terracotta,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _feedbackMessage ??
                        'Put the items you remember into the basket (${_picked.length}/${targets.length})',
                    style: TextStyle(
                      fontSize: isCompact ? 17 : 22,
                      fontWeight: FontWeight.w700,
                      color: isPraise
                          ? AppColors.marigoldDark
                          : AppColors.primaryText,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: isCompact ? 8 : 12),

          // Screen 04: The Woven Mat Area
          Expanded(
            child: CustomPaint(
              painter: const _WovenMatPainter(),
              child: Container(
                padding: EdgeInsets.all(isCompact ? 8 : 14),
                child: LayoutBuilder(
                  builder: (context, matConstraints) {
                    final isNarrow = matConstraints.maxWidth < 600;
                    final crossAxisCount = isNarrow ? 2 : 3;
                    final spacing = isCompact ? 8.0 : 12.0;

                    final colWidth = (matConstraints.maxWidth -
                            (crossAxisCount - 1) * spacing) /
                        crossAxisCount;
                    final rowCount = (shelf.length / crossAxisCount).ceil();
                    final availableRowHeight = (matConstraints.maxHeight -
                            (rowCount - 1) * spacing) /
                        rowCount;

                    final cardHeight = isNarrow
                        ? availableRowHeight.clamp(145.0, 240.0)
                        : availableRowHeight.clamp(115.0, 220.0);
                    final aspectRatio = colWidth / cardHeight;

                    return GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: aspectRatio,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                      ),
                      itemCount: shelf.length,
                      itemBuilder: (context, index) {
                        final shelfItem = shelf[index];
                        final isPicked = _picked.contains(shelfItem.id);
                        final isEliminated = _eliminatedId == shelfItem.id;

                        return _buildMatItemCard(
                          item: shelfItem,
                          isPicked: isPicked,
                          isEliminated: isEliminated,
                          isPraise: isPraise,
                          isCompact: isCompact,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          SizedBox(height: isCompact ? 8 : 12),

          // Bottom Bar: Basket count & Submit Button
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Basket count badge
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 12 : 18,
                    vertical: isCompact ? 8 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shopping_basket_rounded,
                        size: isCompact ? 20 : 24,
                        color: AppColors.terracotta,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_picked.length} of ${targets.length} in basket',
                        style: TextStyle(
                          fontSize: isCompact ? 16 : 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isCompact ? 12 : 20),

                // Done / Put in Basket action button
                SizedBox(
                  width: isCompact ? 220 : 260,
                  height: isCompact ? 50 : 58,
                  child: ElevatedButton(
                    key: const Key('mb_submit'),
                    onPressed: _isProcessing ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPraise
                          ? AppColors.marigold
                          : AppColors.terracotta,
                      foregroundColor: AppColors.onColor,
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isPraise
                                ? Icons.check_circle_rounded
                                : Icons.archive_rounded,
                            size: isCompact ? 22 : 26,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isPraise ? 'Completed' : 'Put in Basket',
                            style: TextStyle(
                              fontSize: isCompact ? 18 : 22,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Noto Sans',
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
        ],
      ),
    );
  }

  Widget _buildMatItemCard({
    required MarketItem item,
    required bool isPicked,
    required bool isEliminated,
    required bool isPraise,
    bool isCompact = false,
  }) {
    // Screen 04: "A wrong touch does nothing at all — it simply waits"
    // Screen 05: "Marigold ring, spoken praise"
    final showMarigoldRing = isPraise && isPicked;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isEliminated ? 0.25 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('mb_pick_${item.id}'),
          onTap: (isEliminated || _isProcessing) ? null : () => _toggle(item.id),
          borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color:
                  isPicked ? const Color(0xFFFFF7EA) : const Color(0xFFFFFDF8),
              borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
              border: Border.all(
                color: showMarigoldRing
                    ? AppColors.marigold
                    : isPicked
                        ? AppColors.terracotta
                        : AppColors.border,
                width: showMarigoldRing
                    ? 4.0
                    : isPicked
                        ? 3.0
                        : 2.0,
              ),
              boxShadow: [
                if (showMarigoldRing)
                  const BoxShadow(
                    color: Color(0x60D99A2B),
                    blurRadius: 14,
                    spreadRadius: 2,
                  )
                else if (isPicked)
                  const BoxShadow(
                    color: Color(0x22C75B39),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  )
                else
                  const BoxShadow(
                    color: Color(0x0C000000),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
              ],
            ),
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isCompact ? 16 : 20),
              child: Stack(
                children: [
                  // Main Card Content: Food Image (70%) + Name & Category (30%)
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 8 : 12,
                        isCompact ? 8 : 10,
                        isCompact ? 8 : 12,
                        isCompact ? 6 : 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Food Image (takes ~70% of the card, main visual focus)
                          Expanded(
                            flex: 70,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                isCompact ? 6 : 10,
                                2,
                                isCompact ? 22 : 28, // Clear of top-right checkmark
                                2,
                              ),
                              child: _buildItemVisual(item: item),
                            ),
                          ),
                          const SizedBox(height: 3),
                          // Secondary Item Name and Category below image
                          Expanded(
                            flex: 30,
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _itemDisplayName(item.labelKey),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: isCompact ? 15 : 18,
                                          fontWeight: isPicked
                                              ? FontWeight.w800
                                              : FontWeight.w700,
                                          color: AppColors.primaryText,
                                          fontFamily: 'Noto Sans',
                                          height: 1.15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.category.toUpperCase(),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: isCompact ? 10 : 12,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.1,
                                          color: _categoryColor(item.category),
                                          fontFamily: 'Noto Sans',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Selection / Checkmark indicator in top-right corner
                  Positioned(
                    top: isCompact ? 8 : 10,
                    right: isCompact ? 8 : 10,
                    child: isPicked
                        ? Container(
                            width: isCompact ? 26 : 32,
                            height: isCompact ? 26 : 32,
                            decoration: BoxDecoration(
                              color: showMarigoldRing
                                  ? AppColors.marigold
                                  : AppColors.terracotta,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x28000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              showMarigoldRing
                                  ? Icons.star_rounded
                                  : Icons.check_rounded,
                              size: isCompact ? 18 : 22,
                              color: AppColors.onColor,
                            ),
                          )
                        : Container(
                            width: isCompact ? 22 : 26,
                            height: isCompact ? 22 : 26,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.border.withValues(alpha: 0.8),
                                width: 1.8,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the textured woven mat (Screen 04).
///
/// Draws subtle diagonal weave texture and border in warm rural earthen tones.
class _WovenMatPainter extends CustomPainter {
  const _WovenMatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(24),
    );

    // Mat ground fill
    final bgPaint = Paint()..color = AppColors.wovenMat;
    canvas.drawRRect(rrect, bgPaint);

    // Weave pattern lines
    final weavePaint = Paint()
      ..color = const Color(0xFFD4C09A)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.clipRRect(rrect);

    // Diagonal weave grid lines
    const spacing = 18.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        weavePaint,
      );
    }
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i + size.height, 0),
        Offset(i, size.height),
        weavePaint,
      );
    }

    canvas.restore();

    // Mat border trim
    final borderPaint = Paint()
      ..color = const Color(0xFFBFAB86)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Compact basket icon for title bar.
class _BasketMiniPainter extends CustomPainter {
  const _BasketMiniPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.terracotta
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path()
      ..moveTo(2, 4)
      ..lineTo(6, size.height - 2)
      ..lineTo(size.width - 6, size.height - 2)
      ..lineTo(size.width - 2, 4)
      ..close();

    canvas.drawPath(path, paint);

    // Cross ribs
    canvas.drawLine(
      Offset(size.width * 0.35, 4),
      Offset(size.width * 0.35, size.height - 2),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.65, 4),
      Offset(size.width * 0.65, size.height - 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
