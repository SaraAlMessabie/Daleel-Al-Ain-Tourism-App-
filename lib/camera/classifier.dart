import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class Prediction {
  Prediction(this.label, this.confidence);
  final String label; // exact class name, matches attractions.model_label
  final double confidence; // 0..1
}

class ClassifyResult {
  ClassifyResult(this.top, this.notSure);
  final List<Prediction> top; // best first, up to 3
  final bool notSure; // true when the best guess is below the confidence limit
}

/// Photo -> 224x224 RGB numbers between 0 and 1.
/// Runs in a background isolate (via compute) so the screen does not freeze.
/// The ImageNet normalisation is already inside the .tflite model.
Float32List _prepare(String path) {
  final bytes = File(path).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) throw Exception('Could not read the photo');
  image = img.bakeOrientation(image); // fix phone rotation
  image = img.copyResize(
    image,
    width: 224,
    height: 224,
    interpolation: img.Interpolation.average, // closest to PIL's smooth downscaling
  );
  final out = Float32List(224 * 224 * 3);
  var i = 0;
  for (var y = 0; y < 224; y++) {
    for (var x = 0; x < 224; x++) {
      final p = image.getPixel(x, y);
      out[i++] = p.r / 255.0;
      out[i++] = p.g / 255.0;
      out[i++] = p.b / 255.0;
    }
  }
  return out;
}

/// MobileNetV3 (TFLite) -> 1280 numbers -> linear SVM -> 21 places.
class Classifier {
  Classifier._(this._interp, this._labels, this._w, this._b, this._temp, this.notSureBelow,
      this._centroids, this._scoreMin, this._simMin);

  static const dim = 1280;
  final Interpreter _interp;
  final List<String> _labels;
  final Float32List _w; // classes x dim, row by row
  final Float32List _b;
  final double _temp;
  final double notSureBelow;
  final Float32List? _centroids; // classes x dim, unit length (null with an old svm_head.json)
  final double _scoreMin; // best raw SVM score must reach this
  final double _simMin; // photo must be this close (cosine) to the winning place's average photo
  static const double minGap = 0.15; // best guess must beat the second by 15 points

  static Future<Classifier> load() async {
    final interp = await Interpreter.fromAsset('assets/model/mobilenetv3_embedder.tflite');
    final raw = await rootBundle.loadString('assets/model/svm_head.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;

    if ((j['embedding_dim'] as num).toInt() != dim) {
      throw Exception('svm_head.json expects ${j['embedding_dim']} numbers, the model gives $dim');
    }
    final labels = (j['class_names'] as List).cast<String>();
    final weights = j['weights'] as List;
    final w = Float32List(labels.length * dim);
    for (var c = 0; c < labels.length; c++) {
      final row = weights[c] as List;
      for (var d = 0; d < dim; d++) {
        w[c * dim + d] = (row[d] as num).toDouble();
      }
    }
    final b = Float32List.fromList(
        (j['bias'] as List).map((e) => (e as num).toDouble()).toList());
    final temp = (j['temperature'] as num?)?.toDouble() ?? 10.0;
    final limit = (j['not_sure_below'] as num?)?.toDouble() ?? 0.65;
    Float32List? cen;
    final cj = j['centroids'] as List?;
    if (cj != null) {
      cen = Float32List(labels.length * dim);
      for (var c = 0; c < labels.length; c++) {
        final row = cj[c] as List;
        for (var d = 0; d < dim; d++) {
          cen[c * dim + d] = (row[d] as num).toDouble();
        }
      }
    }
    final scoreMin = (j['score_min'] as num?)?.toDouble() ?? -double.infinity;
    final simMin = (j['sim_min'] as num?)?.toDouble() ?? -double.infinity;
    return Classifier._(interp, labels, w, b, temp, limit, cen, scoreMin, simMin);
  }

  Future<ClassifyResult> classify(String photoPath) async {
    final input = await compute(_prepare, photoPath);
    final output = [List<double>.filled(dim, 0.0)];
    _interp.run(input.reshape([1, 224, 224, 3]), output);
    final emb = output[0];

    // SVM scores = weights x embedding + bias
    final n = _labels.length;
    final scores = List<double>.filled(n, 0);
    for (var c = 0; c < n; c++) {
      var s = _b[c].toDouble();
      final base = c * dim;
      for (var d = 0; d < dim; d++) {
        s += _w[base + d] * emb[d];
      }
      scores[c] = s;
    }

    // Turn scores into a 0..1 confidence (softmax with the temperature fitted in Colab).
    final scaled = [for (final s in scores) s * _temp];
    final m = scaled.reduce(math.max);
    final exps = [for (final s in scaled) math.exp(s - m)];
    final sum = exps.reduce((a, b) => a + b);
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => exps[b].compareTo(exps[a]));
    final top = [
      for (final i in order.take(3)) Prediction(_labels[i], exps[i] / sum),
    ];
    // Be cautious: also say "Not sure" when the top two guesses are close,
    // because then the model is torn between two places.
    final close = top.length > 1 && (top[0].confidence - top[1].confidence) < minGap;

    // "Is this really one of my places?" checks (stop the app guessing on random photos).
    final best = order.first;
    final lowScore = scores[best] < _scoreMin;
    var lowSim = false;
    final cen = _centroids;
    if (cen != null) {
      var dot = 0.0, norm = 0.0;
      final base = best * dim;
      for (var d = 0; d < dim; d++) {
        dot += emb[d] * cen[base + d];
        norm += emb[d] * emb[d];
      }
      final sim = dot / math.sqrt(norm == 0 ? 1 : norm);
      lowSim = sim < _simMin;
      if (kDebugMode) {
        debugPrint('camera: score=${scores[best].toStringAsFixed(3)} (min ${_scoreMin.toStringAsFixed(3)}) '
            'match=${sim.toStringAsFixed(3)} (min ${_simMin.toStringAsFixed(3)}) '
            'conf=${top.first.confidence.toStringAsFixed(2)}');
      }
    }
    return ClassifyResult(
        top, top.first.confidence < notSureBelow || close || lowScore || lowSim);
  }

  void close() => _interp.close();
}
