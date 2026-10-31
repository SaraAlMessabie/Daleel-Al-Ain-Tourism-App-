import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../models/road_route.dart';
import '../models/saved_trip.dart';
import 'app_storage_backend.dart';

class OfflineRouteCache {
  OfflineRouteCache({StorageBackend? backend})
    : _backend = backend ?? createStorageBackend();

  static const String _cacheKey = 'al_ain_road_route_cache_v1';
  static const int _maximumEntries = 25;

  final StorageBackend _backend;
  final Distance _distance = const Distance();
  Future<void> _writeQueue = Future<void>.value();

  Future<RoadRoute?> findRoute({
    required LatLng origin,
    required LatLng destination,
    required TravelMode mode,
  }) async {
    final entries = await _readEntries();
    Map<String, Object?>? best;
    var bestScore = double.infinity;
    final originTolerance = mode == TravelMode.driving ? 100.0 : 45.0;

    for (final entry in entries) {
      if (entry['mode'] != mode.name) continue;
      final savedOrigin = _latLng(entry['origin']);
      final savedDestination = _latLng(entry['destination']);
      if (savedOrigin == null || savedDestination == null) continue;
      final originMeters = _distance.as(LengthUnit.Meter, origin, savedOrigin);
      final destinationMeters = _distance.as(
        LengthUnit.Meter,
        destination,
        savedDestination,
      );
      if (originMeters > originTolerance || destinationMeters > 35) continue;
      final score = originMeters + destinationMeters * 2;
      if (score < bestScore) {
        best = entry;
        bestScore = score;
      }
    }

    if (best == null) return null;
    final routeMap = best['route'];
    if (routeMap is! Map) return null;
    try {
      return RoadRoute.fromMap(
        Map<String, Object?>.from(routeMap),
        fromOfflineCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRoute({
    required LatLng origin,
    required LatLng destination,
    required TravelMode mode,
    required RoadRoute route,
  }) {
    _writeQueue = _writeQueue
        .catchError((Object _) {})
        .then(
          (_) => _saveRoute(
            origin: origin,
            destination: destination,
            mode: mode,
            route: route,
          ),
        );
    return _writeQueue;
  }

  Future<void> _saveRoute({
    required LatLng origin,
    required LatLng destination,
    required TravelMode mode,
    required RoadRoute route,
  }) async {
    final entries = await _readEntries();
    entries.removeWhere((entry) {
      if (entry['mode'] != mode.name) return false;
      final savedOrigin = _latLng(entry['origin']);
      final savedDestination = _latLng(entry['destination']);
      if (savedOrigin == null || savedDestination == null) return false;
      return _distance.as(LengthUnit.Meter, origin, savedOrigin) < 20 &&
          _distance.as(LengthUnit.Meter, destination, savedDestination) < 20;
    });
    entries.insert(0, <String, Object?>{
      'mode': mode.name,
      'origin': <double>[origin.latitude, origin.longitude],
      'destination': <double>[destination.latitude, destination.longitude],
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'route': route.toMap(),
    });
    if (entries.length > _maximumEntries) {
      entries.removeRange(_maximumEntries, entries.length);
    }
    try {
      await _backend.write(_cacheKey, jsonEncode(entries));
    } catch (_) {
      // Route caching is an enhancement. A route should still be usable when
      // the platform storage backend is temporarily unavailable.
    }
  }

  Future<List<Map<String, Object?>>> _readEntries() async {
    try {
      final value = await _backend.read(_cacheKey);
      if (value == null || value.isEmpty) return [];
      return (jsonDecode(value) as List<dynamic>)
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  LatLng? _latLng(Object? value) {
    if (value is! List || value.length < 2) return null;
    return LatLng((value[0] as num).toDouble(), (value[1] as num).toDouble());
  }
}
