import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../camera/classifier.dart';
import '../data.dart';
import '../theme.dart';
import '../ui.dart';
import 'detail_screen.dart';

/// Take or choose a photo -> Daleel says which landmark it is and tells its story.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  Classifier? _clf;
  List<Attraction> _all = [];
  File? _photo;
  ClassifyResult? _result;
  bool _busy = false;
  String? _error;

  Attraction? _byLabel(String label) {
    for (final a in _all) {
      if (a.modelLabel == label) return a;
    }
    return null;
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600, // smaller photo = less memory
        imageQuality: 90,
      );
      if (x == null) return;
      setState(() {
        _busy = true;
        _error = null;
        _result = null;
        _photo = File(x.path);
      });
      _all = _all.isEmpty ? await loadAttractions() : _all;
      _clf ??= await Classifier.load(); // loaded only the first time it is needed
      final r = await _clf!.classify(x.path);
      if (mounted) setState(() => _result = r);
    } catch (e, st) {
      // Keep the technical detail in the log; show people a plain message.
      debugPrint('Camera error: $e\n$st');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _clf?.close();
    super.dispose();
  }

  void _open(Attraction a) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(a)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tab_camera'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_photo!, height: 240, fit: BoxFit.cover, cacheWidth: 800),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const SaduBand(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                    child: Column(
                      children: [
                        const Icon(Icons.center_focus_weak, size: 44, color: terracotta),
                        const SizedBox(height: 14),
                        Text(
                          s.t('cam_hint'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: Text(s.t('cam_take')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(s.t('cam_gallery')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy)
            Row(
              children: [
                const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text(s.t('cam_analyzing')),
              ],
            ),
          if (_error != null)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                leading: const Icon(Icons.no_photography_outlined, color: errorClay),
                title: Text(s.t('cam_error'),
                    style: Theme.of(context).textTheme.titleMedium),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(s.t('cam_error_body')),
                ),
              ),
            ),
          if (_result != null) _ResultView(result: _result!, byLabel: _byLabel, onOpen: _open),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.byLabel, required this.onOpen});
  final ClassifyResult result;
  final Attraction? Function(String) byLabel;
  final void Function(Attraction) onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final l = s.language;
    final title = Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold);

    // "Not sure" below the confidence limit (40%): show the closest matches instead.
    if (result.notSure) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('cam_not_sure'), style: title),
              const SizedBox(height: 8),
              Text(s.t('cam_not_sure_body')),
              const SizedBox(height: 12),
              Text(s.t('cam_closest'), style: Theme.of(context).textTheme.titleMedium),
              for (final p in result.top) _MatchTile(p: p, a: byLabel(p.label), onOpen: onOpen),
            ],
          ),
        ),
      );
    }

    final best = result.top.first;
    final a = byLabel(best.label);
    final pct = (best.confidence * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('cam_sure'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedBrown)),
            Text(a?.pick(l, 'name') ?? best.label, style: title),
            Text('$pct% ${s.t('cam_confidence')}', style: Theme.of(context).textTheme.bodySmall),
            if (a != null) ...[
              const SizedBox(height: 12),
              Text(s.t('cam_history'), style: Theme.of(context).textTheme.titleMedium),
              Text(a.pick(l, 'description')),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => onOpen(a), child: Text(s.t('cam_open'))),
            ],
          ],
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.p, required this.a, required this.onOpen});
  final Prediction p;
  final Attraction? a;
  final void Function(Attraction) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().language;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(a?.pick(l, 'name') ?? p.label),
      trailing: Text('${(p.confidence * 100).round()}%'),
      onTap: a == null ? null : () => onOpen(a!),
    );
  }
}
