/// WHAT: Talks to the backend's public service-concierge endpoint.
/// WHY: The public booking chat should use a real backend AI turn instead of frontend-only canned text.
/// HOW: Post the current booking-step context and parse the assistant reply contract.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final publicServiceConciergeRepositoryProvider =
    Provider<PublicServiceConciergeRepository>((ref) {
      return PublicServiceConciergeRepository(ref.read(apiClientProvider));
    });

class PublicServiceConciergeReply {
  const PublicServiceConciergeReply({
    required this.assistantName,
    required this.reply,
    required this.nextStep,
    required this.readyForRegistration,
  });

  final String assistantName;
  final String reply;
  final String nextStep;
  final bool readyForRegistration;

  factory PublicServiceConciergeReply.fromJson(Map<String, dynamic> json) {
    return PublicServiceConciergeReply(
      assistantName: json['name'] as String? ?? 'Naima',
      reply: json['reply'] as String? ?? '',
      nextStep: json['nextStep'] as String? ?? 'firstName',
      readyForRegistration: json['readyForRegistration'] as bool? ?? false,
    );
  }
}

class PublicServiceConciergeRepository {
  const PublicServiceConciergeRepository(this._client);

  final ApiClient _client;

  Future<PublicServiceConciergeReply> fetchReply({
    required String languageCode,
    required String justCapturedStep,
    required String nextStep,
    String? serviceKey,
    String? serviceName,
    String? firstName,
    List<String> completedSteps = const <String>[],
  }) async {
    final response = await _client.postJson(
      '/public/service-concierge/reply',
      data: <String, dynamic>{
        'languageCode': languageCode,
        'justCapturedStep': justCapturedStep,
        'nextStep': nextStep,
        'serviceKey': serviceKey,
        'serviceName': serviceName,
        'firstName': firstName,
        'completedSteps': completedSteps,
      },
    );

    return PublicServiceConciergeReply.fromJson(
      response['assistant'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );
  }
}
