import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import '../core/sync/sync_engine.dart';
import '../games/game_content_loader.dart';
import '../games/market_basket/market_basket_screen.dart';
import '../games/sort_the_harvest/sort_the_harvest_screen.dart';

/// Screen 02: Games Menu.
///
/// Designed for a 1280×800 landscape tablet.
/// Presents four cognitive games:
/// 1. Market Basket (Working memory / span)
/// 2. Faces of My Family (Long-term / semantic memory)
/// 3. Sort the Harvest (Executive function / set-shifting)
/// 4. Sounds of Home (Auditory attention & recognition)
class GamesMenuScreen extends StatelessWidget {
  const GamesMenuScreen({super.key, required this.services});

  final AppServices services;

  Future<void> _playMarketBasket(BuildContext context) async {
    final content = await loadMockGameContent();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketBasketScreen(
          services: services,
          content: content,
        ),
      ),
    );
    await services.syncEngine.run(trigger: SyncTrigger.sessionEnd);
  }

  Future<void> _playSortTheHarvest(BuildContext context) async {
    final content = await loadMockGameContent();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SortTheHarvestScreen(
          services: services,
          content: content,
        ),
      ),
    );
    await services.syncEngine.run(trigger: SyncTrigger.sessionEnd);
  }

  void _showComingSoon(BuildContext context, String gameName, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$gameName will be ready soon!'),
        duration: const Duration(seconds: 2),
        backgroundColor: color,
      ),
    );
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
        child: Column(
          children: [
            // TOP BAR: Large return button, title, and clock
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 28, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back to Home button (large accessible touch target)
                  InkWell(
                    key: const Key('games_back_button'),
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.primaryText, width: 2),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded,
                              size: 28, color: AppColors.primaryText),
                          SizedBox(width: 8),
                          Text(
                            'Home',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Text(
                    'Games',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                      fontFamily: 'Noto Sans',
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

            // 4 GAME CARDS (2x2 Grid)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
                child: Row(
                  children: [
                    // Column 1: Market Basket & Sort the Harvest
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _buildGameCard(
                              context: context,
                              key: const Key('game_card_market_basket'),
                              title: 'Market Basket',
                              subtitle: 'Remember what to buy',
                              color: AppColors.terracotta,
                              onTap: () => _playMarketBasket(context),
                              iconPainter: const _BasketPainter(),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Expanded(
                            child: _buildGameCard(
                              context: context,
                              key: const Key('game_card_sort_harvest'),
                              title: 'Sort the Harvest',
                              subtitle: 'Sort into the right tray',
                              color: AppColors.leafGreen,
                              onTap: () => _playSortTheHarvest(context),
                              iconWidget: const Icon(
                                Icons.grid_view_rounded,
                                size: 56,
                                color: Color(0xFF386144),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    // Column 2: Faces of My Family & Sounds of Home
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _buildGameCard(
                              context: context,
                              key: const Key('game_card_faces'),
                              title: 'Faces of My Family',
                              subtitle: 'Recognize family members',
                              color: AppColors.indigo,
                              onTap: () => _showComingSoon(
                                  context, 'Faces of My Family', AppColors.indigo),
                              iconWidget: Container(
                                width: 72,
                                height: 72,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE9DFCE),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.people_alt_rounded,
                                  size: 48,
                                  color: AppColors.indigoDark,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Expanded(
                            child: _buildGameCard(
                              context: context,
                              key: const Key('game_card_sounds'),
                              title: 'Sounds of Home',
                              subtitle: 'Listen and identify sounds',
                              color: AppColors.marigold,
                              onTap: () => _showComingSoon(
                                  context, 'Sounds of Home', AppColors.marigold),
                              iconWidget: const Icon(
                                Icons.volume_up_rounded,
                                size: 56,
                                color: Color(0xFF9A6C17),
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
          ],
        ),
      ),
    );
  }

  Widget _buildGameCard({
    required BuildContext context,
    required Key key,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    CustomPainter? iconPainter,
    Widget? iconWidget,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 3),
        ),
        child: Column(
          children: [
            // Upper illustration area
            Expanded(
              flex: 6,
              child: Center(
                child: iconPainter != null
                    ? CustomPaint(
                        size: const Size(120, 60),
                        painter: iconPainter,
                      )
                    : iconWidget ?? const SizedBox.shrink(),
              ),
            ),
            // Lower banner with game name & subtitle
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onColor,
                      letterSpacing: 0.3,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.onColor.withAlpha(220),
                      fontFamily: 'Noto Sans',
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

/// Custom painter for the fruit basket icon on the Market Basket game card.
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

    // Fruits
    fillPaint.color = const Color(0xFFC74B39);
    canvas.drawCircle(Offset(cx - 18, cy - 8), 13, fillPaint);
    canvas.drawCircle(Offset(cx - 18, cy - 8), 13, strokePaint);

    fillPaint.color = const Color(0xFF3E6F4B);
    canvas.drawCircle(Offset(cx + 1, cy - 10), 12, fillPaint);
    canvas.drawCircle(Offset(cx + 1, cy - 10), 12, strokePaint);

    fillPaint.color = const Color(0xFFDE9928);
    canvas.drawCircle(Offset(cx + 18, cy - 7), 13, fillPaint);
    canvas.drawCircle(Offset(cx + 18, cy - 7), 13, strokePaint);

    // Basket trapezoid
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
