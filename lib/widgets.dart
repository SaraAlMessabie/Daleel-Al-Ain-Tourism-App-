import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'data.dart';
import 'theme.dart';
import 'ui.dart';

/// A row of single-choice chips.
class ChoiceGroup<V> extends StatelessWidget {
  const ChoiceGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<(String, V)> options; // (label, value)
  final V? value;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(o.$1),
              selected: o.$2 == value,
              onSelected: (_) => onChanged(o.$2),
            ),
        ],
      );
}

class LanguageChoice extends StatelessWidget {
  const LanguageChoice({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ChoiceGroup<String>(
        options: const [('English', 'en'), ('العربية', 'ar')],
        value: value,
        onChanged: onChanged,
      );
}

class StyleChoice extends StatelessWidget {
  const StyleChoice({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    return ChoiceGroup<String>(
      options: [
        (t('solo'), 'solo'),
        (t('couple'), 'couple'),
        (t('family'), 'family'),
        (t('friends'), 'friends'),
      ],
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Budget values: 0 = free only, 50, 100, -1 = no limit.
class BudgetChoice extends StatelessWidget {
  const BudgetChoice({super.key, required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    return ChoiceGroup<int>(
      options: [(t('b_free'), 0), (t('b50'), 50), (t('b100'), 100), (t('b_any'), -1)],
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Up to [max] interests. Once the limit is reached the other chips are
/// shown as unavailable and a short note explains why, instead of taps
/// silently doing nothing.
class InterestChoice extends StatelessWidget {
  const InterestChoice({
    super.key,
    required this.selected,
    required this.onChanged,
    this.max = 4,
  });
  final Set<int> selected; // indexes into `interests`
  final ValueChanged<Set<int>> onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final ar = s.language == 'ar';
    final full = selected.length >= max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < interests.length; i++)
              FilterChip(
                label: Text(ar ? interests[i].ar : interests[i].en),
                selected: selected.contains(i),
                onSelected: full && !selected.contains(i)
                    ? null
                    : (on) {
                        final next = {...selected};
                        on ? next.add(i) : next.remove(i);
                        onChanged(next);
                      },
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: full
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Semantics(
                    liveRegion: true,
                    child: MetaItem(icon: Icons.info_outline, label: s.t('q_limit')),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Photo from assets/images. If the file is missing, shows a sand panel with
/// the category's icon so the layout still reads as intentional.
Widget attractionImage(Attraction a, double height, {String? semanticLabel}) {
  final path = (a.row['image_path'] as String?) ?? '';
  return Image.asset(
    'assets/$path',
    height: height,
    width: double.infinity,
    fit: BoxFit.cover,
    cacheWidth: 800, // decode at phone size, not full camera size: saves a lot of RAM
    semanticLabel: semanticLabel,
    excludeFromSemantics: semanticLabel == null,
    errorBuilder: (_, __, ___) => Container(
      height: height,
      width: double.infinity,
      color: sandDeep,
      child: Icon(
        PlaceCategory.icon(a.categoryId),
        size: 44,
        color: PlaceCategory.color(a.categoryId).withValues(alpha: 0.7),
      ),
    ),
  );
}

String priceLabel(Attraction a, AppState s) =>
    a.price == 0 ? s.t('free') : '${a.price.toStringAsFixed(0)} ${s.t('aed')}';

/// Save / Saved toggle used on the place screen and the map card.
class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.attractionId, this.expanded = false});
  final int attractionId;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final saved = s.isFavorite(attractionId);
    void toggle() {
      s.toggleFavorite(attractionId);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(s.t(saved ? 'unsaved_msg' : 'saved_msg')),
          duration: const Duration(seconds: 2),
        ));
    }

    final icon = Icon(saved ? Icons.bookmark : Icons.bookmark_border);
    final label = Text(s.t(saved ? 'saved' : 'save'));
    final button = saved
        ? FilledButton.tonalIcon(onPressed: toggle, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: toggle, icon: icon, label: label);
    return Semantics(
      toggled: saved,
      child: expanded ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// The Daleel logo. Put your file at assets/logo/logo.png.
/// If the file is missing, a simple icon is shown instead so the app still runs.
class DaleelLogo extends StatelessWidget {
  const DaleelLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/logo/logo.png',
        height: size,
        width: size,
        cacheWidth: 400,
        semanticLabel: 'Daleel',
        errorBuilder: (_, __, ___) => Icon(
          Icons.explore,
          size: size,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
}
