// lib/itinerary/my_itineraries_screen.dart
//
// The list of saved itineraries. Tap one to open it; the bin deletes it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../ui.dart';
import 'itinerary_screen.dart';
import 'itinerary_store.dart';

class MyItinerariesScreen extends StatefulWidget {
  const MyItinerariesScreen({super.key});

  @override
  State<MyItinerariesScreen> createState() => _MyItinerariesScreenState();
}

class _MyItinerariesScreenState extends State<MyItinerariesScreen> {
  late Future<List<ItinerarySummary>> _future = ItineraryStore.list();

  void _reload() => setState(() => _future = ItineraryStore.list());

  Future<void> _open(ItinerarySummary item) async {
    final plan = await ItineraryStore.load(item.id);
    if (plan == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItineraryScreen(plan: plan, savedId: item.id)));
    if (mounted) _reload();
  }

  Future<void> _delete(ItinerarySummary item) async {
    if (!await confirmDelete(context, context.read<AppState>().t)) return;
    await ItineraryStore.delete(item.id);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('it_my'))),
      body: SafeArea(
        child: FutureBuilder<List<ItinerarySummary>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              debugPrint('Itineraries: could not load: ${snap.error}');
              return ErrorPanel(
                title: t('it_err_title'),
                body: t('it_err_body'),
                retryLabel: t('retry'),
                onRetry: _reload,
                icon: Icons.route_outlined,
              );
            }
            final items = snap.data ?? const <ItinerarySummary>[];
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(t('it_empty'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    onTap: () => _open(item),
                    title: Text(item.title, style: theme.textTheme.titleMedium),
                    subtitle: Text(
                      '${item.days} ${t('it_days')}  \u00B7  ${item.stops} ${t('it_stops')}  \u00B7  ${money(item.total, t)}',
                    ),
                    trailing: IconButton(
                      onPressed: () => _delete(item),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: t('it_delete'),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}