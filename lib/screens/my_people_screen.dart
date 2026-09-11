import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import '../core/db/database.dart';
import '../core/files/file_paths.dart';
import '../core/sync/sync_engine.dart';
import '../core/voice/voice_player.dart';
import '../core/voice/voice_recorder.dart';

/// Screen 10: My People & Screen 11: Person Detail / Voice Recording.
///
/// Designed for a 1280×800 landscape tablet.
/// Nine faces in a 3×3 grid with no scrolling. Names are placed directly
/// underneath each face. Tapping opens person detail with voice playback
/// and in-place memo recording.
class MyPeopleScreen extends StatefulWidget {
  const MyPeopleScreen({
    super.key,
    required this.services,
    this.voicePlayer,
    this.voiceRecorder,
  });

  final AppServices services;
  final VoicePlayer? voicePlayer;
  final VoiceRecorder? voiceRecorder;

  @override
  State<MyPeopleScreen> createState() => _MyPeopleScreenState();
}

class _MyPeopleScreenState extends State<MyPeopleScreen> {
  late final VoicePlayer _player =
      widget.voicePlayer ?? JustAudioVoicePlayer();
  late final VoiceRecorder _recorder =
      widget.voiceRecorder ?? StubVoiceRecorder();

  late final Future<List<PeopleData>> _peopleFuture = _loadPeople();

  Future<List<PeopleData>> _loadPeople() =>
      widget.services.contentRepo.getPeople();

  @override
  void dispose() {
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  static const List<Color> _avatarColors = [
    Color(0xFF213A5C), // Bina (Navy)
    Color(0xFF8A3C23), // Thoibi (Rust)
    Color(0xFF2B4C38), // Tomba (Forest Green)
    Color(0xFFB57A1E), // Memcha (Golden Ochre)
    Color(0xFF4A4644), // Ibotombi (Charcoal)
    Color(0xFFC85A32), // Sanahal (Terracotta)
    Color(0xFF3D5A8A), // Ningol (Indigo Blue)
    Color(0xFF487E5E), // Chaoba (Leaf Green)
    Color(0xFF7A3522), // Leima (Deep Brown)
  ];

  Color _getAvatarColor(int index) =>
      _avatarColors[index % _avatarColors.length];

  void _openPersonDetail(PeopleData person, int index) {
    showDialog(
      context: context,
      builder: (dialogContext) => _PersonDetailDialog(
        person: person,
        avatarColor: _getAvatarColor(index),
        services: widget.services,
        player: _player,
        recorder: _recorder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF261D18),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slide / Screen header matching reference image
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
              child: Row(
                children: [
                  Text(
                    '10',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE5A93C),
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'My People',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF5EFE6),
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                ],
              ),
            ),

            // Main cream card
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                child: FutureBuilder<List<PeopleData>>(
                  future: _peopleFuture,
                  builder: (context, snapshot) {
                    final people = snapshot.data ?? [];

                    return Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(36, 24, 36, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // TITLE: "Your family"
                              const Text(
                                'Your family',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B365D),
                                  fontFamily: 'Noto Sans',
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 9 FACES GRID (3x3, No Scrolling)
                              Expanded(
                                child: people.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No family members yet',
                                          key: Key('people_empty'),
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: AppColors.secondaryText,
                                            fontFamily: 'Noto Sans',
                                          ),
                                        ),
                                      )
                                    : LayoutBuilder(
                                        builder: (context, constraints) {
                                          final displayList =
                                              people.take(9).toList();
                                          return GridView.builder(
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              childAspectRatio: 1.35,
                                              crossAxisSpacing: 24,
                                              mainAxisSpacing: 14,
                                            ),
                                            itemCount: displayList.length,
                                            itemBuilder: (context, index) {
                                              final person = displayList[index];
                                              return _buildPersonAvatar(
                                                person: person,
                                                index: index,
                                              );
                                            },
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),

                        // HOME BUTTON (Bottom Right of cream card)
                        Positioned(
                          right: 28,
                          bottom: 24,
                          child: InkWell(
                            key: const Key('people_home_button'),
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(32),
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFDF8),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFD6CDB8),
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x18000000),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.home_outlined,
                                size: 36,
                                color: Color(0xFF261D18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonAvatar({
    required PeopleData person,
    required int index,
  }) {
    final avatarColor = _getAvatarColor(index);
    final photo = existingFile(person.photoPath);

    return InkWell(
      key: Key('person_card_${person.id}'),
      onTap: () => _openPersonDetail(person, index),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular Disk
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: Color(0xFFE4DAC3),
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: photo != null
                ? Image.file(
                    photo,
                    fit: BoxFit.cover,
                    width: 88,
                    height: 88,
                  )
                : _buildAvatarSilhouette(index, avatarColor),
          ),
          const SizedBox(height: 10),

          // Name underneath (never on hover)
          Text(
            person.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF261D18),
              fontFamily: 'Noto Sans',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSilhouette(int index, Color color) {
    // Indices with hair/cap/headband accents matching the 9-member design
    final hasHairTop = index == 1 || index == 2 || index == 6;
    final hasCap = index == 4;
    final hasHeadband = index == 8;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Head
        Positioned(
          top: 20,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ),

        // Optional hair arc / cap accent
        if (hasHairTop)
          Positioned(
            top: 17,
            child: Container(
              width: 22,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFF231C18),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

        if (hasCap)
          Positioned(
            top: 18,
            child: Container(
              width: 28,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF2E2724),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),

        if (hasHeadband)
          Positioned(
            top: 32,
            child: Container(
              width: 30,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF231C18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

        // Shoulders / Torso
        Positioned(
          bottom: -4,
          child: Container(
            width: 58,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(29),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Screen 11: Person Detail & Recording Modal
class _PersonDetailDialog extends StatefulWidget {
  const _PersonDetailDialog({
    required this.person,
    required this.avatarColor,
    required this.services,
    required this.player,
    required this.recorder,
  });

  final PeopleData person;
  final Color avatarColor;
  final AppServices services;
  final VoicePlayer player;
  final VoiceRecorder recorder;

  @override
  State<_PersonDetailDialog> createState() => _PersonDetailDialogState();
}

class _PersonDetailDialogState extends State<_PersonDetailDialog> {
  bool _isRecording = false;
  bool _isBusy = false;
  int _recordSeconds = 0;
  Timer? _timer;

  void _playVoice() {
    final voice = widget.person.voicePath;
    if (voice != null && voice.isNotEmpty) {
      widget.player.play(voice);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No voice message from ${widget.person.name} yet.'),
          duration: const Duration(seconds: 2),
          backgroundColor: widget.avatarColor,
        ),
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (_isBusy) return;
    _isBusy = true;

    if (_isRecording) {
      // Stop recording and save memo
      _timer?.cancel();
      _timer = null;
      final durationMs = await widget.recorder.stop();
      final memoId = const Uuid().v4();
      final memosDir = await FilePaths.memos();
      final localPath = p.join(memosDir, '$memoId.m4a');

      await widget.services.memoRepo.insertMemo(
        VoiceMemosCompanion.insert(
          id: memoId,
          localPath: localPath,
          durationMs: durationMs,
          recordedAt: DateTime.now().millisecondsSinceEpoch,
          contextTag: Value(widget.person.id),
        ),
      );

      // Trigger background sync for voice memos
      unawaited(
        widget.services.syncEngine.run(trigger: SyncTrigger.manual),
      );

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        setState(() {
          _isRecording = false;
          _isBusy = false;
        });
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Message saved for ${widget.person.name}!'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.leafGreen,
          ),
        );
      }
    } else {
      // Start recording
      final memoId = const Uuid().v4();
      final memosDir = await FilePaths.memos();
      final localPath = p.join(memosDir, '$memoId.m4a');

      await widget.recorder.start(localPath);
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _isBusy = false;
        _recordSeconds = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordSeconds++);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = existingFile(widget.person.photoPath);

    return Dialog(
      backgroundColor: const Color(0xFFFFFDF8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar / Photo
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: Color(0xFFE6DEC8),
                shape: BoxShape.circle,
              ),
              child: photo != null
                  ? ClipOval(
                      child: Image.file(
                        photo,
                        fit: BoxFit.cover,
                        width: 104,
                        height: 104,
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.person,
                        size: 72,
                        color: widget.avatarColor,
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Name
            Text(
              widget.person.name,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
                fontFamily: 'Noto Sans',
              ),
            ),

            // Relationship
            Text(
              widget.person.relationship,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryText,
                fontFamily: 'Noto Sans',
              ),
            ),
            const SizedBox(height: 24),

            // ACTION 1: Hear Message
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                key: const Key('play_person_voice'),
                onPressed: _playVoice,
                icon: const Icon(Icons.volume_up_rounded, size: 26),
                label: Text(
                  "Hear ${widget.person.name}'s message",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryText,
                  side: const BorderSide(color: AppColors.primaryText, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ACTION 2: Leave a Message / Record
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                key: const Key('record_memo_button'),
                onPressed: _toggleRecording,
                icon: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 28,
                ),
                label: Text(
                  _isRecording
                      ? 'Stop recording ($_recordSeconds s)'
                      : 'Leave a message for ${widget.person.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording
                      ? AppColors.recordingDot
                      : AppColors.terracotta,
                  foregroundColor: AppColors.onColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Close button
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

File? existingFile(String? path) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  return file.existsSync() ? file : null;
}
