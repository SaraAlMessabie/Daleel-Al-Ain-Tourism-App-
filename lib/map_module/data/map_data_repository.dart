import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/attraction.dart';
import '../models/bus_map_data.dart';
import '../models/bus_route.dart';
import '../models/bus_stop.dart';
import '../models/category.dart';
import '../models/route_direction.dart';

class MapDataRepository {
  const MapDataRepository();

  Future<List<Attraction>> loadAttractions() async {
    final jsonList = await _loadJsonList('assets/data/attractions.json');

    return jsonList.map((item) {
      final map = Map<String, Object?>.from(item as Map);

      return Attraction.fromMap(map);
    }).toList();
  }

  Future<List<Category>> loadCategories() async {
    final jsonList = await _loadJsonList('assets/data/categories.json');

    return jsonList.map((item) {
      final map = Map<String, Object?>.from(item as Map);

      return Category.fromMap(map);
    }).toList();
  }

  Future<BusMapData> loadBusMapData() async {
    final routeJson = await _loadJsonList('assets/data/bus_routes.json');
    final directionJson = await _loadJsonList(
      'assets/data/route_directions.json',
    );
    final stopJson = await _loadJsonList('assets/data/bus_stops.json');
    final linkJson = await _loadJsonList('assets/data/route_stops.json');
    final shapeJson = await _loadJsonList('assets/data/route_shapes.json');

    final routes =
        routeJson
            .map(
              (item) =>
                  BusRoute.fromMap(Map<String, Object?>.from(item as Map)),
            )
            .where((route) => route.isActive)
            .toList()
          ..sort(
            (first, second) =>
                int.parse(first.routeNumber)
                    .compareTo(int.parse(second.routeNumber)),
          );

    final directions = directionJson
        .map(
          (item) =>
              RouteDirection.fromMap(Map<String, Object?>.from(item as Map)),
        )
        .toList();

    final stopsById = <String, BusStop>{};
    for (final item in stopJson) {
      final stop = BusStop.fromMap(Map<String, Object?>.from(item as Map));
      stopsById[stop.stopId] = stop;
    }

    final stopLinksByDirection = <String, List<RouteStopLink>>{};
    for (final item in linkJson) {
      final link = RouteStopLink.fromMap(
        Map<String, Object?>.from(item as Map),
      );
      stopLinksByDirection.putIfAbsent(link.directionId, () => []).add(link);
    }
    for (final links in stopLinksByDirection.values) {
      links.sort(
        (first, second) => first.stopSequence.compareTo(second.stopSequence),
      );
    }

    final shapePointsByDirection = <String, List<RouteShapePoint>>{};
    for (final item in shapeJson) {
      final point = RouteShapePoint.fromMap(
        Map<String, Object?>.from(item as Map),
      );
      shapePointsByDirection
          .putIfAbsent(point.directionId, () => [])
          .add(point);
    }
    for (final points in shapePointsByDirection.values) {
      points.sort(
        (first, second) => first.pointSequence.compareTo(second.pointSequence),
      );
    }

    return BusMapData(
      routes: routes,
      directions: directions,
      stopsById: stopsById,
      stopLinksByDirection: stopLinksByDirection,
      shapePointsByDirection: shapePointsByDirection,
    );
  }

  Future<List<dynamic>> _loadJsonList(String assetPath) async {
    final jsonText = await rootBundle.loadString(assetPath);
    return jsonDecode(jsonText) as List<dynamic>;
  }
}
