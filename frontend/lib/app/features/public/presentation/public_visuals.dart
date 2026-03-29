library;

import 'package:flutter/material.dart';

import '../../../core/models/public_company_profile.dart';

class PublicServiceVisualData {
  const PublicServiceVisualData({
    required this.icon,
    required this.imageUrl,
    required this.eyebrow,
    required this.summary,
    required this.highlights,
    required this.metrics,
  });

  final IconData icon;
  final String imageUrl;
  final LocalizedText eyebrow;
  final LocalizedText summary;
  final List<LocalizedText> highlights;
  final List<LocalizedText> metrics;
}

class PublicPageVisualData {
  const PublicPageVisualData({
    required this.imageUrl,
    required this.kicker,
    required this.supportingLine,
  });

  final String imageUrl;
  final LocalizedText kicker;
  final LocalizedText supportingLine;
}

String publicServiceHeroTag(String serviceKey) {
  return 'public-service-visual-$serviceKey';
}

PublicServiceVisualData publicServiceVisualForKey(String serviceKey) {
  switch (serviceKey) {
    case 'building_cleaning':
      return const PublicServiceVisualData(
        icon: Icons.apartment_rounded,
        imageUrl:
            'https://images.unsplash.com/photo-1757904257714-4f9a7e64cde0?auto=format&fit=crop&w=1600&q=80',
        eyebrow: LocalizedText(
          en: 'Shared spaces and entrances',
          de: 'Gemeinschaftsflächen und Eingänge',
        ),
        summary: LocalizedText(
          en: 'Structured cleaning support for lobbies, circulation areas, and daily building touchpoints.',
          de: 'Strukturierte Reinigung für Lobbys, Verkehrsflächen und die täglichen Berührungspunkte im Gebäude.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'Lobbies, stairwells, lift areas, and entry zones',
            de: 'Lobbys, Treppenhäuser, Aufzüge und Eingangsbereiche',
          ),
          LocalizedText(
            en: 'Scheduled visits with a consistent presentation standard',
            de: 'Planbare Einsätze mit konstant professionellem Erscheinungsbild',
          ),
          LocalizedText(
            en: 'Suitable for residential blocks and commercial properties',
            de: 'Geeignet für Wohnanlagen und gewerbliche Immobilien',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Entrances', de: 'Eingänge'),
          LocalizedText(en: 'Common areas', de: 'Gemeinschaftsflächen'),
          LocalizedText(en: 'Routine upkeep', de: 'Regelmäßige Pflege'),
        ],
      );
    case 'window_cleaning':
      return const PublicServiceVisualData(
        icon: Icons.window_rounded,
        imageUrl:
            'https://images.unsplash.com/photo-1743269559568-c9823c89030f?auto=format&fit=crop&w=1600&q=80',
        eyebrow: LocalizedText(
          en: 'Glass, facade, and visibility',
          de: 'Glas, Fassade und klare Sicht',
        ),
        summary: LocalizedText(
          en: 'Clean glazing and facade-facing surfaces with a sharper, more professional finish.',
          de: 'Saubere Glas- und Fassadenflächen mit einem klareren und professionellen Gesamtbild.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'Interior and exterior window coverage',
            de: 'Innen- und Außenreinigung von Fenstern',
          ),
          LocalizedText(
            en: 'Ideal for frontage, office glazing, and shared facades',
            de: 'Ideal für Fronten, Büroverglasung und gemeinsame Fassaden',
          ),
          LocalizedText(
            en: 'Visual impact that clients and residents notice immediately',
            de: 'Ein sichtbarer Unterschied, den Kundschaft und Bewohner sofort wahrnehmen',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Interior glass', de: 'Innenverglasung'),
          LocalizedText(en: 'Exterior panes', de: 'Außenflächen'),
          LocalizedText(en: 'Facade detail', de: 'Fassadendetails'),
        ],
      );
    case 'office_cleaning':
      return const PublicServiceVisualData(
        icon: Icons.business_center_rounded,
        imageUrl:
            'https://images.unsplash.com/photo-1748050869375-a38a7bd50735?auto=format&fit=crop&w=1600&q=80',
        eyebrow: LocalizedText(
          en: 'Focused on productive workspaces',
          de: 'Für produktive Arbeitsumgebungen',
        ),
        summary: LocalizedText(
          en: 'Keep offices presentable, calm, and ready for staff, visitors, and day-to-day operations.',
          de: 'Büros bleiben gepflegt, ruhig und bereit für Mitarbeitende, Besuch und den täglichen Betrieb.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'Desks, meeting rooms, shared kitchens, and washrooms',
            de: 'Schreibtische, Besprechungsräume, Küchen und Sanitärbereiche',
          ),
          LocalizedText(
            en: 'Supports a cleaner client-facing and team-facing environment',
            de: 'Sorgt für ein sauberes Umfeld für Kundenkontakt und Teamarbeit',
          ),
          LocalizedText(
            en: 'Designed for recurring routines instead of one-off fixes',
            de: 'Ausgelegt auf wiederkehrende Routinen statt nur Einzeltermine',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Desks', de: 'Arbeitsplätze'),
          LocalizedText(en: 'Meeting rooms', de: 'Besprechungsräume'),
          LocalizedText(en: 'Shared spaces', de: 'Gemeinschaftsbereiche'),
        ],
      );
    case 'house_cleaning':
      return const PublicServiceVisualData(
        icon: Icons.house_rounded,
        imageUrl:
            'https://images.unsplash.com/photo-1758272421516-9593de0fb5bf?auto=format&fit=crop&w=1600&q=80',
        eyebrow: LocalizedText(
          en: 'Homes that feel ready again',
          de: 'Wohnräume, die wieder bereit wirken',
        ),
        summary: LocalizedText(
          en: 'Domestic cleaning support for occupied homes, regular upkeep, and move-related resets.',
          de: 'Haushaltsnahe Reinigung für bewohnte Wohnungen, regelmäßige Pflege und Umzugsphasen.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'Living areas, floors, kitchens, and practical reset work',
            de: 'Wohnbereiche, Böden, Küchen und praktische Grundreinigung',
          ),
          LocalizedText(
            en: 'Comfort-focused presentation without overcomplicating the process',
            de: 'Komfortorientiert und ohne unnötig komplizierten Ablauf',
          ),
          LocalizedText(
            en: 'Useful for recurring household support or preparation work',
            de: 'Geeignet für regelmäßige Haushaltsunterstützung oder Vorbereitungstermine',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Living rooms', de: 'Wohnbereiche'),
          LocalizedText(en: 'Move support', de: 'Umzugsphasen'),
          LocalizedText(en: 'Scheduled visits', de: 'Planbare Termine'),
        ],
      );
    default:
      return const PublicServiceVisualData(
        icon: Icons.cleaning_services_rounded,
        imageUrl:
            'https://images.unsplash.com/photo-1770816307800-72ba937620fe?auto=format&fit=crop&w=1600&q=80',
        eyebrow: LocalizedText(
          en: 'Professional facility support',
          de: 'Professioneller Facility-Support',
        ),
        summary: LocalizedText(
          en: 'A cleaner public presentation backed by a simple request flow.',
          de: 'Ein sauberer öffentlicher Auftritt mit einfachem Anfrageablauf.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'Residential and commercial support',
            de: 'Unterstützung für Privat- und Gewerbeobjekte',
          ),
          LocalizedText(
            en: 'Fast contact and clear routing',
            de: 'Schneller Kontakt und klare Wege',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Responsive', de: 'Reaktionsstark'),
          LocalizedText(en: 'Flexible', de: 'Flexibel'),
        ],
      );
  }
}

PublicPageVisualData publicPageVisualForKey(String pageKey) {
  switch (pageKey) {
    case 'about':
      return const PublicPageVisualData(
        imageUrl:
            'https://images.unsplash.com/photo-1757904257714-4f9a7e64cde0?auto=format&fit=crop&w=1600&q=80',
        kicker: LocalizedText(
          en: 'Clean, calm, and organised spaces',
          de: 'Saubere, ruhige und organisierte Räume',
        ),
        supportingLine: LocalizedText(
          en: 'A public-facing look that matches dependable day-to-day service.',
          de: 'Ein öffentlicher Auftritt, der zum verlässlichen Tagesgeschäft passt.',
        ),
      );
    case 'contact':
      return const PublicPageVisualData(
        imageUrl:
            'https://images.unsplash.com/photo-1770816307800-72ba937620fe?auto=format&fit=crop&w=1600&q=80',
        kicker: LocalizedText(
          en: 'Clear contact, clear next step',
          de: 'Klarer Kontakt, klarer nächster Schritt',
        ),
        supportingLine: LocalizedText(
          en: 'Reach the team quickly without searching across multiple sections.',
          de: 'Das Team schnell erreichen, ohne zwischen mehreren Bereichen zu suchen.',
        ),
      );
    case 'legal':
      return const PublicPageVisualData(
        imageUrl:
            'https://images.unsplash.com/photo-1769522836633-443c1dea15c9?auto=format&fit=crop&w=1600&q=80',
        kicker: LocalizedText(
          en: 'Business details kept tidy',
          de: 'Unternehmensangaben sauber strukturiert',
        ),
        supportingLine: LocalizedText(
          en: 'Core public information grouped into a cleaner, more trustworthy layout.',
          de: 'Wichtige öffentliche Angaben in einem klareren und vertrauenswürdigeren Layout.',
        ),
      );
    case 'services':
      return const PublicPageVisualData(
        imageUrl:
            'https://images.unsplash.com/photo-1748050869375-a38a7bd50735?auto=format&fit=crop&w=1600&q=80',
        kicker: LocalizedText(
          en: 'Service-led presentation',
          de: 'Leistungsorientierte Darstellung',
        ),
        supportingLine: LocalizedText(
          en: 'Visual cards make each service easier to browse before opening details.',
          de: 'Visuelle Karten machen jede Leistung leichter erfassbar, bevor Details geöffnet werden.',
        ),
      );
    default:
      return const PublicPageVisualData(
        imageUrl:
            'https://images.unsplash.com/photo-1757904257714-4f9a7e64cde0?auto=format&fit=crop&w=1600&q=80',
        kicker: LocalizedText(
          en: 'Professional public presence',
          de: 'Professioneller öffentlicher Auftritt',
        ),
        supportingLine: LocalizedText(
          en: 'A cleaner website flow for public information and service discovery.',
          de: 'Ein klarerer Webseitenfluss für öffentliche Informationen und Leistungen.',
        ),
      );
  }
}
