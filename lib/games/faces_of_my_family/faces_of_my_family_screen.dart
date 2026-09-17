import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app_colors.dart';
import '../../core/app_services.dart';
import '../../core/files/file_paths.dart';
import '../../screens/session_end_screen.dart';
import '../cognitive_game.dart';
import '../session_runner.dart';
import 'faces_of_my_family_game.dart';

/// Screen for Faces of My Family (Screen 02 game 3).
///
/// Long-term semantic family recognition game for the elder tablet.
/// Recommended layout hierarchy:
///   Header
///   ↓
///   Large centered person photo
///   ↓
///   "Who is this?"
///   ↓
///   Large name-selection buttons/cards (ONLY name & relationship)
///
/// Adheres strictly to AGENTS.md rule 11: no red, no "wrong", neutral return
/// on incorrect answer.
class FacesOfMyFamilyScreen extends StatefulWidget {
  const FacesOfMyFamilyScreen({
    super.key,
    required this.services,
    required this.content,
  });

  final AppServices services;
  final GameContent content;

  @override
  State<FacesOfMyFamilyScreen> createState() => _FacesOfMyFamilyScreenState();
}

class _FacesOfMyFamilyScreenState extends State<FacesOfMyFamilyScreen> {
  FacesOfMyFamilyGame? _game;
  late final SessionRunner _runner = SessionRunner(
    eventRepo: widget.services.eventRepo,
    abilityRepo: widget.services.abilityRepo,
    content: widget.content,
  );

  GameItem? _item;
  DateTime? _shownAt;
  DateTime? _firstTouchAt;
  bool _isProcessing = false;
  String? _feedbackMessage;
  String? _eliminatedId;
  String? _selectedChoiceId;
  Timer? _advanceTimer;

  static const List<Color> _avatarColors = [
    Color(0xFF213A5C), // Navy
    Color(0xFF8A3C23), // Rust
    Color(0xFF2B4C38), // Forest Green
    Color(0xFFB57A1E), // Golden Ochre
    Color(0xFF4A4644), // Charcoal
    Color(0xFFC85A32), // Terracotta
    Color(0xFF3D5A8A), // Indigo
    Color(0xFF487E5E), // Leaf Green
    Color(0xFF7A3522), // Deep Brown
  ];

  Color _getAvatarColor(int index) =>
      _avatarColors[index % _avatarColors.length];

  @override
  void initState() {
    super.initState();
    _initGameAndStart();
  }

  Future<void> _initGameAndStart() async {
    // 1. Load living people from local SQLite repository (fallback to all people)
    final livingPeople = await widget.services.contentRepo.getLivingPeople();
    final dbPeople = livingPeople.isNotEmpty
        ? livingPeople
        : await widget.services.contentRepo.getPeople();

    final mappedPeople = <FamilyPerson>[];
    for (var i = 0; i < dbPeople.length; i++) {
      final pData = dbPeople[i];
      final resolvedPhoto = await _resolvePhotoPath(pData.photoPath);
      mappedPeople.add(
        FamilyPerson(
          id: pData.id,
          name: pData.name,
          relationship: pData.relationship,
          photoPath: resolvedPhoto,
          memoryPrompt: pData.memoryPrompt,
          avatarColor: _getAvatarColor(i),
        ),
      );
    }

    // 2. Ensure at least 3 candidate options:
    // If the user added people in the People section (e.g. Veer), retain them.
    // If fewer than 3 were added, pad with defaults so real people are NEVER dropped.
    final List<FamilyPerson> familyList;
    if (mappedPeople.isNotEmpty) {
      familyList = List<FamilyPerson>.from(mappedPeople);
      if (familyList.length < 3) {
        for (final def in FacesOfMyFamilyGame.defaultFamilyPeople) {
          if (!familyList.any((p) =>
              p.id == def.id ||
              p.name.toLowerCase() == def.name.toLowerCase())) {
            familyList.add(def);
            if (familyList.length >= 3) break;
          }
        }
      }
    } else {
      familyList = FacesOfMyFamilyGame.defaultFamilyPeople;
    }

    final game = FacesOfMyFamilyGame(people: familyList);
    _game = game;

    await _runner.start([game]);
    await _nextItem();
  }

  Future<String?> _resolvePhotoPath(String? rawPath) async {
    if (rawPath == null || rawPath.trim().isEmpty) return null;
    final trimmed = rawPath.trim();
    if (trimmed.startsWith('assets/')) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    try {
      if (File(trimmed).existsSync()) return trimmed;

      final absPath = await widget.services.resolveMediaPath(trimmed);
      if (File(absPath).existsSync()) return absPath;

      if (FilePaths.documentsDirectoryOverride != null) {
        final overridePath =
            p.join(FilePaths.documentsDirectoryOverride!, trimmed);
        if (File(overridePath).existsSync()) return overridePath;
      }

      return absPath;
    } catch (_) {
      return trimmed;
    }
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _runner.end(completed: false).catchError((_) {});
    _game?.dispose();
    super.dispose();
  }

  Future<void> _nextItem() async {
    final game = _game;
    if (game == null) return;

    final item = await _runner.nextItem(game);
    if (!mounted) return;

    if (item == null) {
      await _runner.end(completed: true);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SessionEndScreen(
              services: widget.services,
              gameTitle: 'Faces of My Family',
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
      _eliminatedId = null;
      _selectedChoiceId = null;
    });
  }

  void _onChoosePerson(FamilyPerson chosen) {
    if (_isProcessing || _item == null || _game == null) return;
    final now = DateTime.now();
    _firstTouchAt ??= now;

    final target = _item!.payload['target'] as FamilyPerson;
    final isCorrect = chosen.id == target.id;

    setState(() {
      _isProcessing = true;
      _selectedChoiceId = chosen.id;
      if (isCorrect) {
        _feedbackMessage = 'Yes, that is ${target.name}!';
      } else {
        // Rule 11: Gentle neutral cue, no red, no "wrong"
        _feedbackMessage = 'Let us look closely together';
      }
    });

    final initiationMs =
        _firstTouchAt!.difference(_shownAt ?? _firstTouchAt!).inMilliseconds;
    final movementMs = now.difference(_firstTouchAt!).inMilliseconds;

    _game!.submitChoice(
      item: _item!,
      chosenId: chosen.id,
      initiationMs: initiationMs.clamp(50, 30000),
      movementMs: movementMs.clamp(10, 30000),
    );

    _advanceTimer?.cancel();
    _advanceTimer = Timer(Duration(milliseconds: isCorrect ? 1200 : 1500), () {
      if (!mounted) return;
      _nextItem();
    });
  }

  void _onAskHint() {
    if (_isProcessing || _item == null) return;
    final hintLevel = _runner.escalateHint();
    final target = _item!.payload['target'] as FamilyPerson;
    final options =
        (_item!.payload['options'] as List<Object?>).cast<FamilyPerson>();

    setState(() {
      if (hintLevel == 1) {
        _feedbackMessage =
            target.memoryPrompt ?? 'Think of your ${target.relationship}';
      } else if (hintLevel >= 2) {
        // Eliminate one distractor
        final distractor = options
            .firstWhere((p) => p.id != target.id && p.id != _eliminatedId);
        _eliminatedId = distractor.id;
        _feedbackMessage = 'Look at the choices left';
      }
    });
  }

  String _formatTime() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final target = _item?.payload['target'] as FamilyPerson?;
    final options = (_item?.payload['options'] as List<Object?>?)
            ?.cast<FamilyPerson>() ??
        const [];

    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final isCompact = media.size.shortestSide < 600;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR
            Padding(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 16 : 24,
                isCompact ? 8 : 12,
                isCompact ? 16 : 28,
                isCompact ? 6 : 8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    key: const Key('faces_back_button'),
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
                            color: AppColors.primaryText, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded,
                              size: isCompact ? 24 : 28,
                              color: AppColors.primaryText),
                          const SizedBox(width: 8),
                          Text(
                            'Games',
                            style: TextStyle(
                              fontSize: isCompact ? 17 : 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'Faces of My Family',
                            style: TextStyle(
                              fontSize: isCompact ? 20 : 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('faces_hint_button'),
                        icon: Icon(Icons.lightbulb_outline_rounded,
                            size: isCompact ? 28 : 32,
                            color: AppColors.marigoldDark),
                        tooltip: 'Hint',
                        onPressed: _onAskHint,
                      ),
                      SizedBox(width: isCompact ? 6 : 12),
                      Text(
                        _formatTime(),
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

            // MAIN INTERACTION AREA
            // Hierarchy:
            //   Large centered person photo
            //   ↓
            //   "Who is this?"
            //   ↓
            //   Large name-selection buttons/cards
            Expanded(
              child: target == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.indigo,
                      ),
                    )
                  : Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: isLandscape ? 860 : 540,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 16 : 24,
                          vertical: isCompact ? 6 : 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Large centered person photo (main visual focus)
                            Expanded(
                              flex: isLandscape ? 58 : 52,
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: isLandscape ? 1.35 : 1.05,
                                  child: _buildCenterPhotoCard(
                                    target,
                                    isCompact: isCompact,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: isCompact ? 8 : 12),

                            // 2. Clear Question & Feedback ("Who is this?")
                            _buildQuestionAndFeedback(
                              isCompact: isCompact,
                            ),
                            SizedBox(height: isCompact ? 10 : 16),

                            // 3. Simple, large name-selection buttons (NO photos inside)
                            Expanded(
                              flex: isLandscape ? 24 : 24,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (int i = 0; i < options.length; i++) ...[
                                    if (i > 0)
                                      SizedBox(width: isCompact ? 10 : 16),
                                    Expanded(
                                      child: _buildNameOptionCard(
                                        options[i],
                                        isCompact: isCompact,
                                      ),
                                    ),
                                  ],
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

  /// Central Photo Card: Large rectangular/card-shaped area with rounded corners.
  /// Displays the target person's actual photo using BoxFit.cover.
  Widget _buildCenterPhotoCard(
    FamilyPerson target, {
    required bool isCompact,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.indigo.withAlpha(90),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(16),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(isCompact ? 8 : 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: _buildPersonPhoto(
          person: target,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  /// Displays the actual uploaded person photo if available.
  /// Falls back to initial avatar ONLY when genuine absence of a photo file.
  Widget _buildPersonPhoto({
    required FamilyPerson person,
    BoxFit fit = BoxFit.cover,
    required BorderRadius borderRadius,
  }) {
    final photo = person.photoPath;
    if (photo != null && photo.trim().isNotEmpty) {
      final trimmed = photo.trim();
      if (trimmed.startsWith('assets/')) {
        return ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox.expand(
            child: Image.asset(
              trimmed,
              fit: fit,
              errorBuilder: (_, __, ___) => _buildAvatarFallback(
                person,
                borderRadius: borderRadius,
              ),
            ),
          ),
        );
      }
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox.expand(
            child: Image.network(
              trimmed,
              fit: fit,
              errorBuilder: (_, __, ___) => _buildAvatarFallback(
                person,
                borderRadius: borderRadius,
              ),
            ),
          ),
        );
      }

      final file = File(trimmed);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox.expand(
            child: Image.file(
              file,
              fit: fit,
              errorBuilder: (_, __, ___) => _buildAvatarFallback(
                person,
                borderRadius: borderRadius,
              ),
            ),
          ),
        );
      }

      if (FilePaths.documentsDirectoryOverride != null) {
        final overrideFile =
            File(p.join(FilePaths.documentsDirectoryOverride!, trimmed));
        if (overrideFile.existsSync()) {
          return ClipRRect(
            borderRadius: borderRadius,
            child: SizedBox.expand(
              child: Image.file(
                overrideFile,
                fit: fit,
                errorBuilder: (_, __, ___) => _buildAvatarFallback(
                  person,
                  borderRadius: borderRadius,
                ),
              ),
            ),
          );
        }
      }
    }

    // Only show fallback when genuine absence of photo
    return _buildAvatarFallback(
      person,
      borderRadius: borderRadius,
    );
  }

  /// High-contrast fallback avatar occupying the rectangular photo area.
  Widget _buildAvatarFallback(
    FamilyPerson person, {
    required BorderRadius borderRadius,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxW =
            constraints.hasBoundedWidth && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 140.0;
        final double maxH =
            constraints.hasBoundedHeight && constraints.maxHeight > 0
                ? constraints.maxHeight
                : 140.0;
        final double side = min(maxW, maxH).clamp(40.0, 240.0);

        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: person.avatarColor,
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withAlpha(180),
              width: 2,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_rounded,
                  size: side * 0.42,
                  color: Colors.white.withAlpha(220),
                ),
                if (person.name.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    person.name[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: side * 0.28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Question & Feedback banner: "Who is this?" placed directly under the photo.
  Widget _buildQuestionAndFeedback({
    required bool isCompact,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Who is this?',
            style: TextStyle(
              fontSize: isCompact ? 24 : 30,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
              fontFamily: 'Noto Sans',
            ),
          ),
        ),
        if (_feedbackMessage != null) ...[
          SizedBox(height: isCompact ? 4 : 6),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 14 : 20,
              vertical: isCompact ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EDE2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.indigo.withAlpha(60),
                width: 1.5,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _feedbackMessage!,
                style: TextStyle(
                  fontSize: isCompact ? 15 : 19,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Name Option Button/Card: Contains ONLY the person's name and relationship below it.
  /// NO photos, NO circular avatars, NO initials.
  Widget _buildNameOptionCard(
    FamilyPerson person, {
    required bool isCompact,
  }) {
    final isEliminated = person.id == _eliminatedId;
    final isSelected = _selectedChoiceId == person.id;

    if (isEliminated) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEFECE4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD6CFC4), width: 2),
        ),
        child: const Center(
          child: Icon(
            Icons.remove_circle_outline,
            size: 32,
            color: Color(0xFFA69E92),
          ),
        ),
      );
    }

    return InkWell(
      key: Key('face_option_${person.id}'),
      onTap: _isProcessing ? null : () => _onChoosePerson(person),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 14,
          vertical: isCompact ? 8 : 12,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEBF1FA)
              : const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.indigo
                : AppColors.indigo.withAlpha(160),
            width: isSelected ? 3.5 : 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.indigo.withAlpha(35)
                  : Colors.black.withAlpha(12),
              blurRadius: isSelected ? 8 : 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  person.name,
                  style: TextStyle(
                    fontSize: isCompact ? 20 : 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                    fontFamily: 'Noto Sans',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (person.relationship.isNotEmpty) ...[
                SizedBox(height: isCompact ? 3 : 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    person.relationship,
                    style: TextStyle(
                      fontSize: isCompact ? 14 : 18,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryText.withAlpha(180),
                      fontFamily: 'Noto Sans',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
