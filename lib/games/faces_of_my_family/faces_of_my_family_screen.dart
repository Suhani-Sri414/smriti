import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core/app_services.dart';
import '../../screens/session_end_screen.dart';
import '../../core/db/database.dart';
import '../cognitive_game.dart';
import '../session_runner.dart';
import 'faces_of_my_family_game.dart';

/// Screen for Faces of My Family (Screen 02 game 3).
///
/// Long-term semantic family recognition game for the 1280×800 tablet.
/// The elder inspects the portrait/avatar and selects who the person is
/// from 3 accessible candidate cards.
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

  @override
  void initState() {
    super.initState();
    _initGameAndStart();
  }

  Future<void> _initGameAndStart() async {
    // Load people from local SQLite repository
    final dbPeople = await widget.services.contentRepo.getPeople();
    final familyList = dbPeople.isNotEmpty
        ? dbPeople.map(_mapDbPersonToFamilyPerson).toList()
        : FacesOfMyFamilyGame.defaultFamilyPeople;

    final game = FacesOfMyFamilyGame(people: familyList);
    _game = game;

    await _runner.start([game]);
    await _nextItem();
  }

  FamilyPerson _mapDbPersonToFamilyPerson(PeopleData p) {
    return FamilyPerson(
      id: p.id,
      name: p.name,
      relationship: p.relationship,
      photoPath: p.photoPath.isNotEmpty ? p.photoPath : null,
      memoryPrompt: p.memoryPrompt,
      avatarColor: const Color(0xFF213A5C),
    );
  }

  Timer? _advanceTimer;

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _runner.end(completed: false);
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
        _feedbackMessage = target.memoryPrompt ?? 'Think of your ${target.relationship}';
      } else if (hintLevel >= 2) {
        // Eliminate one distractor
        final distractor =
            options.firstWhere((p) => p.id != target.id && p.id != _eliminatedId);
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

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            // TOP BAR
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 28, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    key: const Key('faces_back_button'),
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
                            'Games',
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
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Faces of My Family',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          fontFamily: 'Noto Sans',
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('faces_hint_button'),
                        icon: const Icon(Icons.lightbulb_outline_rounded,
                            size: 32, color: AppColors.marigoldDark),
                        tooltip: 'Hint',
                        onPressed: _onAskHint,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatTime(),
                        style: const TextStyle(
                          fontSize: 22,
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
            Expanded(
              child: target == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.indigo,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                      child: Column(
                        children: [
                          // CENTER CARD: Portrait & Prompt
                          Expanded(
                            flex: 5,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFDF8),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: AppColors.indigo.withAlpha(80),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(12),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Portrait Circle
                                  _buildAvatar(target),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Who is this?',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryText,
                                      fontFamily: 'Noto Sans',
                                    ),
                                  ),
                                  if (_feedbackMessage != null) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3EDE2),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        _feedbackMessage!,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primaryText,
                                          fontFamily: 'Noto Sans',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // CANDIDATE CHOICE CARDS (3 columns)
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                for (int i = 0; i < options.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 20),
                                  Expanded(
                                    child: _buildChoiceCard(options[i]),
                                  ),
                                ],
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

  Widget _buildAvatar(FamilyPerson person) {
    final photo = person.photoPath;
    final hasLocalPhoto = photo != null && File(photo).existsSync();

    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: person.avatarColor,
        border: Border.all(color: const Color(0xFFFFFDF8), width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: hasLocalPhoto
          ? ClipOval(
              child: Image.file(
                File(photo),
                fit: BoxFit.cover,
                width: 140,
                height: 140,
              ),
            )
          : Center(
              child: Text(
                person.name.isNotEmpty ? person.name[0] : '?',
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamily: 'Noto Sans',
                ),
              ),
            ),
    );
  }

  Widget _buildChoiceCard(FamilyPerson person) {
    final isEliminated = person.id == _eliminatedId;

    if (isEliminated) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEFECE4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD6CFC4), width: 2),
        ),
        child: const Center(
          child: Icon(Icons.remove_circle_outline,
              size: 36, color: Color(0xFFA69E92)),
        ),
      );
    }

    return InkWell(
      key: Key('face_option_${person.id}'),
      onTap: _isProcessing ? null : () => _onChoosePerson(person),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.indigo, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              person.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
                fontFamily: 'Noto Sans',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              person.relationship,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryText.withAlpha(180),
                fontFamily: 'Noto Sans',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
