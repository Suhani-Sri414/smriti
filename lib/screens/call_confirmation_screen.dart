import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../core/app_services.dart';
import 'my_people_screen.dart';

/// Screen 13: Call Confirmation.
///
/// Designed for a 1280×800 landscape tablet.
/// Accessible confirmation screen displayed when the elder taps "Call [Name]"
/// on the Home screen. Shows a large avatar, the contact's name, a prominent
/// "Call [Name]" button, and an outlined "Not now" button to return home.
class CallConfirmationScreen extends StatefulWidget {
  const CallConfirmationScreen({
    super.key,
    required this.services,
    this.contactName,
    this.contactPhone,
    this.contactPhotoPath,
    this.onPlaceCall,
  });

  final AppServices services;
  final String? contactName;
  final String? contactPhone;
  final String? contactPhotoPath;

  /// Injected for testing so phone dialer / intent can be verified without
  /// real telephony hardware.
  final Future<void> Function(String phone)? onPlaceCall;

  @override
  State<CallConfirmationScreen> createState() => _CallConfirmationScreenState();
}

class _CallConfirmationScreenState extends State<CallConfirmationScreen> {
  late Future<_ContactInfo> _contactFuture;

  @override
  void initState() {
    super.initState();
    _contactFuture = _resolveContact();
  }

  Future<_ContactInfo> _resolveContact() async {
    final nameFromConfig =
        await widget.services.db.appConfigsDao.getValue('primaryContactName');
    final phoneFromConfig =
        await widget.services.db.appConfigsDao.getValue('primaryContactPhone');

    final name = widget.contactName ??
        (nameFromConfig != null && nameFromConfig.isNotEmpty
            ? nameFromConfig
            : 'Bina');
    final phone = widget.contactPhone ?? phoneFromConfig ?? '';

    String? photoPath = widget.contactPhotoPath;
    if (photoPath == null) {
      // Check if there is a matching person in People table for photo
      final people = await widget.services.contentRepo.getPeople();
      for (final p in people) {
        if (p.name.toLowerCase() == name.toLowerCase() &&
            p.photoPath.isNotEmpty) {
          photoPath = p.photoPath;
          break;
        }
      }
    }

    return _ContactInfo(
      name: name,
      phone: phone,
      photoPath: photoPath,
    );
  }

  Future<void> _makeCall(String name, String phone) async {
    if (widget.onPlaceCall != null) {
      await widget.onPlaceCall!(phone);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (phone.isNotEmpty && !kIsWeb && Platform.isAndroid) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.CALL',
          data: 'tel:$phone',
        );
        await intent.launch();
        if (mounted) Navigator.of(context).pop();
        return;
      } catch (e) {
        debugPrint('Could not place direct call via CALL intent: $e');
        try {
          final dialIntent = AndroidIntent(
            action: 'android.intent.action.DIAL',
            data: 'tel:$phone',
          );
          await dialIntent.launch();
          if (mounted) Navigator.of(context).pop();
          return;
        } catch (e2) {
          debugPrint('Could not launch dialer intent: $e2');
        }
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calling $name...'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.leafGreen,
        ),
      );
    }
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
                  const Text(
                    '13',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE5A93C),
                      fontFamily: 'Noto Sans',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Call confirmation',
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

            // Main Green Card
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A7C59),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x25000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: FutureBuilder<_ContactInfo>(
                  future: _contactFuture,
                  builder: (context, snapshot) {
                    final info = snapshot.data ??
                        _ContactInfo(
                          name: widget.contactName ?? 'Bina',
                          phone: widget.contactPhone ?? '',
                          photoPath: widget.contactPhotoPath,
                        );

                    final photo = existingFile(info.photoPath);

                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Large Avatar with white ring border
                          Container(
                            width: 176,
                            height: 176,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE4DAC3),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 4,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x18000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: photo != null
                                ? Image.file(
                                    photo,
                                    fit: BoxFit.cover,
                                    width: 176,
                                    height: 176,
                                  )
                                : _buildDefaultSilhouette(),
                          ),
                          const SizedBox(height: 24),

                          // Contact Name
                          Text(
                            info.name,
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontFamily: 'Noto Sans',
                            ),
                          ),
                          const SizedBox(height: 38),

                          // Action Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 1. Call Button
                              InkWell(
                                key: const Key('confirm_call_button'),
                                onTap: () => _makeCall(info.name, info.phone),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 240,
                                    maxWidth: 320,
                                    minHeight: 72,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFDF8),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x20000000),
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.phone_rounded,
                                            color: Color(0xFF2F5A3E),
                                            size: 28,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'Call ${info.name}',
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF2F5A3E),
                                              fontFamily: 'Noto Sans',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),

                              // 2. Not Now Button
                              InkWell(
                                key: const Key('cancel_call_button'),
                                onTap: () => Navigator.of(context).pop(),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 220,
                                    maxWidth: 280,
                                    minHeight: 72,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFFE4DAC3)
                                          .withValues(alpha: 0.8),
                                      width: 2,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Not now',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        fontFamily: 'Noto Sans',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  Widget _buildDefaultSilhouette() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Head
        Positioned(
          top: 38,
          child: Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              color: Color(0xFF1F3A60),
              shape: BoxShape.circle,
            ),
          ),
        ),

        // Shoulders
        Positioned(
          bottom: -10,
          child: Container(
            width: 118,
            height: 68,
            decoration: const BoxDecoration(
              color: Color(0xFF1F3A60),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(59),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactInfo {
  const _ContactInfo({
    required this.name,
    required this.phone,
    this.photoPath,
  });

  final String name;
  final String phone;
  final String? photoPath;
}
