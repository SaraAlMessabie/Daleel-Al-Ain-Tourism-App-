import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data.dart';
import '../theme.dart';
import '../ui.dart';
import '../widgets.dart';
import 'detail_screen.dart';
import 'quiz_screen.dart';

const kAppVersion = '1.0.0';

/// Profile tab: a short trip summary, saved places, then grouped settings rows.
/// Tapping a setting opens a bottom sheet; every change is saved immediately.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Future<List<Attraction>> _places = loadAttractions();

  // ---- helpers -----------------------------------------------------------
  static Future<void> _update(AppState s,
          {String? lang, String? style, int? budget, Set<int>? tags}) =>
      s.save(
        lang: lang ?? s.language,
        style: style ?? s.travelStyle,
        budget: budget == null ? s.budget : (budget < 0 ? null : budget.toDouble()),
        tags: tags ?? s.tagIds,
      );

  static String _styleName(AppState s) =>
      s.travelStyle == null ? s.t('p_none') : s.t(s.travelStyle!);

  static String _budgetName(AppState s) {
    final b = s.budget;
    if (b == null) return s.t('b_any');
    if (b == 0) return s.t('b_free');
    return b <= 50 ? s.t('b50') : s.t('b100');
  }

  static String _interestSummary(AppState s) {
    final ar = s.language == 'ar';
    final n = [
      for (final i in (groupsOf(s.tagIds).toList()..sort()))
        ar ? interests[i].ar : interests[i].en
    ];
    if (n.isEmpty) return s.t('p_none');
    if (n.length <= 2) return n.join(ar ? '، ' : ', ');
    return '${n.take(2).join(ar ? '، ' : ', ')} +${n.length - 2}';
  }

  void _sheet(String titleKey, Widget Function(AppState s) body) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Consumer<AppState>(
        builder: (ctx, s, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t(titleKey), style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                body(s),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(s.t('p_close')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(Attraction a) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(a)));

  void _allSaved(List<Attraction> saved) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final s = context.read<AppState>();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(s.t('p_saved'), style: Theme.of(ctx).textTheme.titleLarge),
                ),
                for (final a in saved)
                  _SavedTile(a: a, onTap: () {
                    Navigator.pop(ctx);
                    _open(a);
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- screen ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: Text(s.t('tab_profile'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Header(s),
          const SizedBox(height: 24),
          _GroupTitle(s.t('p_saved')),
          FutureBuilder<List<Attraction>>(
            future: _places,
            builder: (context, snap) {
              final all = snap.data ?? const <Attraction>[];
              final saved = all.where((a) => s.isFavorite(a.id)).toList();
              if (saved.isEmpty) {
                return _Group(children: [
                  _Row(
                    icon: Icons.bookmark_border,
                    title: s.t('p_saved_none'),
                    subtitle: s.t('p_saved_hint'),
                  ),
                ]);
              }
              return _Group(children: [
                for (final a in saved.take(3)) _SavedTile(a: a, onTap: () => _open(a)),
                if (saved.length > 3)
                  _Row(
                    icon: Icons.bookmarks_outlined,
                    title: '${s.t('p_saved')} (${saved.length})',
                    onTap: () => _allSaved(saved),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 24),
          _GroupTitle(s.t('p_prefs')),
          _Group(children: [
            _Row(
              icon: Icons.language,
              title: s.t('language'),
              value: s.language == 'ar' ? 'العربية' : 'English',
              onTap: () => _sheet(
                'language',
                (s) => LanguageChoice(
                    value: s.language, onChanged: (v) => _update(s, lang: v)),
              ),
            ),
            _Row(
              icon: Icons.group_outlined,
              title: s.t('travel_style'),
              value: _styleName(s),
              onTap: () => _sheet(
                'travel_style',
                (s) => StyleChoice(
                    value: s.travelStyle, onChanged: (v) => _update(s, style: v)),
              ),
            ),
            _Row(
              icon: Icons.favorite_border,
              title: s.t('interests'),
              value: _interestSummary(s),
              onTap: () => _sheet(
                'interests',
                (s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('p_hint_interests'),
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    InterestChoice(
                      selected: groupsOf(s.tagIds),
                      onChanged: (g) => _update(s, tags: tagsOf(g)),
                    ),
                  ],
                ),
              ),
            ),
            _Row(
              icon: Icons.payments_outlined,
              title: s.t('budget'),
              value: _budgetName(s),
              onTap: () => _sheet(
                'budget',
                (s) => BudgetChoice(
                  value: s.budget == null ? -1 : s.budget!.toInt(),
                  onChanged: (v) => _update(s, budget: v),
                ),
              ),
            ),
            _Row(
              icon: Icons.replay,
              title: s.t('retake'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QuizScreen(retake: true))),
            ),
          ]),
          const SizedBox(height: 24),
          _GroupTitle(s.t('p_app')),
          _Group(children: [
            _Row(
              icon: Icons.cloud_off_outlined,
              title: s.t('p_offline'),
              subtitle: s.t('about_text'),
            ),
            _Row(
              icon: Icons.info_outline,
              title: s.t('about_app'),
              value: kAppVersion,
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Daleel',
                applicationVersion: kAppVersion,
                applicationIcon: const DaleelLogo(size: 48),
                children: [Text(s.t('about_text'))],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Text(s.t('prefs_saved'), style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Trip summary: a band of Al Sadu weave, the trip title and one line of
/// what Daleel knows about you. The details live in the rows below.
class _Header extends StatelessWidget {
  const _Header(this.s);
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final summary = [
      _ProfileScreenState._styleName(s),
      _ProfileScreenState._budgetName(s),
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SaduBand(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('p_traveller'), style: text.headlineSmall),
                const SizedBox(height: 4),
                Text(summary, style: text.bodyMedium?.copyWith(color: mutedBrown)),
                const SizedBox(height: 10),
                MetaItem(
                  icon: Icons.bookmark_border,
                  label: '${s.t('p_saved')}: ${s.favoriteIds.length}',
                  color: terracotta,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 8, bottom: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: terracottaDeep, fontWeight: FontWeight.w700)),
      );
}

/// A rounded card holding rows separated by thin dividers.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 56),
              children[i],
            ],
          ],
        ),
      );
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.a, required this.onTap});
  final Attraction a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final tagline = a.pick(s.language, 'tagline');
    return ListTile(
      leading: Icon(PlaceCategory.icon(a.categoryId), color: PlaceCategory.color(a.categoryId)),
      title: Text(a.pick(s.language, 'name')),
      subtitle: tagline.isEmpty
          ? null
          : Text(tagline, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, color: mutedBrown),
      onTap: onTap,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.value,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? value; // shown on the trailing side
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: onTap == null && value == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: mutedBrown)),
                  ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: mutedBrown),
                ],
              ],
            ),
      onTap: onTap,
    );
  }
}
