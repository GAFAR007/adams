/// WHAT: Defines the backend-driven company profile used by the public homepage.
/// WHY: The landing page should render business data from MongoDB instead of embedding it in UI code.
/// HOW: Parse the public company-profile JSON into immutable localized and contact models.
library;

class LocalizedText {
  const LocalizedText({required this.en, required this.de});

  final String en;
  final String de;

  factory LocalizedText.fromJson(Map<String, dynamic>? json) {
    return LocalizedText(
      en: json?['en'] as String? ?? '',
      de: json?['de'] as String? ?? '',
    );
  }

  String resolve(String languageCode) {
    final preferred = languageCode == 'de' ? de : en;
    final fallback = languageCode == 'de' ? en : de;
    return preferred.isNotEmpty ? preferred : fallback;
  }
}

class PublicServiceItem {
  const PublicServiceItem({required this.key, required this.label});

  final String key;
  final LocalizedText label;

  factory PublicServiceItem.fromJson(Map<String, dynamic> json) {
    return PublicServiceItem(
      key: json['key'] as String? ?? '',
      label: LocalizedText.fromJson(json['label'] as Map<String, dynamic>?),
    );
  }
}

class PublicInfoStep {
  const PublicInfoStep({required this.title, required this.subtitle});

  final LocalizedText title;
  final LocalizedText subtitle;

  factory PublicInfoStep.fromJson(Map<String, dynamic> json) {
    return PublicInfoStep(
      title: LocalizedText.fromJson(json['title'] as Map<String, dynamic>?),
      subtitle: LocalizedText.fromJson(
        json['subtitle'] as Map<String, dynamic>?,
      ),
    );
  }
}

class PublicContactInfo {
  const PublicContactInfo({
    required this.addressLine1,
    required this.city,
    required this.postalCode,
    required this.country,
    required this.phone,
    required this.secondaryPhone,
    required this.email,
    required this.hoursLabel,
  });

  final String addressLine1;
  final String city;
  final String postalCode;
  final String country;
  final String phone;
  final String secondaryPhone;
  final String email;
  final LocalizedText hoursLabel;

  factory PublicContactInfo.fromJson(Map<String, dynamic> json) {
    return PublicContactInfo(
      addressLine1: json['addressLine1'] as String? ?? '',
      city: json['city'] as String? ?? '',
      postalCode: json['postalCode'] as String? ?? '',
      country: json['country'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      secondaryPhone: json['secondaryPhone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      hoursLabel: LocalizedText.fromJson(
        json['hoursLabel'] as Map<String, dynamic>?,
      ),
    );
  }
}

class PublicCompanyProfileModel {
  const PublicCompanyProfileModel({
    required this.id,
    required this.companyName,
    required this.legalName,
    required this.category,
    required this.tagline,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.adminLoginLabel,
    required this.createAccountLabel,
    required this.customerLoginLabel,
    required this.staffLoginLabel,
    required this.heroPanelTitle,
    required this.heroPanelSubtitle,
    required this.heroBullets,
    required this.servicesTitle,
    required this.serviceCardSubtitle,
    required this.serviceLabels,
    required this.howItWorksTitle,
    required this.howItWorksSteps,
    required this.contactSectionTitle,
    required this.contactSectionSubtitle,
    required this.serviceAreaLabel,
    required this.serviceAreaText,
    required this.contact,
    required this.primaryColorHex,
    required this.accentColorHex,
  });

  final String id;
  final String companyName;
  final String legalName;
  final LocalizedText category;
  final LocalizedText tagline;
  final LocalizedText heroTitle;
  final LocalizedText heroSubtitle;
  final LocalizedText adminLoginLabel;
  final LocalizedText createAccountLabel;
  final LocalizedText customerLoginLabel;
  final LocalizedText staffLoginLabel;
  final LocalizedText heroPanelTitle;
  final LocalizedText heroPanelSubtitle;
  final List<LocalizedText> heroBullets;
  final LocalizedText servicesTitle;
  final LocalizedText serviceCardSubtitle;
  final List<PublicServiceItem> serviceLabels;
  final LocalizedText howItWorksTitle;
  final List<PublicInfoStep> howItWorksSteps;
  final LocalizedText contactSectionTitle;
  final LocalizedText contactSectionSubtitle;
  final LocalizedText serviceAreaLabel;
  final LocalizedText serviceAreaText;
  final PublicContactInfo contact;
  final String primaryColorHex;
  final String accentColorHex;

  factory PublicCompanyProfileModel.fromJson(Map<String, dynamic> json) {
    return PublicCompanyProfileModel(
      id: json['id'] as String? ?? '',
      companyName: json['companyName'] as String? ?? '',
      legalName: json['legalName'] as String? ?? '',
      category: LocalizedText.fromJson(
        json['category'] as Map<String, dynamic>?,
      ),
      tagline: LocalizedText.fromJson(json['tagline'] as Map<String, dynamic>?),
      heroTitle: LocalizedText.fromJson(
        json['heroTitle'] as Map<String, dynamic>?,
      ),
      heroSubtitle: LocalizedText.fromJson(
        json['heroSubtitle'] as Map<String, dynamic>?,
      ),
      adminLoginLabel: LocalizedText.fromJson(
        json['adminLoginLabel'] as Map<String, dynamic>?,
      ),
      createAccountLabel: LocalizedText.fromJson(
        json['createAccountLabel'] as Map<String, dynamic>?,
      ),
      customerLoginLabel: LocalizedText.fromJson(
        json['customerLoginLabel'] as Map<String, dynamic>?,
      ),
      staffLoginLabel: LocalizedText.fromJson(
        json['staffLoginLabel'] as Map<String, dynamic>?,
      ),
      heroPanelTitle: LocalizedText.fromJson(
        json['heroPanelTitle'] as Map<String, dynamic>?,
      ),
      heroPanelSubtitle: LocalizedText.fromJson(
        json['heroPanelSubtitle'] as Map<String, dynamic>?,
      ),
      heroBullets: (json['heroBullets'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(LocalizedText.fromJson)
          .toList(),
      servicesTitle: LocalizedText.fromJson(
        json['servicesTitle'] as Map<String, dynamic>?,
      ),
      serviceCardSubtitle: LocalizedText.fromJson(
        json['serviceCardSubtitle'] as Map<String, dynamic>?,
      ),
      serviceLabels:
          (json['serviceLabels'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(PublicServiceItem.fromJson)
              .toList(),
      howItWorksTitle: LocalizedText.fromJson(
        json['howItWorksTitle'] as Map<String, dynamic>?,
      ),
      howItWorksSteps:
          (json['howItWorksSteps'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(PublicInfoStep.fromJson)
              .toList(),
      contactSectionTitle: LocalizedText.fromJson(
        json['contactSectionTitle'] as Map<String, dynamic>?,
      ),
      contactSectionSubtitle: LocalizedText.fromJson(
        json['contactSectionSubtitle'] as Map<String, dynamic>?,
      ),
      serviceAreaLabel: LocalizedText.fromJson(
        json['serviceAreaLabel'] as Map<String, dynamic>?,
      ),
      serviceAreaText: LocalizedText.fromJson(
        json['serviceAreaText'] as Map<String, dynamic>?,
      ),
      contact: PublicContactInfo.fromJson(
        json['contact'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      primaryColorHex: json['primaryColorHex'] as String? ?? '',
      accentColorHex: json['accentColorHex'] as String? ?? '',
    );
  }
}
