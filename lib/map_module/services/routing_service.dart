import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/road_route.dart';
import '../models/saved_trip.dart';
import 'offline_route_cache.dart';

class RoutingException implements Exception {
  const RoutingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RoutingService {
  RoutingService([http.Client? client, OfflineRouteCache? cache])
    : _client = client,
      _cache = cache ?? OfflineRouteCache();

  static const String _drivingEndpoint =
      'https://router.project-osrm.org/route/v1/driving';
  static const String _walkingEndpoint =
      'https://routing.openstreetmap.de/routed-foot/route/v1/driving';

  final http.Client? _client;
  final OfflineRouteCache _cache;

  Future<RoadRoute> getRoute({
    required LatLng origin,
    required LatLng destination,
    required TravelMode mode,
  }) async {
    final cached = await _cache.findRoute(
      origin: origin,
      destination: destination,
      mode: mode,
    );
    if (cached != null) return cached;

    final endpoint = mode == TravelMode.driving
        ? _drivingEndpoint
        : _walkingEndpoint;
    final coordinates =
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';
    final uri = Uri.parse('$endpoint/$coordinates').replace(
      queryParameters: const {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
        'alternatives': 'false',
      },
    );
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw RoutingException(
          'The routing service returned HTTP ${response.statusCode}.',
        );
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['code'] != 'Ok') {
        throw RoutingException(
          payload['message'] as String? ?? 'No route could be calculated.',
        );
      }
      final routes = payload['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) {
        throw const RoutingException('No route could be calculated.');
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final rawCoordinates = geometry['coordinates'] as List<dynamic>;
      final points = rawCoordinates.map((rawPoint) {
        final pair = rawPoint as List<dynamic>;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
      final instructions = <RouteInstruction>[];
      for (final rawLeg in route['legs'] as List<dynamic>? ?? const []) {
        final leg = rawLeg as Map<String, dynamic>;
        for (final rawStep in leg['steps'] as List<dynamic>? ?? const []) {
          final step = rawStep as Map<String, dynamic>;
          final maneuver =
              step['maneuver'] as Map<String, dynamic>? ?? const {};
          final rawLocation = maneuver['location'] as List<dynamic>?;
          if (rawLocation == null || rawLocation.length < 2) continue;
          instructions.add(
            RouteInstruction(
              type: maneuver['type'] as String? ?? 'continue',
              modifier: maneuver['modifier'] as String? ?? '',
              roadName: step['name'] as String? ?? '',
              distanceMeters: (step['distance'] as num?)?.toDouble() ?? 0,
              durationSeconds: (step['duration'] as num?)?.toDouble() ?? 0,
              location: LatLng(
                (rawLocation[1] as num).toDouble(),
                (rawLocation[0] as num).toDouble(),
              ),
            ),
          );
        }
      }
      if (points.length < 2) {
        throw const RoutingException('The route geometry was empty.');
      }
      final result = RoadRoute(
        points: points,
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toDouble(),
        instructions: instructions,
      );
      await _cache.saveRoute(
        origin: origin,
        destination: destination,
        mode: mode,
        route: result,
      );
      return result;
    } on RoutingException {
      rethrow;
    } catch (error) {
      throw RoutingException(
        'This route is not saved offline yet. Connect once to download it: '
        '$error',
      );
    } finally {
      if (_client == null) client.close();
    }
  }
}
