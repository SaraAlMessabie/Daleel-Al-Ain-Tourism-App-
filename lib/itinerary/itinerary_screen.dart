// lib/itinerary/itinerary_screen.dart
//
// One itinerary: the days and stops the assistant suggested, each with the facts from Daleel's guide (opening
// hours, price, visit time), warnings, a total computed in code, and buttons to remove or move a stop,
// change the people and budget, and save. The same screen shows a saved itinerary.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../screens/detail_screen.dart';
import '../theme.dart';
import 'itinerary_core.dart';
import 'itinerary_store.dart';

String _fill(String s, String x) => s.replaceAll('{x}', x);

String money(double v, String Function(String) t) => v == 0 ? t('free') : '${v.round()} ${t('aed')}';

String warnText(String Function(String) t, Warn w) {
  switch (w.kind) {
    case WarnKind.opensLater:
      return _fill(t('it_w_opens'), w.detail);
    case WarnKind.closesEarlier:
      return _fill(t('it_w_closes'), w.detail);
    case WarnKind.repeated:
      return _fill(t('it_w_repeat'), _fill(t('it_day'), w.detail.replaceAll(RegExp(r'\D'), '')));
    case WarnKind.notInGuide:
      return t('it_w_unknown');
    case WarnKind.longDay:
      return _fill(t('it_w_long'), w.detail);
    case WarnKind.overBudget:
      return _fill(t('it_w_budget'), w.detail);
  }
}

Future<bool> confirmDelete(BuildContext context, String Function(String) t) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(t('it_delete_ask')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('it_cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('it_delete'))),
      ],
    ),
  );
  return ok == true;
}

class ItineraryScreen extends StatefulWidget {
  const ItineraryScreen({super.key, required this.plan, this.savedId});

  final Plan plan;

  /// Set when this is a saved itinerary being opened again.
  final int? savedId;

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  late final Plan plan = widget.plan;
  final _budget = TextEditingController();
  int? _savedId;
  bool _dirty = true;

  @override
  void initState() {
    super.initState();
    _savedId = widget.savedId;
    _dirty = widget.savedId == null;
    final b = plan.budgetAed;
    if (b != null) _budget.text = b.round().toString();
  }

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  void _edit(VoidCallback change) => setState(() {
        change();
        recheck(plan);
        _dirty = true;
      });

  void _setBudget(String v) {
    final n = double.tryParse(v.trim());
    _edit(() => plan.budgetAed = (n == null || n <= 0) ? null : n);
  }

  Future<void> _save() async {
    final t = context.read<AppState>().t;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ItineraryStore.save(plan, title: plan.title ?? t('it_default_title'), existingId: _savedId);
      if (!mounted) return;
      setState(() {
        _savedId = id;
        _dirty = false;
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t('it_saved_snack')), duration: const Duration(seconds: 2)));
    } catch (e, st) {
      debugPrint('Itinerary: save failed: $e\n$st');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t('it_save_failed'))));
    }
  }

  Future<void> _delete() async {
    final id = _savedId;
    if (id == null) return;
    if (!await confirmDelete(context, context.read<AppState>().t)) return;
    await ItineraryStore.delete(id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String _placeName(PlanStop s, String lang) {
    final f = s.facts;
    if (f != null && lang == 'ar' && f.nameAr.trim().isNotEmpty) return f.nameAr;
    return s.name;
  }

  Widget _chip(BuildContext context, String text, {bool warning = true}) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(warning ? Icons.warning_amber_rounded : Icons.info_outline, size: 16),
      label: Text(text, style: Theme.of(context).textTheme.bodySmall),
      backgroundColor: warning ? scheme.errorContainer : parchment,
    );
  }

  Widget _stop(BuildContext context, AppState s, int di, int si) {
    final t = s.t;
    final theme = Theme.of(context);
    final day = plan.days[di];
    final stop = day.stops[si];
    final f = stop.facts;
    final facts = <String>[
      if (f != null && f.hoursText.isNotEmpty) f.hoursText,
      if (f != null) money(stop.price, t),
      if (f != null) '${stop.minutes} ${t('min')}',
    ].join('  \u00B7  ');
    final closed = f?.closedNote;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: stop.inGuide ? () => DetailScreen.openById(context, stop.placeId!) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(_placeName(stop, s.language),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: stop.inGuide ? terracotta : null,
                          )),
                    ),
                  ),
                ),
                PopupMenuButton<Slot>(
                  tooltip: t('it_slot'),
                  onSelected: (v) => _edit(() => setSlot(plan, di, si, v)),
                  itemBuilder: (_) => [
                    for (final v in Slot.values) PopupMenuItem(value: v, child: Text(t('it_slot_${v.name}'))),
                  ],
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(t('it_slot_${stop.slot.name}'), style: theme.textTheme.bodySmall),
                    avatar: const Icon(Icons.schedule, size: 16),
                  ),
                ),
              ],
            ),
            if (facts.isNotEmpty) Text(facts, style: theme.textTheme.bodySmall?.copyWith(color: mutedBrown)),
            if (closed != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${t('it_note')}: $closed', style: theme.textTheme.bodySmall?.copyWith(color: mutedBrown)),
              ),
            if (stop.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(stop.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              ),
            if (stop.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 0, children: [
                  for (final w in stop.warnings) _chip(context, warnText(t, w)),
                ]),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: si > 0 ? () => _edit(() => moveStop(plan, di, si, -1)) : null,
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: t('it_up'),
                ),
                IconButton(
                  onPressed: si < day.stops.length - 1 ? () => _edit(() => moveStop(plan, di, si, 1)) : null,
                  icon: const Icon(Icons.arrow_downward),
                  tooltip: t('it_down'),
                ),
                IconButton(
                  onPressed: () => _edit(() => removeStop(plan, di, si)),
                  icon: const Icon(Icons.close),
                  tooltip: t('it_remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _day(BuildContext context, AppState s, int di) {
    final t = s.t;
    final theme = Theme.of(context);
    final day = plan.days[di];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 2),
        child: Text(
          day.title.isEmpty ? _fill(t('it_day'), '${day.number}') : '${_fill(t('it_day'), '${day.number}')}  \u00B7  ${day.title}',
          style: theme.textTheme.titleLarge,
        ),
      ),
      Text(
        '${day.stops.length} ${t('it_stops')}  \u00B7  ${day.minutes} ${t('min')}  \u00B7  ${money(day.pricePerPerson, t)}',
        style: theme.textTheme.bodySmall?.copyWith(color: mutedBrown),
      ),
      if (day.warnings.isNotEmpty)
        Wrap(spacing: 6, children: [for (final w in day.warnings) _chip(context, warnText(t, w))]),
      if (day.stops.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(t('it_day_empty'), style: theme.textTheme.bodyMedium?.copyWith(color: mutedBrown)),
        ),
      for (var si = 0; si < day.stops.length; si++) _stop(context, s, di, si),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = s.t;
    final theme = Theme.of(context);
    final unknown = plan.days.fold<int>(0, (a, d) => a + d.stops.where((x) => !x.inGuide).length);
    return Scaffold(
      appBar: AppBar(
        title: Text(plan.title ?? t('it_title')),
        actions: [
          if (_savedId != null)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: t('it_delete')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(t('it_people'), style: theme.textTheme.titleMedium),
                        const Spacer(),
                        IconButton(
                          onPressed: plan.people > 1 ? () => _edit(() => plan.people--) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${plan.people}', style: theme.textTheme.titleMedium),
                        IconButton(
                          onPressed: plan.people < 20 ? () => _edit(() => plan.people++) : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _budget,
                      keyboardType: TextInputType.number,
                      onChanged: _setBudget,
                      decoration: InputDecoration(labelText: t('it_budget')),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _Figure(label: t('it_per_person'), value: money(plan.pricePerPerson, t))),
                        Expanded(child: _Figure(label: t('it_total'), value: money(plan.total, t))),
                      ],
                    ),
                    if (plan.budgetAed != null) ...[
                      const SizedBox(height: 8),
                      if (plan.warnings.isEmpty)
                        _chip(context, t('it_ok_budget'), warning: false)
                      else
                        for (final w in plan.warnings) _chip(context, warnText(t, w)),
                    ],
                    const SizedBox(height: 8),
                    Text(t('it_cost_note'), style: theme.textTheme.bodySmall?.copyWith(color: mutedBrown)),
                  ],
                ),
              ),
            ),
            for (var di = 0; di < plan.days.length; di++) ..._day(context, s, di),
            if (unknown > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_fill(t('it_unknown_note'), '$unknown'),
                    style: theme.textTheme.bodySmall?.copyWith(color: mutedBrown)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(t('it_disclaimer'), style: theme.textTheme.bodySmall?.copyWith(color: mutedBrown)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _dirty ? _save : null,
            icon: Icon(_dirty ? Icons.bookmark_add_outlined : Icons.check),
            label: Text(_dirty ? t('it_save') : t('saved')),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: mutedBrown)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleLarge),
      ],
    );
  }
}