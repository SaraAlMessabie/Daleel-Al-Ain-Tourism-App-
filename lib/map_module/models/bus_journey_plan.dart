import 'package:latlong2/latlong.dart';

import 'bus_route.dart';
import 'bus_stop.dart';
import 'route_direction.dart';
import 'road_route.dart';

enum BusJourneyPhase { walkToBoard, ride, walkToDestination }

class BusJourneyPlan {
  const BusJourneyPlan({
    required this.direction,
    required this.route,
    required this.boardLink,
    required this.boardStop,
    required this.alightLink,
    required this.alightStop,
    required this.routeStops,
    required this.routeShape,
    required this.walkToBoardKm,
    required this.walkFromAlightKm,
    this.walkToBoardRoute,
    this.walkFromAlightRoute,
  });

  final RouteDirection direction;
  final BusRoute route;
  final RouteStopLink boardLink;
  final BusStop boardStop;
  final RouteStopLink alightLink;
  final BusStop alightStop;
  final List<BusStop> routeStops;
  final List<LatLng> routeShape;
  final double walkToBoardKm;
  final double walkFromAlightKm;
  final RoadRoute? walkToBoardRoute;
  final RoadRoute? walkFromAlightRoute;

  int get stopCount => alightLink.stopSequence - boardLink.stopSequence + 1;

  double get totalWalkingKm => walkToBoardKm + walkFromAlightKm;

  BusJourneyPlan withWalkingRoutes({
    required RoadRoute toBoard,
    required RoadRoute fromAlight,
  }) {
    return BusJourneyPlan(
      direction: direction,
      route: route,
      boardLink: boardLink,
      boardStop: boardStop,
      alightLink: alightLink,
      alightStop: alightStop,
      routeStops: routeStops,
      routeShape: routeShape,
      walkToBoardKm: toBoard.distanceKm,
      walkFromAlightKm: fromAlight.distanceKm,
      walkToBoardRoute: toBoard,
      walkFromAlightRoute: fromAlight,
    );
  }
}
