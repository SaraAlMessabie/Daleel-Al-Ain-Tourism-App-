import 'bus_route.dart';
import 'bus_stop.dart';
import 'route_direction.dart';

class BusMapData {
  const BusMapData({
    required this.routes,
    required this.directions,
    required this.stopsById,
    required this.stopLinksByDirection,
    required this.shapePointsByDirection,
  });

  final List<BusRoute> routes;
  final List<RouteDirection> directions;
  final Map<String, BusStop> stopsById;
  final Map<String, List<RouteStopLink>> stopLinksByDirection;
  final Map<String, List<RouteShapePoint>> shapePointsByDirection;
}
