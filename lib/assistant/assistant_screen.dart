// lib/assistant/assistant_screen.dart
//
// The Assistant tab: a one-time setup (download), a short start-up, and then the chat.
// The assistant runs on the phone with no internet: the answers come from Daleel's own offline guide.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data.dart' show groupsOf, interests;
import '../screens/detail_screen.dart';
import '../theme.dart';
import '../itinerary/itinerary_screen.dart';
import '../itinerary/my_itineraries_screen.dart';
import '../ui.dart';
import 'assistant_controller.dart';
import 'markdown_lite.dart';
import 'markdown_lite_parse.dart';

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AssistantController()..start(),
        child: const _AssistantView(),
      );
}

class _AssistantView extends StatelessWidget {
  const _AssistantView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AssistantController>();
    final t = context.watch<AppState>().t;
    final Widget body;
    switch (c.phase) {
      case AssistantPhase.starting:
        body = _Centered(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(t('a_starting'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(t('a_starting_note'),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedBrown)),
          ],
        );
      case AssistantPhase.needsSetup:
        body = _Centered(
          children: [
            const Icon(Icons.auto_awesome, size: 44, color: terracotta),
            const SizedBox(height: 16),
            Text(t('a_setup_title'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(t('a_setup_body'),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedBrown)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: c.install,
              icon: const Icon(Icons.download),
              label: Text(t('a_setup_button')),
            ),
          ],
        );
      case AssistantPhase.downloading:
        body = _Centered(
          children: [
            Text(t('a_downloading'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(c.downloadStep == 1 ? t('a_dl_step1') : t('a_dl_step2'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedBrown)),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: c.downloadStep == 2 ? c.progress : null),
            if (c.downloadStep == 2 && c.progress != null) ...[
              const SizedBox(height: 8),
              Text('${(c.progress! * 100).round()}%'),
            ],
            const SizedBox(height: 20),
            Text(t('a_dl_keep_open'),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: mutedBrown)),
          ],
        );
      case AssistantPhase.failed:
        final download = c.failure == AssistantFailure.download;
        final unsupported = c.failure == AssistantFailure.unsupported;
        body = ErrorPanel(
          title: t('a_err_title'),
          body: unsupported ? t('a_err_unsupported') : (download ? t('a_err_download') : t('a_err_start')),
          retryLabel: unsupported ? null : t('retry'),
          onRetry: unsupported ? null : (download ? c.install : c.start),
          icon: Icons.smart_toy_outlined,
        );
      case AssistantPhase.ready:
        body = const _Chat();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t('tab_assistant')),
        actions: [
          if (c.phase == AssistantPhase.ready)
            IconButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyItinerariesScreen())),
              icon: const Icon(Icons.route_outlined),
              tooltip: t('it_my'),
            ),
          if (c.phase == AssistantPhase.ready && c.messages.isNotEmpty)
            IconButton(
              onPressed: c.answering
                  ? null
                  : () async {
                      if (await _confirmNewChat(context, t)) c.newChat();
                    },
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: t('a_new_chat'),
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Clearing the conversation also loses itineraries that were not saved, so it asks first.
Future<bool> _confirmNewChat(BuildContext context, String Function(String) t) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(t('a_new_chat_ask')),
      content: Text(t('a_new_chat_body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('it_cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(t('a_new_chat'))),
      ],
    ),
  );
  return ok == true;
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}

class _Chat extends StatefulWidget {
  const _Chat();

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Follows the answer as it is written, unless the visitor has scrolled up to read something earlier.
  void _toBottom({bool force = false}) {
    if (!force && _scroll.hasClients && _scroll.position.maxScrollExtent - _scroll.position.pixels > 160) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _submit([String? text]) {
    final c = context.read<AssistantController>();
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || c.answering) return;
    _input.clear();
    c.send(q, userContext: visitorNote(context.read<AppState>(), DateTime.now()));
    _toBottom(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AssistantController>();
    final t = context.watch<AppState>().t;
    if (c.answering) _toBottom();
    return Column(
      children: [
        Expanded(
          child: c.messages.isEmpty
              ? _Welcome(onPick: _submit)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: c.messages.length,
                  itemBuilder: (context, i) => _Bubble(
                    message: c.messages[i],
                    waiting: c.answering && i == c.messages.length - 1,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(t('a_disclaimer'),
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: mutedBrown)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _submit,
                  decoration: InputDecoration(hintText: t('a_hint')), // the rest comes from the app's input theme
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: c.answering ? null : _submit,
                tooltip: t('a_send'),
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<AppState>().t;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 40, color: terracotta),
            const SizedBox(height: 14),
            Text(t('a_welcome_title'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(t('a_welcome_body'),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedBrown)),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in const ['a_try1', 'a_try2', 'a_try3', 'a_try4'])
                  ActionChip(label: Text(t(k)), onPressed: () => onPick(t(k))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.waiting});
  final ChatMessage message;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.t;
    final lang = app.language;
    final theme = Theme.of(context);
    final mine = message.fromUser;
    final text = message.failed && message.text.isEmpty ? t('a_err_chat') : message.text;
    final rtl = looksArabic(text);
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          color: mine ? theme.colorScheme.primaryContainer : parchment,
          borderRadius: BorderRadius.circular(18),
          border: mine ? null : Border.all(color: duneLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isEmpty && waiting)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(t('a_thinking'), style: theme.textTheme.bodyMedium?.copyWith(color: mutedBrown)),
                ],
              )
            else
              Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: mine ? Text(text, style: theme.textTheme.bodyMedium) : MarkdownLite(text),
              ),
            if (!mine && message.plan != null && !waiting) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ItineraryScreen(
                      plan: message.plan!,
                      savedId: message.savedItineraryId,
                      // Saving again from this answer updates the same itinerary instead of making a copy.
                      onSaved: (id) => message.savedItineraryId = id,
                    ),
                  ),
                ),
                icon: const Icon(Icons.route_outlined),
                label: Text(t('it_create')),
              ),
            ],
            if (!mine && message.places.isNotEmpty && !waiting) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final p in message.places)
                    ActionChip(
                      avatar: const Icon(Icons.place_outlined, size: 18),
                      label: Text(lang == 'ar' && p.nameAr != null ? p.nameAr! : p.name),
                      tooltip: t('a_places'),
                      onPressed: () => DetailScreen.openById(context, p.attractionId),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
/// A short note about the visitor for the assistant: what they told the welcome quiz, and the day and time now,
/// so answers can fit their interests and budget and say what is open. Written in English for the model.
String visitorNote(AppState s, DateTime now) {
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
      'November', 'December'];
  final parts = <String>[];
  final style = s.travelStyle;
  if (style != null) parts.add(style == 'solo' ? 'travelling alone' : 'travelling as a $style');
  final names = [for (final i in (groupsOf(s.tagIds).toList()..sort())) interests[i].en];
  if (names.isNotEmpty) parts.add('interested in ${names.join(', ')}');
  final b = s.budget;
  if (b != null) parts.add(b == 0 ? 'prefers free places' : 'budget up to ${b.round()} AED per place per person');
  final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  final today = '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]} ${now.year}, $time';
  final about = parts.isEmpty ? '' : 'About the visitor: ${parts.join('; ')}. ';
  return '[${about}Now: $today in Al Ain. Use this only where it helps the answer.]';
}
