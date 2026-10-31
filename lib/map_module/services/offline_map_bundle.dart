import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:http/http.dart' as http;

import 'asset_range_http_client.dart';

class OfflineMapBundle {
  OfflineMapBundle._({required this.style, required this.archiveClient});

  static const String _archiveAsset = 'assets/maps/al_ain.pmtiles';
  static const String _styleAsset = 'assets/maps/al_ain_style.json';
  static const String _archiveUrl = 'https://offline.local/al_ain.pmtiles';

  final vt.Style style;
  final http.Client archiveClient;

  static Future<OfflineMapBundle> load({
    bool isArabic = false,
    bool isDark = false,
  }) async {
    final byteData = await rootBundle.load(_archiveAsset);
    final bytes = Uint8List.sublistView(
      byteData.buffer.asUint8List(),
      byteData.offsetInBytes,
      byteData.offsetInBytes + byteData.lengthInBytes,
    );
    final client = AssetRangeHttpClient(bytes);

    final provider = await vt.PmTilesVectorTileProvider.open(
      _archiveUrl,
      client: client,
      logger: const vt.Logger.console(),
    );

    final styleJson = Map<String, dynamic>.from(
      jsonDecode(await rootBundle.loadString(_styleAsset)) as Map,
    );
    _localizeAndThemeStyle(styleJson, isArabic: isArabic, isDark: isDark);
    final styleClient = _MemoryJsonClient(jsonEncode(styleJson));

    try {
      final style = await vt.StyleReader(
        uri: 'https://offline.local/al_ain_style.json',
        httpClient: styleClient,
        cache: false,
        logger: const vt.Logger.console(),
        resolveProvider: (sourceId) async {
          return sourceId == 'protomaps' ? provider : null;
        },
      ).read();

      styleClient.close();

      return OfflineMapBundle._(style: style, archiveClient: client);
    } catch (_) {
      styleClient.close();
      provider.dispose();
      client.close();
      rethrow;
    }
  }

  static void _localizeAndThemeStyle(
    Map<String, dynamic> styleJson, {
    required bool isArabic,
    required bool isDark,
  }) {
    final labelExpression = _labelExpression(isArabic: isArabic);
    final layers = styleJson['layers'] as List<dynamic>? ?? const [];
    for (final rawLayer in layers) {
      if (rawLayer is! Map) continue;
      final layer = Map<String, dynamic>.from(rawLayer);
      final id = layer['id'] as String? ?? '';
      if (id == 'place-labels' || id == 'road-labels') {
        final layout = Map<String, dynamic>.from(
          layer['layout'] as Map? ?? const <String, dynamic>{},
        );
        layout['text-field'] = labelExpression;
        layer['layout'] = layout;
      }
      if (isDark) _applyDarkLayerColors(layer, id);
      final index = layers.indexOf(rawLayer);
      layers[index] = layer;
    }
    layers.addAll(<Map<String, Object?>>[
      <String, Object?>{
        'id': 'water-labels',
        'type': 'symbol',
        'source': 'protomaps',
        'source-layer': 'water',
        'minzoom': 10,
        'layout': <String, Object?>{
          'text-field': labelExpression,
          'text-size': 10,
          'text-font': <String>['Noto Sans Regular'],
        },
        'paint': <String, Object?>{
          'text-color': isDark ? '#86C8DE' : '#31758D',
          'text-halo-color': isDark ? '#101512' : '#FFFFFF',
          'text-halo-width': 2,
        },
      },
      <String, Object?>{
        'id': 'poi-labels',
        'type': 'symbol',
        'source': 'protomaps',
        'source-layer': 'pois',
        'minzoom': 13,
        'layout': <String, Object?>{
          'text-field': labelExpression,
          'text-size': 10,
          'text-font': <String>['Noto Sans Regular'],
        },
        'paint': <String, Object?>{
          'text-color': isDark ? '#E8EEE9' : '#3D3A35',
          'text-halo-color': isDark ? '#101512' : '#FFFFFF',
          'text-halo-width': 2,
        },
      },
    ]);
    // Theme.name is part of flutter_map_vector_tiles' rendered-tile cache
    // identity. Keep every language/theme combination distinct so switching
    // languages cannot reuse tiles whose labels were already laid out.
    final language = isArabic ? 'Arabic' : 'English';
    final brightness = isDark ? 'Dark' : 'Light';
    styleJson['name'] = 'Al Ain Offline $language $brightness';
  }

  static List<Object> _labelExpression({required bool isArabic}) {
    if (isArabic) {
      return <Object>[
        'coalesce',
        <Object>['get', 'name:ar'],
        <Object>['get', 'name'],
      ];
    }

    return <Object>[
      'coalesce',
      <Object>['get', 'name:en'],
      <Object>['get', 'pgf:name:en'],
      <Object>['get', 'name_int'],
      <Object>['get', 'name'],
    ];
  }

  static void _applyDarkLayerColors(Map<String, dynamic> layer, String id) {
    final paint = Map<String, dynamic>.from(
      layer['paint'] as Map? ?? const <String, dynamic>{},
    );
    switch (id) {
      case 'background':
        paint['background-color'] = '#101512';
      case 'earth':
        paint['fill-color'] = '#151b17';
      case 'landcover':
        paint['fill-color'] = '#203b2a';
        paint['fill-opacity'] = 0.78;
      case 'landuse':
        paint['fill-color'] = '#262d28';
        paint['fill-opacity'] = 0.86;
      case 'water':
        paint['fill-color'] = '#173e50';
      case 'buildings':
        paint['fill-color'] = '#343b37';
        paint['fill-outline-color'] = '#414b45';
      case 'roads-casing':
        paint['line-color'] = '#171c19';
      case 'roads':
        paint['line-color'] = '#505a54';
      case 'boundaries':
        paint['line-color'] = '#9c7ba0';
      case 'place-labels':
        paint['text-color'] = '#E8EEE9';
        paint['text-halo-color'] = '#101512';
      case 'road-labels':
        paint['text-color'] = '#D0D8D2';
        paint['text-halo-color'] = '#101512';
    }
    layer['paint'] = paint;
  }

  void dispose() {
    style.dispose();
    archiveClient.close();
  }
}

class _MemoryJsonClient extends http.BaseClient {
  _MemoryJsonClient(String json) : _bytes = utf8.encode(json);

  final List<int> _bytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(_bytes),
      200,
      request: request,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }
}
