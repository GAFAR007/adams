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
    case 'fire_damage_cleaning':
      return const PublicServiceVisualData(
        icon: Icons.local_fire_department_rounded,
        imageUrl:
            'https://images.pexels.com/photos/36409941/pexels-photo-36409941.jpeg?auto=compress&cs=tinysrgb&w=1600',
        eyebrow: LocalizedText(
          en: 'After fire and smoke impact',
          de: 'Nach Brand- und Rauchschaden',
        ),
        summary: LocalizedText(
          en: 'Careful fire damage cleaning to remove soot, smoke residue, and the mess left behind after an incident.',
          de: 'Sorgfältige Brandschadenreinigung zur Entfernung von Ruß, Rauchrückständen und Verschmutzungen nach einem Vorfall.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'Soot, ash, and smoke residue from affected rooms and surfaces',
            de: 'Ruß, Asche und Rauchrückstände in betroffenen Räumen und auf Oberflächen',
          ),
          LocalizedText(
            en: 'Practical clean-up support before restoration, repairs, or re-occupation',
            de: 'Praktische Reinigung vor Sanierung, Reparatur oder Wiederbezug',
          ),
          LocalizedText(
            en: 'Handled discreetly with attention to safety, containment, and documentation',
            de: 'Diskret durchgeführt mit Blick auf Sicherheit, Abschottung und Dokumentation',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Soot removal', de: 'Rußentfernung'),
          LocalizedText(en: 'Smoke residue', de: 'Rauchrückstände'),
          LocalizedText(
            en: 'Post-incident clean-up',
            de: 'Reinigung nach Vorfall',
          ),
        ],
      );
    case 'needle_sweeps_sharps_cleanups':
      return const PublicServiceVisualData(
        icon: Icons.health_and_safety_rounded,
        imageUrl:
            'https://images.pexels.com/photos/4099087/pexels-photo-4099087.jpeg?auto=compress&cs=tinysrgb&w=1600',
        eyebrow: LocalizedText(
          en: 'Sharps and hazardous items',
          de: 'Sharps und gefährliche Fundstücke',
        ),
        summary: LocalizedText(
          en: 'Targeted needle sweeps and sharps clean-ups for entrances, grounds, shared areas, and sensitive properties.',
          de: 'Gezielte Nadelsuche und Sharps-Beseitigung für Eingänge, Außenflächen, Gemeinschaftsbereiche und sensible Objekte.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'Safe collection of needles, blades, and exposed sharps',
            de: 'Sichere Aufnahme von Nadeln, Klingen und offen liegenden Sharps',
          ),
          LocalizedText(
            en: 'Suitable for housing blocks, public areas, business sites, and access routes',
            de: 'Geeignet für Wohnanlagen, öffentliche Bereiche, Gewerbestandorte und Zugangswege',
          ),
          LocalizedText(
            en: 'Helps restore safer day-to-day access for residents, staff, and visitors',
            de: 'Hilft dabei, sichere Zugänge für Bewohner, Mitarbeitende und Besucher wiederherzustellen',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Needle sweeps', de: 'Nadelsuche'),
          LocalizedText(en: 'Sharps disposal', de: 'Sharps-Entsorgung'),
          LocalizedText(en: 'Safer access', de: 'Sicherere Zugänge'),
        ],
      );
    case 'hoarding_cleanups':
      return const PublicServiceVisualData(
        icon: Icons.inventory_2_rounded,
        imageUrl:
            'https://images.pexels.com/photos/6195288/pexels-photo-6195288.jpeg?auto=compress&cs=tinysrgb&w=1600',
        eyebrow: LocalizedText(
          en: 'Resetting overwhelmed spaces',
          de: 'Überforderte Räume neu ordnen',
        ),
        summary: LocalizedText(
          en: 'Sensitive hoarding clean-ups that help clear heavily affected rooms and bring properties back toward a usable standard.',
          de: 'Einfühlsame Hoarding-Reinigungen, die stark betroffene Räume entlasten und Objekte wieder in einen nutzbaren Zustand bringen.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'Decluttering, waste removal, and practical cleaning after heavy buildup',
            de: 'Entrümpelung, Entsorgung und praktische Reinigung bei starker Ansammlung',
          ),
          LocalizedText(
            en: 'Works for homes, tenancies, inherited properties, and managed units',
            de: 'Geeignet für Wohnungen, Mietobjekte, Nachlassobjekte und verwaltete Einheiten',
          ),
          LocalizedText(
            en: 'Approached discreetly and without adding pressure to difficult situations',
            de: 'Diskret umgesetzt, ohne schwierige Situationen zusätzlich zu belasten',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Decluttering', de: 'Entrümpelung'),
          LocalizedText(en: 'Waste removal', de: 'Entsorgung'),
          LocalizedText(en: 'Property reset', de: 'Objekt-Reset'),
        ],
      );
    case 'trauma_decomposition_cleanups':
      return const PublicServiceVisualData(
        icon: Icons.healing_rounded,
        imageUrl:
            'https://images.pexels.com/photos/4176365/pexels-photo-4176365.jpeg?auto=compress&cs=tinysrgb&w=1600',
        eyebrow: LocalizedText(
          en: 'Sensitive scene remediation',
          de: 'Sensible Einsatzstellen-Reinigung',
        ),
        summary: LocalizedText(
          en: 'Specialist trauma and decomposition clean-ups focused on safe remediation, discretion, and restoring affected properties.',
          de: 'Spezialisierte Trauma- und Leichenfundortreinigung mit Fokus auf sichere Wiederherstellung, Diskretion und die Rückführung betroffener Objekte.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'For unexpected deaths, traumatic incidents, and serious contamination events',
            de: 'Für Todesfälle, traumatische Ereignisse und schwere Kontaminationslagen',
          ),
          LocalizedText(
            en: 'Handled with controlled cleaning, deodorisation, and careful site attention',
            de: 'Durchgeführt mit kontrollierter Reinigung, Geruchsbehandlung und sorgfältiger Objektbetreuung',
          ),
          LocalizedText(
            en: 'Suitable for private homes, rentals, workplaces, and managed properties',
            de: 'Geeignet für Privatwohnungen, Mietobjekte, Arbeitsplätze und verwaltete Immobilien',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Sensitive clean-up', de: 'Sensible Reinigung'),
          LocalizedText(en: 'Odour treatment', de: 'Geruchsbehandlung'),
          LocalizedText(
            en: 'Safe remediation',
            de: 'Sichere Wiederherstellung',
          ),
        ],
      );
    case 'infection_control_cleaning':
      return const PublicServiceVisualData(
        icon: Icons.coronavirus_rounded,
        imageUrl:
            'https://images.pexels.com/photos/4099267/pexels-photo-4099267.jpeg?auto=compress&cs=tinysrgb&w=1600',
        eyebrow: LocalizedText(
          en: 'Targeted hygiene control',
          de: 'Gezielte Hygienekontrolle',
        ),
        summary: LocalizedText(
          en: 'Infection control cleaning for high-risk touchpoints, contaminated areas, and environments that need a stricter hygiene response.',
          de: 'Infektionsschutzreinigung für Hochrisiko-Kontaktflächen, kontaminierte Bereiche und Umgebungen mit erhöhten Hygieneanforderungen.',
        ),
        highlights: <LocalizedText>[
          LocalizedText(
            en: 'High-touch disinfection for rooms, washrooms, access points, and shared surfaces',
            de: 'Desinfektion von Räumen, Sanitärbereichen, Zugängen und häufig berührten Flächen',
          ),
          LocalizedText(
            en: 'Supports outbreak response, precautionary deep cleaning, and safer reopening',
            de: 'Unterstützt Ausbruchslagen, vorsorgliche Grundreinigung und eine sicherere Wiederöffnung',
          ),
          LocalizedText(
            en: 'Useful for workplaces, communal buildings, healthcare-adjacent spaces, and homes',
            de: 'Geeignet für Arbeitsplätze, Gemeinschaftsgebäude, gesundheitsnahe Bereiche und Wohnungen',
          ),
        ],
        metrics: <LocalizedText>[
          LocalizedText(en: 'Disinfection', de: 'Desinfektion'),
          LocalizedText(en: 'High-touch areas', de: 'Kontaktflächen'),
          LocalizedText(en: 'Safer reopening', de: 'Sicherer Neustart'),
        ],
      );
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
