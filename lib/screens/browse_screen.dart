import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data.dart';
import '../theme.dart';
import '../ui.dart';
import '../widgets.dart';
import 'detail_screen.dart';

/// Orders places by how well they match the quiz answers (the rule is in data.dart, where it is tested).
List<Attraction> _rank(List<Attraction> all, AppState s) =>
    rankAttractions(all, s.tagIds, s.travelStyle, s.budget);

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late Future<(List<Attraction>, List<PlaceCategoryRow>)> _future = _load();
  final _search = TextEditingController();
  String _query = '';
  int? _category;

  static Future<(List<Attraction>, List<PlaceCategoryRow>)> _load() async =>
      (await loadAttractions(), await loadCategories());

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearAll() {
    _search.clear();
    setState(() {
      _query = '';
      _category = null;
    });
  }

  bool _matches(Attraction a) {
    if (_category != null && a.categoryId != _category) return false;
    if (_query.isEmpty) return true;
    // Both languages, names and taglines, with Arabic spelling variants folded (searchKey).
    return [
      a.pick('en', 'name'),
      a.pick('ar', 'name'),
      a.pick('en', 'tagline'),
      a.pick('ar', 'tagline'),
    ].any((text) => searchKey(text).contains(_query));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      // The page is named like its tab; the greeting sits under it.
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.t('tab_browse')),
            if (s.userName.isNotEmpty)
              Text(
                '${s.t('hello')} ${s.userName}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedBrown),
              ),
          ],
        ),
        toolbarHeight: s.userName.isEmpty ? null : 72,
      ),
      body: FutureBuilder<(List<Attraction>, List<PlaceCategoryRow>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorPanel(
              title: s.t('load_error_title'),
              body: s.t('load_error_body'),
              retryLabel: s.t('retry'),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final loading = !snap.hasData;
          final (places, categories) = snap.data ?? (const <Attraction>[], const <PlaceCategoryRow>[]);
          final items = _rank(places, s).where(_matches).toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: s.t('search'),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: s.t('clear_search'),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    onChanged: (v) => setState(() => _query = searchKey(v)),
                  ),
                ),
              ),
              if (categories.isNotEmpty)
                SliverToBoxAdapter(
                  child: _CategoryRow(
                    categories: categories,
                    selected: _category,
                    onSelected: (id) => setState(() => _category = id),
                  ),
                ),
              if (loading)
                SliverList.list(children: const [_CardSkeleton(), _CardSkeleton()])
              else if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorPanel(
                    icon: Icons.travel_explore,
                    title: s.t('no_match_title'),
                    body: s.t('no_match_body'),
                    retryLabel: s.t('clear_filters'),
                    onRetry: _clearAll,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) => _PlaceCard(items[i], categories),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "All" plus the eight place categories, with the same icons and colours
/// the map uses.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });
  final List<PlaceCategoryRow> categories;
  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // Grows with the phone's text size, so chip labels are not cut off at large text.
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(40) + 12,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(
              label: Text(s.t('all')),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                avatar: Icon(PlaceCategory.icon(c.id),
                    size: 18, color: PlaceCategory.color(c.id)),
                showCheckmark: false,
                label: Text(c.name(s.language)),
                selected: selected == c.id,
                onSelected: (on) => onSelected(on ? c.id : null),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard(this.a, this.categories);
  final Attraction a;
  final List<PlaceCategoryRow> categories;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final l = s.language;
    final tagline = a.pick(l, 'tagline');
    final matched = a.tags.intersection(s.tagIds);
    final matches = matched.isNotEmpty;
    // Say why a place is suggested: the first of the visitor's interests it matches.
    final reason = interests.where((g) => g.tags.any(matched.contains)).firstOrNull;
    final overBudget = s.budget != null && a.price > s.budget!;
    final category = categories.where((c) => c.id == a.categoryId).firstOrNull;
    final saved = s.isFavorite(a.id);
    final open = a.openAt(DateTime.now());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => DetailScreen(a))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                attractionImage(a, 172),
                if (a.unesco)
                  PositionedDirectional(
                    start: 12,
                    top: 12,
                    child: UnescoBadge(arabic: l == 'ar', compact: true),
                  ),
                PositionedDirectional(
                  end: 6,
                  top: 6,
                  child: IconButton(
                    tooltip: s.t(saved ? 'saved' : 'save'),
                    isSelected: saved,
                    style: IconButton.styleFrom(
                      backgroundColor: parchment.withValues(alpha: 0.92),
                      foregroundColor: terracottaDeep,
                    ),
                    icon: const Icon(Icons.bookmark_border),
                    selectedIcon: const Icon(Icons.bookmark),
                    onPressed: () => s.toggleFavorite(a.id),
                  ),
                ),
              ],
            ),
            // One item for screen readers (name, tagline, price, open now, why it is suggested) instead of
            // six separate ones; the Save button stays its own item.
            MergeSemantics(
              child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.pick(l, 'name'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
                  if (tagline.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedBrown),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      if (category != null)
                        MetaItem(
                          icon: PlaceCategory.icon(category.id),
                          label: category.name(l),
                          color: PlaceCategory.color(category.id),
                        ),
                      MetaItem(icon: Icons.confirmation_number_outlined, label: priceLabel(a, s)),
                      if (open != null)
                        MetaItem(
                          icon: Icons.schedule,
                          label: s.t(open ? 'open_now' : 'closed_now'),
                          color: open ? oasis : null,
                        ),
                      if (a.ladiesOnly)
                        MetaItem(icon: Icons.woman_outlined, label: s.t('ladies_only')),
                      if (overBudget)
                        MetaItem(icon: Icons.info_outline, label: s.t('over_budget'))
                      else if (matches)
                        MetaItem(
                          icon: Icons.favorite_outline,
                          label: reason == null
                              ? s.t('for_you')
                              : '${s.t('for_you_short')} · ${l == 'ar' ? reason.ar : reason.en}',
                          color: oasis,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 172, radius: 0),
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 20, width: 190),
                    SizedBox(height: 10),
                    SkeletonBox(height: 12),
                    SizedBox(height: 6),
                    SkeletonBox(height: 12, width: 220),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
