/// Data models and exceptions for the Smriti ML VoiceBot companion.
library;

/// Unified response from a conversational turn (POST /v1/conversation/voice).
class VoiceResponse {
  const VoiceResponse({
    required this.requestId,
    required this.sessionId,
    required this.responseText,
    required this.language,
    this.transcript = '',
    this.jobId,
    this.jobStatus = 'NOT_REQUESTED',
    this.audioId,
    this.audioUrl,
    this.audioAvailable = false,
    this.kind = 'CONVERSATION',
    this.action = 'NO_ACTION',
  });

  factory VoiceResponse.fromJson(Map<String, dynamic> json) {
    return VoiceResponse(
      requestId: json['request_id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      responseText: json['response_text'] as String? ?? '',
      language: json['language'] as String? ?? '',
      transcript: json['transcript'] as String? ?? '',
      jobId: json['job_id'] as String?,
      jobStatus: json['job_status'] as String? ?? 'NOT_REQUESTED',
      audioId: json['audio_id'] as String?,
      audioUrl: json['audio_url'] as String?,
      audioAvailable: json['audio_available'] as bool? ?? false,
      kind: json['kind'] as String? ?? 'CONVERSATION',
      action: json['action'] as String? ?? 'NO_ACTION',
    );
  }

  final String requestId;
  final String sessionId;
  final String responseText;
  final String language;
  final String transcript;
  final String? jobId;
  final String jobStatus;
  final String? audioId;
  final String? audioUrl;
  final bool audioAvailable;
  final String kind;
  final String action;

  bool get hasTtsJob => jobId != null && jobId!.isNotEmpty;
}

/// Asynchronous TTS job status (GET /v1/voice/jobs/{job_id}).
class VoiceJobStatus {
  const VoiceJobStatus({
    required this.jobId,
    required this.status,
    required this.language,
    this.audioId,
    this.audioUrl,
    this.errorCode,
    this.audioExpired = false,
  });

  factory VoiceJobStatus.fromJson(Map<String, dynamic> json) {
    return VoiceJobStatus(
      jobId: json['job_id'] as String? ?? '',
      status: (json['status'] as String? ?? '').toLowerCase(),
      language: json['language'] as String? ?? '',
      audioId: json['audio_id'] as String?,
      audioUrl: json['audio_url'] as String?,
      errorCode: json['error_code'] as String?,
      audioExpired: json['audio_expired'] as bool? ?? false,
    );
  }

  final String jobId;
  final String status;
  final String language;
  final String? audioId;
  final String? audioUrl;
  final String? errorCode;
  final bool audioExpired;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
  bool get isPending => status == 'queued' || status == 'processing';
}

/// Proactive welcome turn response (POST /v1/conversation/welcome).
class WelcomeResponse {
  const WelcomeResponse({
    required this.requestId,
    required this.sessionId,
    required this.responseText,
    required this.language,
    this.jobId,
    this.jobStatus = 'NOT_REQUESTED',
    this.audioId,
    this.audioUrl,
    this.audioAvailable = false,
  });

  factory WelcomeResponse.fromJson(Map<String, dynamic> json) {
    return WelcomeResponse(
      requestId: json['request_id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      responseText: json['response_text'] as String? ?? '',
      language: json['language'] as String? ?? '',
      jobId: json['job_id'] as String?,
      jobStatus: json['job_status'] as String? ?? 'NOT_REQUESTED',
      audioId: json['audio_id'] as String?,
      audioUrl: json['audio_url'] as String?,
      audioAvailable: json['audio_available'] as bool? ?? false,
    );
  }

  final String requestId;
  final String sessionId;
  final String responseText;
  final String language;
  final String? jobId;
  final String jobStatus;
  final String? audioId;
  final String? audioUrl;
  final bool audioAvailable;
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

abstract class VoiceBotException implements Exception {
  const VoiceBotException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VoiceBotApiException extends VoiceBotException {
  const VoiceBotApiException({
    required this.statusCode,
    required String message,
    this.body,
  }) : super(message);

  final int statusCode;
  final String? body;

  @override
  String toString() => 'VoiceBotApiException($statusCode): $message';
}

class VoiceBotAuthException extends VoiceBotApiException {
  const VoiceBotAuthException({
    required super.statusCode,
    required super.message,
    super.body,
  });
}

class VoiceBotNetworkException extends VoiceBotException {
  const VoiceBotNetworkException(super.message, [this.cause]);
  final Object? cause;

  @override
  String toString() => 'VoiceBotNetworkException: $message';
}

class VoiceBotTimeoutException extends VoiceBotException {
  const VoiceBotTimeoutException(super.message);

  @override
  String toString() => 'VoiceBotTimeoutException: $message';
}
