import 'package:permission_handler/permission_handler.dart';

/// Outcomes of a microphone permission request.
enum VoiceBotPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

/// Abstract gateway for permission checks to allow deterministic testing.
abstract class MicrophonePermissionGateway {
  Future<bool> hasPermission();
  Future<VoiceBotPermissionStatus> requestPermission();
  Future<bool> openSettings();
}

/// Production implementation backed by `package:permission_handler`.
class DeviceMicrophonePermissionGateway implements MicrophonePermissionGateway {
  const DeviceMicrophonePermissionGateway();

  @override
  Future<bool> hasPermission() async {
    try {
      return await Permission.microphone.isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<VoiceBotPermissionStatus> requestPermission() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) return VoiceBotPermissionStatus.granted;
      if (status.isPermanentlyDenied) {
        return VoiceBotPermissionStatus.permanentlyDenied;
      }
      if (status.isRestricted) return VoiceBotPermissionStatus.restricted;
      return VoiceBotPermissionStatus.denied;
    } catch (_) {
      return VoiceBotPermissionStatus.denied;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }
}

/// Top-level helper service for VoiceBot microphone permissions.
class VoiceBotPermissions {
  VoiceBotPermissions({
    MicrophonePermissionGateway? gateway,
  }) : _gateway = gateway ?? const DeviceMicrophonePermissionGateway();

  final MicrophonePermissionGateway _gateway;

  Future<bool> hasMicrophonePermission() => _gateway.hasPermission();

  Future<VoiceBotPermissionStatus> requestMicrophonePermission() =>
      _gateway.requestPermission();

  Future<bool> openSettings() => _gateway.openSettings();
}
