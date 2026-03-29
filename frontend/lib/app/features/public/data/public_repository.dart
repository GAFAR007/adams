/// WHAT: Loads backend-driven company content for the public homepage.
/// WHY: Public business information should be sourced from the backend rather than embedded in widgets.
/// HOW: Fetch the public company-profile payload and map it into a typed model.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/public_company_profile.dart';
import '../../../core/network/api_client.dart';

final publicRepositoryProvider = Provider<PublicRepository>((ref) {
  return PublicRepository(ref.read(apiClientProvider));
});

final publicCompanyProfileProvider = FutureProvider<PublicCompanyProfileModel>((
  ref,
) {
  return ref.watch(publicRepositoryProvider).fetchCompanyProfile();
});

class PublicRepository {
  const PublicRepository(this._client);

  final ApiClient _client;

  Future<PublicCompanyProfileModel> fetchCompanyProfile() async {
    final response = await _client.getJson('/public/company-profile');
    return PublicCompanyProfileModel.fromJson(
      response['companyProfile'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
    );
  }
}
