import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data.dart';
import '../ui.dart';
import '../widgets.dart';

/// The 4-question cold-start quiz. Also used for "Retake the quiz" in Profile.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, this.retake = false});
  final bool retake;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _pc = PageController();
  int _page = 0;
  late String _lang;
  String? _style;
  Set<int> _groups = {};
  int? _budget;
  bool _saving = false; // stops a double-tap on "Finish" from saving twice
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _lang = s.language;
    _name.text = s.userName;
    if (widget.retake) {
      _style = s.travelStyle;
      _groups = groupsOf(s.tagIds);
      _budget = s.budget == null ? -1 : s.budget!.toInt();
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _valid => switch (_page) {
        0 => true,
        1 => _style != null,
        2 => _groups.isNotEmpty,
        _ => _budget != null,
      };

  void _go(int delta) {
    setState(() => _page += delta);
    _pc.animateToPage(_page,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _next() async {
    if (_page < 3) return _go(1);
    if (_saving) return;
    final s = context.read<AppState>();
    final b = _budget!;
    setState(() => _saving = true);
    try {
      await s.setUserName(_name.text);
      await s.save(
        lang: _lang,
        style: _style,
        budget: b < 0 ? null : b.toDouble(),
        tags: tagsOf(_groups),
      );
      if (widget.retake && mounted) Navigator.pop(context);
    } catch (e, st) {
      // The answers were not saved: stay on the last question and let the button work again.
      debugPrint('Quiz: save failed: $e\n$st');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _back() {
    if (_page == 0) {
      if (widget.retake) Navigator.pop(context);
      return;
    }
    _go(-1);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: (_page + 1) / 4),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    semanticsLabel: '${_page + 1} / 4',
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pc,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Question(
                    logo: true,
                    title: s.t('q_lang'),
                    sub: s.t('q_lang_sub'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LanguageChoice(
                          value: _lang,
                          onChanged: (v) {
                            setState(() => _lang = v);
                            s.setLanguage(v); // switch the screen language immediately
                          },
                        ),
                        const SizedBox(height: 28),
                        Text(s.t('q_name'), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _name,
                          maxLength: 30,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: s.t('q_name_hint'),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Question(
                    title: s.t('q_who'),
                    sub: s.t('q_who_sub'),
                    child: StyleChoice(
                      value: _style,
                      onChanged: (v) => setState(() => _style = v),
                    ),
                  ),
                  _Question(
                    title: s.t('q_interests'),
                    sub: s.t('q_interests_sub'),
                    child: InterestChoice(
                      selected: _groups,
                      onChanged: (v) => setState(() => _groups = v),
                    ),
                  ),
                  _Question(
                    title: s.t('q_budget'),
                    sub: s.t('q_budget_sub'),
                    child: BudgetChoice(
                      value: _budget,
                      onChanged: (v) => setState(() => _budget = v),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_page > 0 || widget.retake)
                    TextButton(onPressed: _back, child: Text(s.t('back'))),
                  const Spacer(),
                  FilledButton(
                    onPressed: _valid && !_saving ? _next : null,
                    child: Text(_page == 3 ? s.t('finish') : s.t('next')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.title,
    required this.sub,
    required this.child,
    this.logo = false,
  });
  final String title, sub;
  final bool logo;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (logo) ...[
              const SizedBox(height: 8),
              const Center(child: DaleelLogo(size: 110)),
              const SizedBox(height: 24),
              const SaduBand(height: 12),
              const SizedBox(height: 28),
            ],
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(sub,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            child,
          ],
        ),
      );
}
