import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data.dart';
import '../theme.dart';
import '../ui.dart';
import '../widgets.dart';

/// The one place screen. Opened from Explore, the Camera result, Profile's
/// saved places and the map's place card.
class DetailScreen extends StatelessWidget {
  const DetailScreen(this.a, {super.key});
  final Attraction a;

  /// Opens the place screen for an attraction id (used by the map).
  static Future<void> openById(BuildContext context, int id) async {
    final a = await loadAttraction(id);
    if (a == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(a)));
  }

  void _toMap(BuildContext context, AppState s, {required bool directions}) {
    // Go back to the tabs, then open the Map tab on this place.
    Navigator.of(context).popUntil((r) => r.isFirst);
    s.showOnMap(a.id, directions: directions);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final l = s.language;
    final text = Theme.of(context).textTheme;
    final name = a.pick(l, 'name');
    final tagline = a.pick(l, 'tagline');
    final description = a.pick(l, 'description');
    final area = l == 'ar'
        ? (a.row['district_area_ar'] as String?) ?? (a.row['district_area'] as String?)
        : a.row['district_area'] as String?;
    final minutes = a.visitMinutes;

    final facts = <(IconData, String, String?)>[
      (Icons.schedule, s.t('hours'), a.row['opening_hours'] as String?),
      (Icons.wb_twilight, s.t('best_time'), a.row['best_time_to_visit'] as String?),
      (Icons.hourglass_bottom, s.t('visit_length'),
          minutes == null ? null : '${s.t('about')} $minutes ${s.t('min')}'),
      (Icons.checkroom, s.t('dress'), a.row['dress_code_note'] as String?),
      (Icons.location_on_outlined, s.t('area'), area),
    ].where((f) => f.$3 != null && f.$3!.trim().isNotEmpty).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: sand,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: parchment.withValues(alpha: 0.92),
                  foregroundColor: darkBrown,
                ),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const BackButtonIcon(),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: attractionImage(a, 280 + MediaQuery.paddingOf(context).top,
                  semanticLabel: name),
            ),
          ),
          const SliverToBoxAdapter(child: SaduBand(height: 10)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            sliver: SliverList.list(
              children: [
                if (a.unesco) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: UnescoBadge(arabic: l == 'ar'),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(name, style: text.headlineMedium),
                if (tagline.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(tagline, style: text.bodyLarge?.copyWith(color: mutedBrown)),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    MetaItem(
                      icon: Icons.confirmation_number_outlined,
                      label: '${s.t('entry')}: ${priceLabel(a, s)}',
                    ),
                    if (a.family)
                      MetaItem(icon: Icons.family_restroom, label: s.t('good_families')),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: a.hasLocation ? () => _toMap(context, s, directions: false) : null,
                    icon: const Icon(Icons.map_outlined),
                    label: Text(s.t('show_map')),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            a.hasLocation ? () => _toMap(context, s, directions: true) : null,
                        icon: const Icon(Icons.directions_outlined),
                        label: Text(s.t('directions')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: SaveButton(attractionId: a.id, expanded: true)),
                  ],
                ),
                if (!a.hasLocation) ...[
                  const SizedBox(height: 8),
                  MetaItem(icon: Icons.info_outline, label: s.t('no_coords')),
                ],
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text(s.t('about_place'), style: text.titleLarge),
                  const SizedBox(height: 8),
                  Text(description, style: text.bodyLarge),
                ],
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < facts.length; i++) ...[
                          if (i > 0) const Divider(indent: 56),
                          ListTile(
                            leading: Icon(facts[i].$1),
                            title: Text(facts[i].$2,
                                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(facts[i].$3!,
                                style: text.bodyMedium?.copyWith(color: darkBrown)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
