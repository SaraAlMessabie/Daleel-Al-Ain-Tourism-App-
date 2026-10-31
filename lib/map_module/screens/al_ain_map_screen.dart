import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/map_data_repository.dart';
import '../models/attraction.dart';
import '../models/bus_journey_plan.dart';
import '../models/bus_route.dart';
import '../models/bus_stop.dart';
import '../models/category.dart';
import '../models/route_direction.dart';
import '../models/road_route.dart';
import '../models/saved_trip.dart';
import '../services/app_storage.dart';
import '../services/offline_map_bundle.dart';
import '../services/routing_service.dart';
import '../../theme.dart';
import '../../ui.dart';

class AlAinMapScreen extends StatefulWidget {
  const AlAinMapScreen({
    super.key,
    this.themeMode = ThemeMode.system,
    this.isArabic,
    this.focusAttractionId,
    this.focusNonce = 0,
    this.focusDirections = false,
    this.favoriteIds,
    this.onToggleFavorite,
    this.onOpenDetails,
  });

  final ThemeMode themeMode;

  /// DALEEL: the host app controls the language (defaults to English).
  final bool? isArabic;

  /// DALEEL: ask the map to zoom to this attraction (changes of [focusNonce]
  /// trigger a new request, even for the same id). With [focusDirections]
  /// the travel options open straight away.
  final int? focusAttractionId;
  final int focusNonce;
  final bool focusDirections;

  /// DALEEL: saved places are owned by the host app so Explore, the place
  /// screen, Profile and the map all show the same list.
  final Set<int>? favoriteIds;
  final void Function(int attractionId)? onToggleFavorite;

  /// DALEEL: opens the app's single place screen.
  final void Function(int attractionId)? onOpenDetails;

  @override
  State<AlAinMapScreen> createState() => _AlAinMapScreenState();
}

class _AlAinMapScreenState extends State<AlAinMapScreen>
    with WidgetsBindingObserver {
  static const double southBoundary = 23.95;
  static const double westBoundary = 55.50;
  static const double northBoundary = 24.45;
  static const double eastBoundary = 56.00;

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final MapDataRepository _repository = const MapDataRepository();
  final AppStorage _storage = AppStorage();
  final RoutingService _routingService = RoutingService();
  final Distance _distance = const Distance();

  List<Attraction> _attractions = [];
  List<Category> _categories = [];
  List<BusRoute> _busRoutes = [];
  List<RouteDirection> _routeDirections = [];
  Map<String, BusStop> _busStopsById = {};
  Map<String, List<RouteStopLink>> _stopLinksByDirection = {};
  Map<String, List<RouteShapePoint>> _shapePointsByDirection = {};

  final Set<int> _localFavoriteIds = {};
  Set<int> get _favoriteIds => widget.favoriteIds ?? _localFavoriteIds;
  final List<int> _tripStopIds = [];
  final List<SavedTrip> _savedTrips = [];

  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionSubscription;
  Attraction? _navigationTarget;
  BusJourneyPlan? _activeBusPlan;
  BusJourneyPhase _busJourneyPhase = BusJourneyPhase.walkToBoard;
  int _busJourneyStopIndex = 0;
  RoadRoute? _activeRoadRoute;
  RoadRoute? _tripRoadRoute;
  int _currentInstructionIndex = 0;
  int _tripRouteRequestId = 0;
  int _mapStyleRequestId = 0;
  DateTime? _lastRerouteAt;
  double _currentHeading = 0;
  double _currentSpeedMps = 0;
  int? _selectedCategoryId;
  String _searchQuery = '';
  String? _selectedDirectionId;
  TravelMode _travelMode = TravelMode.driving;

  bool _isLoadingData = true;
  bool _isLoadingLocation = false;
  bool _clusteringEnabled = true;
  bool _transportEnabled = false;
  bool _nearMeEnabled = false;
  bool _liveTrackingEnabled = false;
  bool _followUser = false;
  bool _isCalculatingRoute = false;
  bool _isCalculatingTripRoute = false;
  bool _isArabic = false;
  bool _savedOnly = false; // "Saved" chip: show only saved places
  int _handledFocusNonce = -1;

  String? _dataError;
  String? _tripRouteError;
  OfflineMapBundle? _offlineMap;
  String? _offlineMapError;

  String _t(String english, String arabic) => _isArabic ? arabic : english;

  List<Attraction> get _filteredAttractions {
    final query = _searchQuery.trim().toLowerCase();
    final result = _attractions.where((attraction) {
      if (_savedOnly && !_favoriteIds.contains(attraction.attractionId)) {
        return false;
      }
      final matchesCategory =
          _selectedCategoryId == null ||
          attraction.categoryId == _selectedCategoryId;
      final matchesSearch =
          query.isEmpty ||
          attraction.nameEn.toLowerCase().contains(query) ||
          attraction.nameAr.contains(_searchQuery.trim());
      return attraction.isActive && matchesCategory && matchesSearch;
    }).toList();

    if (_nearMeEnabled && _currentLocation != null) {
      result.sort((first, second) {
        return _distanceToAttraction(first)
            .compareTo(_distanceToAttraction(second));
      });
    }
    return result;
  }

  List<Attraction> get _tripStops =>
      _tripStopIds.map(_attractionById).whereType<Attraction>().toList();

  List<LatLng> get _tripPoints =>
      _tripStops.map((item) => LatLng(item.latitude, item.longitude)).toList();

  List<LatLng> get _tripDisplayPoints =>
      _tripRoadRoute?.points ?? const <LatLng>[];

  List<LatLng> get _navigationPoints {
    if (_activeRoadRoute != null) return _activeRoadRoute!.points;
    final location = _currentLocation;
    final target = _navigationTarget;
    if (location == null || target == null) return const [];
    return [location, LatLng(target.latitude, target.longitude)];
  }

  double get _navigationDistanceKm {
    if (_activeRoadRoute != null && _currentLocation != null) {
      final route = _activeRoadRoute!;
      final nearestIndex = _nearestRoutePointIndex(
        route.points,
        _currentLocation!,
      );
      var meters = _distance.as(
        LengthUnit.Meter,
        _currentLocation!,
        route.points[nearestIndex],
      );
      for (var index = nearestIndex; index < route.points.length - 1; index++) {
        meters += _distance.as(
          LengthUnit.Meter,
          route.points[index],
          route.points[index + 1],
        );
      }
      return meters / 1000;
    }
    final points = _navigationPoints;
    if (points.length < 2) return 0;
    return _distance.as(LengthUnit.Kilometer, points.first, points.last);
  }

  int get _navigationEtaMinutes {
    if (_navigationTarget == null) return 0;
    if (_travelMode == TravelMode.bus && _activeBusPlan != null) {
      final plan = _activeBusPlan!;
      final walkingMinutes = (plan.totalWalkingKm / 4.8 * 60).ceil();
      return walkingMinutes + 10 + math.max(1, plan.stopCount - 1) * 2;
    }
    if (_activeRoadRoute != null) {
      final route = _activeRoadRoute!;
      final fraction = route.distanceKm <= 0
          ? 0.0
          : (_navigationDistanceKm / route.distanceKm).clamp(0.0, 1.0);
      return math.max(1, (route.durationMinutes * fraction).ceil());
    }
    final speedKmh = _travelMode == TravelMode.walking ? 4.8 : 32.0;
    return math.max(1, (_navigationDistanceKm / speedKmh * 60).ceil());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isArabic = widget.isArabic ?? false;
    _loadMapData();
  }

  @override
  void didUpdateWidget(covariant AlAinMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode != widget.themeMode) {
      unawaited(_reloadOfflineMap());
    }
    if (widget.isArabic != null && widget.isArabic != _isArabic) {
      setState(() => _isArabic = widget.isArabic!);
      unawaited(_reloadOfflineMap());
    }
    if (widget.focusNonce != oldWidget.focusNonce) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyFocusRequest());
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (widget.themeMode == ThemeMode.system) {
      unawaited(_reloadOfflineMap());
    }
  }

  @override
  void didHaveMemoryPressure() {
    // The vector renderer keeps decoded and rasterized tiles in shared
    // process-wide caches. Release them when the host operating system asks
    // the combined app to reduce memory use.
    vt.VectorTileLayer.clearMemoryCache();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    _offlineMap?.dispose();
    vt.VectorTileLayer.clearMemoryCache();
    super.dispose();
  }

  /// DALEEL: zoom to the attraction the host app asked for and open its card.
  void _applyFocusRequest() {
    final id = widget.focusAttractionId;
    if (!mounted || id == null || _isLoadingData) return;
    if (widget.focusNonce == _handledFocusNonce) return;
    final attraction = _attractionById(id);
    if (attraction == null) return;
    _handledFocusNonce = widget.focusNonce;
    _mapController.move(LatLng(attraction.latitude, attraction.longitude), 16);
    if (widget.focusDirections) {
      unawaited(_showNavigationOptions(attraction));
    } else {
      _showAttractionPopup(attraction);
    }
  }

  Future<void> _loadMapData() async {
    setState(() {
      _isLoadingData = true;
      _dataError = null;
    });

    try {
      final attractions = await _repository.loadAttractions();
      final categories = await _repository.loadCategories();
      final busMapData = await _repository.loadBusMapData();
      final savedState = await _storage.readState();
      final savedIsArabic =
          widget.isArabic ?? (savedState['is_arabic'] as bool? ?? false);

      OfflineMapBundle? offlineMap;
      String? offlineMapError;
      try {
        offlineMap = await OfflineMapBundle.load(
          isArabic: savedIsArabic,
          isDark: _usesDarkMap(widget.themeMode),
        );
      } catch (error) {
        offlineMapError = error.toString();
      }

      if (!mounted) {
        offlineMap?.dispose();
        return;
      }

      setState(() {
        _offlineMap?.dispose();
        _attractions = attractions;
        _categories = categories;
        _busRoutes = busMapData.routes;
        _routeDirections = busMapData.directions;
        _busStopsById = busMapData.stopsById;
        _stopLinksByDirection = busMapData.stopLinksByDirection;
        _shapePointsByDirection = busMapData.shapePointsByDirection;
        _selectedDirectionId = busMapData.directions.isEmpty
            ? null
            : busMapData.directions.first.directionId;
        _offlineMap = offlineMap;
        _offlineMapError = offlineMapError;
        _restoreState(savedState);
        _isLoadingData = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyFocusRequest());
      unawaited(_refreshTripRoute(showError: false));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dataError = error.toString();
        _isLoadingData = false;
      });
    }
  }

  bool _usesDarkMap(ThemeMode mode) {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  Future<void> _reloadOfflineMap() async {
    final requestId = ++_mapStyleRequestId;
    try {
      final replacement = await OfflineMapBundle.load(
        isArabic: _isArabic,
        isDark: _usesDarkMap(widget.themeMode),
      );
      if (!mounted || requestId != _mapStyleRequestId) {
        replacement.dispose();
        return;
      }
      setState(() {
        _offlineMap?.dispose();
        _offlineMap = replacement;
        _offlineMapError = null;
      });
    } catch (error) {
      if (!mounted || requestId != _mapStyleRequestId) return;
      setState(() => _offlineMapError = error.toString());
      _showMessage(
        _t('The map style could not be changed.', 'تعذر تغيير نمط الخريطة.'),
      );
    }
  }

  void _restoreState(Map<String, Object?> state) {
    _localFavoriteIds
      ..clear()
      ..addAll(
        (state['favorite_ids'] as List<dynamic>? ?? const []).map(
          (value) => (value as num).toInt(),
        ),
      );
    _tripStopIds
      ..clear()
      ..addAll(
        (state['trip_stop_ids'] as List<dynamic>? ?? const []).map(
          (value) => (value as num).toInt(),
        ),
      );
    _savedTrips
      ..clear()
      ..addAll(
        (state['saved_trips'] as List<dynamic>? ?? const []).map(
          (value) => SavedTrip.fromMap(Map<String, Object?>.from(value as Map)),
        ),
      );
    _travelMode = TravelMode.fromStorage(state['travel_mode'] as String?);
    _isArabic = widget.isArabic ?? (state['is_arabic'] as bool? ?? false);
    _clusteringEnabled = state['clustering'] as bool? ?? true;
  }

  Future<void> _persistState({ThemeMode? themeModeOverride}) {
    return _storage.writeState(<String, Object?>{
      'favorite_ids': _favoriteIds.toList(),
      'trip_stop_ids': _tripStopIds,
      'saved_trips': _savedTrips.map((trip) => trip.toMap()).toList(),
      'travel_mode': _travelMode.name,
      'is_arabic': _isArabic,
      'clustering': _clusteringEnabled,
      'theme_mode': (themeModeOverride ?? widget.themeMode).name,
    });
  }

  Attraction? _attractionById(int id) {
    for (final attraction in _attractions) {
      if (attraction.attractionId == id) return attraction;
    }
    return null;
  }

  double _distanceToAttraction(Attraction attraction) {
    final origin = _currentLocation ?? const LatLng(24.18, 55.75);
    return _distance.as(
      LengthUnit.Kilometer,
      origin,
      LatLng(attraction.latitude, attraction.longitude),
    );
  }

  double get _tripDistanceKm {
    if (_tripRoadRoute != null) return _tripRoadRoute!.distanceKm;
    final points = _tripPoints;
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var index = 0; index < points.length - 1; index++) {
      total += _distance.as(
        LengthUnit.Kilometer,
        points[index],
        points[index + 1],
      );
    }
    return total;
  }

  int get _tripDurationMinutes {
    if (_tripDistanceKm == 0) return 0;
    if (_tripRoadRoute != null && _travelMode != TravelMode.bus) {
      final stopMinutes = math.max(0, _tripStopIds.length - 1) * 8;
      return _tripRoadRoute!.durationMinutes + stopMinutes;
    }
    final speed = switch (_travelMode) {
      TravelMode.walking => 4.8,
      TravelMode.driving => 32.0,
      TravelMode.bus => 20.0,
    };
    final travelMinutes = (_tripDistanceKm / speed * 60).ceil();
    final stopMinutes = math.max(0, _tripStopIds.length - 1) * 8;
    final waitMinutes = _travelMode == TravelMode.bus ? 10 : 0;
    return travelMinutes + stopMinutes + waitMinutes;
  }

  void _searchAttractions(String value) {
    setState(() => _searchQuery = value);
  }

  void _submitSearch(String value) {
    _searchAttractions(value);
    if (_filteredAttractions.isEmpty) {
      _showMessage(
        _t('No matching attractions found.', 'لم يتم العثور على نتائج.'),
      );
      return;
    }
    final item = _filteredAttractions.first;
    _mapController.move(LatLng(item.latitude, item.longitude), 15);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _toggleFavorite(Attraction attraction) {
    final host = widget.onToggleFavorite;
    if (host != null) {
      host(attraction.attractionId); // the host rebuilds us with the new list
      return;
    }
    setState(() {
      if (!_localFavoriteIds.add(attraction.attractionId)) {
        _localFavoriteIds.remove(attraction.attractionId);
      }
    });
    _persistState();
  }

  void _toggleTripStop(Attraction attraction) {
    setState(() {
      if (_tripStopIds.contains(attraction.attractionId)) {
        _tripStopIds.remove(attraction.attractionId);
      } else {
        _tripStopIds.add(attraction.attractionId);
      }
    });
    _persistState();
    unawaited(_refreshTripRoute());
  }

  Future<RoadRoute> _routeThroughPoints(
    List<LatLng> points,
    TravelMode mode,
  ) async {
    if (points.length < 2) {
      throw const RoutingException('At least two locations are required.');
    }
    final legs = await Future.wait([
      for (var index = 0; index < points.length - 1; index++)
        _routingService.getRoute(
          origin: points[index],
          destination: points[index + 1],
          mode: mode,
        ),
    ]);
    final routePoints = <LatLng>[];
    final instructions = <RouteInstruction>[];
    var distanceMeters = 0.0;
    var durationSeconds = 0.0;
    for (var index = 0; index < legs.length; index++) {
      final leg = legs[index];
      routePoints.addAll(index == 0 ? leg.points : leg.points.skip(1));
      instructions.addAll(leg.instructions);
      distanceMeters += leg.distanceMeters;
      durationSeconds += leg.durationSeconds;
    }
    return RoadRoute(
      points: routePoints,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      instructions: instructions,
    );
  }

  Future<void> _refreshTripRoute({bool showError = true}) async {
    final requestId = ++_tripRouteRequestId;
    final points = List<LatLng>.from(_tripPoints);
    final mode = _travelMode;
    if (points.length < 2 || mode == TravelMode.bus) {
      if (!mounted) return;
      setState(() {
        _tripRoadRoute = null;
        _tripRouteError = null;
        _isCalculatingTripRoute = false;
      });
      return;
    }
    setState(() {
      _tripRoadRoute = null;
      _tripRouteError = null;
      _isCalculatingTripRoute = true;
    });
    try {
      final route = await _routeThroughPoints(points, mode);
      if (!mounted || requestId != _tripRouteRequestId) return;
      setState(() => _tripRoadRoute = route);
    } catch (error) {
      if (!mounted || requestId != _tripRouteRequestId) return;
      setState(() => _tripRouteError = error.toString());
      if (showError) {
        _showMessage(
          _t(
            'This trip is not saved offline yet. Connect once to download and save it.',
            'هذه الرحلة غير محفوظة دون اتصال بعد. اتصل مرة واحدة لتنزيلها وحفظها.',
          ),
        );
      }
    } finally {
      if (mounted && requestId == _tripRouteRequestId) {
        setState(() => _isCalculatingTripRoute = false);
      }
    }
  }

  Future<void> _startTripNavigation() async {
    final stops = List<Attraction>.from(_tripStops);
    if (stops.isEmpty) return;
    final origin = await _ensureLiveLocation(followUser: false);
    if (origin == null || !mounted) return;
    if (!_isInsideAlAin(origin)) {
      _showMessage(
        _t(
          'Navigation is available inside the offline Al Ain map area.',
          'التنقل متاح داخل نطاق خريطة العين دون اتصال.',
        ),
      );
      return;
    }
    if (_travelMode == TravelMode.bus) {
      await _startBusNavigation(stops.last, origin);
      return;
    }
    setState(() => _isCalculatingRoute = true);
    try {
      final route = await _routeThroughPoints([
        origin,
        for (final stop in stops) LatLng(stop.latitude, stop.longitude),
      ], _travelMode);
      if (!mounted) return;
      setState(() {
        _navigationTarget = stops.last;
        _activeBusPlan = null;
        _activeRoadRoute = route;
        _currentInstructionIndex = 0;
        _followUser = true;
        _transportEnabled = false;
      });
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: route.points,
          padding: const EdgeInsets.all(80),
          maxZoom: 16,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        _t(
          'GPS navigation could not start. Check your internet connection and try again.',
          'تعذر بدء الملاحة عبر GPS. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
  }

  void _toggleClustering() {
    setState(() => _clusteringEnabled = !_clusteringEnabled);
    _persistState();
  }

  void _toggleTransport() {
    setState(() => _transportEnabled = !_transportEnabled);
    if (_transportEnabled && _selectedDirectionId != null) {
      _focusSelectedRoute();
    }
  }

  void _selectRouteDirection(String? directionId) {
    if (directionId == null) return;
    setState(() {
      _selectedDirectionId = directionId;
      if (_activeBusPlan != null) {
        _activeBusPlan = null;
        _navigationTarget = null;
        _followUser = false;
      }
    });
    _focusSelectedRoute();
  }

  void _focusSelectedRoute() {
    final points = _selectedShapePoints;
    if (points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(60),
          maxZoom: 14,
        ),
      );
    });
  }

  RouteDirection? get _selectedDirection {
    for (final direction in _routeDirections) {
      if (direction.directionId == _selectedDirectionId) return direction;
    }
    return null;
  }

  BusRoute? _routeById(String routeId) {
    for (final route in _busRoutes) {
      if (route.routeId == routeId) return route;
    }
    return null;
  }

  List<RouteStopLink> get _selectedStopLinks {
    return _stopLinksByDirection[_selectedDirectionId] ?? [];
  }

  List<LatLng> get _selectedShapePoints {
    return _shapePointsByDirection[_selectedDirectionId]
            ?.map((point) => LatLng(point.latitude, point.longitude))
            .toList() ??
        [];
  }

  void _resetMapView() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedCategoryId = null;
      _savedOnly = false;
      _nearMeEnabled = false;
      _followUser = false;
    });
    _mapController.move(const LatLng(24.18, 55.75), 11);
  }

  Future<void> _enableNearMe() async {
    final location = await _ensureLiveLocation(followUser: false);
    if (location == null || !mounted) return;
    setState(() => _nearMeEnabled = true);
    if (_isInsideAlAin(location)) {
      _mapController.move(location, 13);
    }
    await _showNearMeSheet();
  }

  Future<void> _goToCurrentLocation() async {
    final location = await _ensureLiveLocation(followUser: true);
    if (location == null || !mounted) return;
    if (_isInsideAlAin(location)) {
      _mapController.move(location, 15);
    } else {
      _showMessage(
        _t(
          'Your location is outside the offline Al Ain map area.',
          'موقعك خارج نطاق خريطة العين دون اتصال.',
        ),
      );
    }
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showMessage(
        _t('Location services are disabled.', 'خدمات الموقع متوقفة.'),
      );
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showMessage(_t('Location permission was denied.', 'تم رفض إذن الموقع.'));
      return false;
    }
    return true;
  }

  Future<LatLng?> _ensureLiveLocation({required bool followUser}) async {
    if (_isLoadingLocation) return _currentLocation;
    setState(() => _isLoadingLocation = true);
    try {
      if (!await _ensureLocationPermission()) return null;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return null;
      _applyPosition(position, moveCamera: followUser);
      await _startPositionStream(followUser: followUser);
      return LatLng(position.latitude, position.longitude);
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
      return null;
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _startPositionStream({required bool followUser}) async {
    if (!mounted) return;
    setState(() {
      _liveTrackingEnabled = true;
      _followUser = followUser;
    });
    if (_positionSubscription != null) return;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          (position) => _applyPosition(position, moveCamera: _followUser),
          onError: (Object error) {
            if (!mounted) return;
            _showMessage(error.toString());
          },
        );
  }

  void _applyPosition(Position position, {required bool moveCamera}) {
    if (!mounted) return;
    final location = LatLng(position.latitude, position.longitude);
    setState(() {
      _currentLocation = location;
      _currentHeading = position.heading.isFinite ? position.heading : 0;
      _currentSpeedMps = position.speed.isFinite
          ? math.max(0, position.speed)
          : 0;
    });
    if (moveCamera && _isInsideAlAin(location)) {
      _mapController.move(location, math.max(15, _mapController.camera.zoom));
    }
    _updateNavigationProgress(location);
    _updateBusJourneyProgress(location);
    final target = _navigationTarget;
    final metersToTarget = target == null
        ? double.infinity
        : _distance.as(
            LengthUnit.Meter,
            location,
            LatLng(target.latitude, target.longitude),
          );
    if (target != null && metersToTarget <= 60) {
      _showMessage(
        _t(
          'You have arrived at ${target.nameEn}.',
          'لقد وصلت إلى ${target.nameAr}.',
        ),
      );
      _stopNavigation();
    }
  }

  void _updateBusJourneyProgress(LatLng location) {
    final plan = _activeBusPlan;
    if (plan == null || plan.routeStops.isEmpty) return;

    final boardPoint = LatLng(
      plan.boardStop.latitude,
      plan.boardStop.longitude,
    );
    final alightPoint = LatLng(
      plan.alightStop.latitude,
      plan.alightStop.longitude,
    );
    final metersToBoard = _distance.as(LengthUnit.Meter, location, boardPoint);
    final metersToAlight = _distance.as(
      LengthUnit.Meter,
      location,
      alightPoint,
    );

    if (_busJourneyPhase == BusJourneyPhase.walkToBoard &&
        metersToBoard <= 55) {
      setState(() {
        _busJourneyPhase = BusJourneyPhase.ride;
        _busJourneyStopIndex = 0;
      });
      _showMessage(
        _t(
          'Board route ${plan.route.routeNumber} at ${plan.boardStop.nameEn}.',
          'اركب خط ${plan.route.routeNumber} عند ${plan.boardStop.nameAr}.',
        ),
      );
      return;
    }

    if (_busJourneyPhase != BusJourneyPhase.ride) return;
    var nearestIndex = _busJourneyStopIndex;
    var nearestMeters = double.infinity;
    for (
      var index = _busJourneyStopIndex;
      index < plan.routeStops.length;
      index++
    ) {
      final stop = plan.routeStops[index];
      final meters = _distance.as(
        LengthUnit.Meter,
        location,
        LatLng(stop.latitude, stop.longitude),
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = index;
      }
    }
    if (nearestIndex != _busJourneyStopIndex) {
      setState(() => _busJourneyStopIndex = nearestIndex);
    }
    if (metersToAlight <= 90 && nearestIndex >= plan.routeStops.length - 2) {
      setState(() {
        _busJourneyPhase = BusJourneyPhase.walkToDestination;
        _busJourneyStopIndex = plan.routeStops.length - 1;
      });
      _showMessage(
        _t(
          'Get off at ${plan.alightStop.nameEn}, then walk to your destination.',
          'انزل عند ${plan.alightStop.nameAr}، ثم امشِ إلى وجهتك.',
        ),
      );
    }
  }

  int _nearestRoutePointIndex(List<LatLng> points, LatLng location) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < points.length; index++) {
      final meters = _distance.as(LengthUnit.Meter, location, points[index]);
      if (meters < nearestDistance) {
        nearestDistance = meters;
        nearestIndex = index;
      }
    }
    return nearestIndex;
  }

  void _updateNavigationProgress(LatLng location) {
    final route = _activeRoadRoute;
    final target = _navigationTarget;
    if (route == null || target == null || _activeBusPlan != null) return;

    var newInstructionIndex = _currentInstructionIndex;
    for (
      var index = _currentInstructionIndex;
      index < route.instructions.length;
      index++
    ) {
      final meters = _distance.as(
        LengthUnit.Meter,
        location,
        route.instructions[index].location,
      );
      if (meters <= 45) {
        newInstructionIndex = math.min(
          index + 1,
          route.instructions.length - 1,
        );
      }
    }
    if (newInstructionIndex != _currentInstructionIndex && mounted) {
      setState(() => _currentInstructionIndex = newInstructionIndex);
    }

    final nearestIndex = _nearestRoutePointIndex(route.points, location);
    final offRouteMeters = _distance.as(
      LengthUnit.Meter,
      location,
      route.points[nearestIndex],
    );
    final threshold = _travelMode == TravelMode.walking ? 55.0 : 100.0;
    final lastReroute = _lastRerouteAt;
    final canReroute =
        lastReroute == null ||
        DateTime.now().difference(lastReroute) > const Duration(seconds: 25);
    if (offRouteMeters > threshold && canReroute && !_isCalculatingRoute) {
      _lastRerouteAt = DateTime.now();
      unawaited(_recalculateRoadRoute(location, target));
    }
  }

  Future<void> _recalculateRoadRoute(LatLng origin, Attraction target) async {
    if (_travelMode == TravelMode.bus) return;
    setState(() => _isCalculatingRoute = true);
    try {
      final route = await _routingService.getRoute(
        origin: origin,
        destination: LatLng(target.latitude, target.longitude),
        mode: _travelMode,
      );
      if (!mounted || _navigationTarget?.attractionId != target.attractionId) {
        return;
      }
      setState(() {
        _activeRoadRoute = route;
        _currentInstructionIndex = 0;
      });
    } catch (_) {
      if (mounted) {
        _showMessage(
          _t(
            'You are off route. Automatic recalculation will retry shortly.',
            'أنت خارج المسار. ستتم إعادة المحاولة تلقائياً قريباً.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
  }

  Future<void> _toggleLiveTracking() async {
    if (!_liveTrackingEnabled) {
      await _goToCurrentLocation();
      return;
    }
    if (_followUser) {
      setState(() => _followUser = false);
      _showMessage(_t('Map follow paused.', 'تم إيقاف تتبع الخريطة مؤقتاً.'));
    } else {
      setState(() => _followUser = true);
      final location = _currentLocation;
      if (location != null && _isInsideAlAin(location)) {
        _mapController.move(location, 15);
      }
    }
  }

  Future<void> _stopLiveTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (!mounted) return;
    setState(() {
      _liveTrackingEnabled = false;
      _followUser = false;
    });
  }

  bool _isInsideAlAin(LatLng location) {
    return location.latitude >= southBoundary &&
        location.latitude <= northBoundary &&
        location.longitude >= westBoundary &&
        location.longitude <= eastBoundary;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showNearMeSheet() async {
    final location = _currentLocation;
    if (location == null) return;
    final nearby = _attractions.where((item) => item.isActive).toList()
      ..sort(
        (a, b) => _distanceToAttraction(a).compareTo(_distanceToAttraction(b)),
      );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('Places near you', 'أماكن قريبة منك'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: _t('Turn off location', 'إيقاف تحديد الموقع'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _stopLiveTracking();
                      },
                      icon: const Icon(Icons.location_disabled_outlined),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _t(
                      'Closest to you first. Tap a place to see it on the map.',
                      'الأقرب إليك أولاً. اضغط على مكان لعرضه على الخريطة.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: math.min(15, nearby.length),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final attraction = nearby[index];
                    final kilometers = _distanceToAttraction(attraction);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: sandDeep,
                        child: Icon(
                          _iconForCategory(attraction.categoryId),
                          size: 20,
                          color: _colorForCategory(attraction.categoryId),
                        ),
                      ),
                      title: Text(
                        _isArabic ? attraction.nameAr : attraction.nameEn,
                      ),
                      subtitle: Text(
                        kilometers < 1
                            ? _t(
                                '${(kilometers * 1000).round()} m away',
                                'يبعد ${(kilometers * 1000).round()} متر',
                              )
                            : _t(
                                '${kilometers.toStringAsFixed(1)} km away',
                                'يبعد ${kilometers.toStringAsFixed(1)} كم',
                              ),
                      ),
                      trailing: IconButton(
                        tooltip: _t('Directions', 'الاتجاهات'),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showNavigationOptions(attraction);
                        },
                        icon: const Icon(Icons.directions_outlined),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _mapController.move(
                          LatLng(attraction.latitude, attraction.longitude),
                          15,
                        );
                        _showAttractionPopup(attraction);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() => _nearMeEnabled = false);
  }

  Future<void> _showNavigationOptions(Attraction attraction) async {
    final location = await _ensureLiveLocation(followUser: false);
    if (location == null || !mounted) return;
    if (!_isInsideAlAin(location)) {
      _showMessage(
        _t(
          'Navigation is available inside the offline Al Ain map area.',
          'التنقل متاح داخل نطاق خريطة العين دون اتصال.',
        ),
      );
      return;
    }

    final mode = await showModalBottomSheet<TravelMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(
                  'Directions to ${attraction.nameEn}',
                  'الاتجاهات إلى ${attraction.nameAr}',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.directions_walk),
                title: Text(_t('Walk', 'مشي')),
                subtitle: Text(
                  _t(
                    'Along streets and footpaths, following your location',
                    'عبر الشوارع وممرات المشاة مع تتبع موقعك',
                  ),
                ),
                onTap: () => Navigator.pop(context, TravelMode.walking),
              ),
              ListTile(
                leading: const Icon(Icons.directions_car),
                title: Text(_t('Drive', 'سيارة')),
                subtitle: Text(
                  _t(
                    'Along roads; reroutes if you take a different turn',
                    'عبر الطرق، ويعيد حساب المسار إذا غيّرت الطريق',
                  ),
                ),
                onTap: () => Navigator.pop(context, TravelMode.driving),
              ),
              ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text(_t('Bus', 'حافلة')),
                subtitle: Text(
                  _t(
                    'Where to get on, which bus, and where to get off',
                    'أين تصعد، وأي حافلة، وأين تنزل',
                  ),
                ),
                onTap: () => Navigator.pop(context, TravelMode.bus),
              ),
            ],
          ),
        ),
      ),
    );
    if (mode == null || !mounted) return;
    if (mode == TravelMode.bus) {
      await _startBusNavigation(attraction, location);
    } else {
      await _startRoadNavigation(attraction, mode, location);
    }
  }

  Future<void> _startRoadNavigation(
    Attraction attraction,
    TravelMode mode,
    LatLng origin,
  ) async {
    setState(() => _isCalculatingRoute = true);
    RoadRoute route;
    try {
      route = await _routingService.getRoute(
        origin: origin,
        destination: LatLng(attraction.latitude, attraction.longitude),
        mode: mode,
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          _t(
            'A road route could not be loaded. Check the internet connection and try again.',
            'تعذر تحميل مسار الطريق. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
    if (!mounted) return;
    setState(() {
      _navigationTarget = attraction;
      _activeBusPlan = null;
      _activeRoadRoute = route;
      _currentInstructionIndex = 0;
      _travelMode = mode;
      _followUser = true;
      _transportEnabled = false;
    });
    _persistState();
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: route.points,
        padding: const EdgeInsets.all(80),
        maxZoom: 16,
      ),
    );
  }

  Future<void> _startBusNavigation(Attraction attraction, LatLng origin) async {
    final destination = LatLng(attraction.latitude, attraction.longitude);
    final initialPlan = _findBestDirectBusPlan(origin, destination);
    if (initialPlan == null) {
      _showMessage(
        _t(
          'No practical direct bus route was found in the offline data.',
          'لم يتم العثور على خط حافلة مباشر مناسب في البيانات دون اتصال.',
        ),
      );
      return;
    }
    setState(() => _isCalculatingRoute = true);
    var plan = initialPlan;
    try {
      final walkingRoutes = await Future.wait([
        _routingService.getRoute(
          origin: origin,
          destination: LatLng(
            initialPlan.boardStop.latitude,
            initialPlan.boardStop.longitude,
          ),
          mode: TravelMode.walking,
        ),
        _routingService.getRoute(
          origin: LatLng(
            initialPlan.alightStop.latitude,
            initialPlan.alightStop.longitude,
          ),
          destination: destination,
          mode: TravelMode.walking,
        ),
      ]);
      plan = initialPlan.withWalkingRoutes(
        toBoard: walkingRoutes[0],
        fromAlight: walkingRoutes[1],
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          _t(
            'The bus route is offline, but these walking connectors are not saved yet. Connect once to download them.',
            'مسار الحافلة متاح دون اتصال، لكن مسارات المشي غير محفوظة بعد. اتصل مرة واحدة لتنزيلها.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
    if (!mounted) return;
    setState(() {
      _navigationTarget = attraction;
      _activeBusPlan = plan;
      _busJourneyPhase = BusJourneyPhase.walkToBoard;
      _busJourneyStopIndex = 0;
      _activeRoadRoute = null;
      _currentInstructionIndex = 0;
      _travelMode = TravelMode.bus;
      _followUser = true;
      _transportEnabled = true;
      _selectedDirectionId = plan.direction.directionId;
    });
    _persistState();
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: [
          ...(plan.walkToBoardRoute?.points ??
              [
                origin,
                LatLng(plan.boardStop.latitude, plan.boardStop.longitude),
              ]),
          ...plan.routeShape,
          ...(plan.walkFromAlightRoute?.points ??
              [
                LatLng(plan.alightStop.latitude, plan.alightStop.longitude),
                destination,
              ]),
        ],
        padding: const EdgeInsets.all(70),
        maxZoom: 14,
      ),
    );
    _showBusJourneySheet(plan, attraction);
  }

  BusJourneyPlan? _findBestDirectBusPlan(LatLng origin, LatLng destination) {
    BusJourneyPlan? best;
    var bestScore = double.infinity;
    for (final direction in _routeDirections) {
      final route = _routeById(direction.routeId);
      final links = List<RouteStopLink>.from(
        _stopLinksByDirection[direction.directionId] ?? const [],
      )..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
      if (route == null || links.length < 2) continue;

      for (var boardIndex = 0; boardIndex < links.length - 1; boardIndex++) {
        final boardLink = links[boardIndex];
        final boardStop = _busStopsById[boardLink.stopId];
        if (boardStop == null) continue;
        final walkToBoard = _distance.as(
          LengthUnit.Kilometer,
          origin,
          LatLng(boardStop.latitude, boardStop.longitude),
        );
        if (walkToBoard > 3) continue;

        for (
          var alightIndex = boardIndex + 1;
          alightIndex < links.length;
          alightIndex++
        ) {
          final alightLink = links[alightIndex];
          final alightStop = _busStopsById[alightLink.stopId];
          if (alightStop == null) continue;
          final walkFromAlight = _distance.as(
            LengthUnit.Kilometer,
            LatLng(alightStop.latitude, alightStop.longitude),
            destination,
          );
          if (walkFromAlight > 3) continue;
          final score =
              walkToBoard + walkFromAlight + (alightIndex - boardIndex) * 0.02;
          if (score >= bestScore) continue;

          final segmentLinks = links.sublist(boardIndex, alightIndex + 1);
          final routeStops = segmentLinks
              .map((link) => _busStopsById[link.stopId])
              .whereType<BusStop>()
              .toList();
          final routeShape = _shapeSegment(
            direction.directionId,
            boardStop,
            alightStop,
          );
          bestScore = score;
          best = BusJourneyPlan(
            direction: direction,
            route: route,
            boardLink: boardLink,
            boardStop: boardStop,
            alightLink: alightLink,
            alightStop: alightStop,
            routeStops: routeStops,
            routeShape: routeShape,
            walkToBoardKm: walkToBoard,
            walkFromAlightKm: walkFromAlight,
          );
        }
      }
    }
    return best;
  }

  List<LatLng> _shapeSegment(
    String directionId,
    BusStop boardStop,
    BusStop alightStop,
  ) {
    final shape = (_shapePointsByDirection[directionId] ?? const [])
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
    if (shape.length < 2) {
      return [
        LatLng(boardStop.latitude, boardStop.longitude),
        LatLng(alightStop.latitude, alightStop.longitude),
      ];
    }
    final boardPoint = LatLng(boardStop.latitude, boardStop.longitude);
    final alightPoint = LatLng(alightStop.latitude, alightStop.longitude);
    var boardIndex = 0;
    var alightIndex = 0;
    var boardDistance = double.infinity;
    var alightDistance = double.infinity;
    for (var index = 0; index < shape.length; index++) {
      final toBoard = _distance.as(LengthUnit.Meter, shape[index], boardPoint);
      if (toBoard < boardDistance) {
        boardDistance = toBoard;
        boardIndex = index;
      }
      final toAlight = _distance.as(
        LengthUnit.Meter,
        shape[index],
        alightPoint,
      );
      if (toAlight < alightDistance) {
        alightDistance = toAlight;
        alightIndex = index;
      }
    }
    if (boardIndex <= alightIndex) {
      return shape.sublist(boardIndex, alightIndex + 1);
    }
    return shape.sublist(alightIndex, boardIndex + 1).reversed.toList();
  }

  void _showBusJourneySheet(BusJourneyPlan plan, Attraction attraction) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                _t('Your bus journey', 'رحلتك بالحافلة'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Route ${plan.route.routeNumber} toward ${plan.direction.destinationEn}',
                  'خط ${plan.route.routeNumber} باتجاه ${plan.direction.destinationAr}',
                ),
              ),
              const Divider(height: 28),
              _journeyStep(
                Icons.directions_walk,
                _t(
                  'Walk ${plan.walkToBoardKm.toStringAsFixed(1)} km to ${plan.boardStop.nameEn}',
                  'امشِ ${plan.walkToBoardKm.toStringAsFixed(1)} كم إلى ${plan.boardStop.nameAr}',
                ),
              ),
              _journeyStep(
                Icons.directions_bus,
                _t(
                  'Board route ${plan.route.routeNumber} at ${plan.boardStop.nameEn}',
                  'اركب خط ${plan.route.routeNumber} عند ${plan.boardStop.nameAr}',
                ),
              ),
              _journeyStep(
                Icons.format_list_numbered,
                _t(
                  'Ride ${math.max(1, plan.stopCount - 1)} stops',
                  'استمر ${math.max(1, plan.stopCount - 1)} محطات',
                ),
              ),
              _journeyStep(
                Icons.exit_to_app,
                _t(
                  'Exit at ${plan.alightStop.nameEn}',
                  'انزل عند ${plan.alightStop.nameAr}',
                ),
              ),
              _journeyStep(
                Icons.flag_outlined,
                _t(
                  'Walk ${plan.walkFromAlightKm.toStringAsFixed(1)} km to ${attraction.nameEn}',
                  'امشِ ${plan.walkFromAlightKm.toStringAsFixed(1)} كم إلى ${attraction.nameAr}',
                ),
              ),
              const Divider(height: 28),
              Text(
                _t('Stops on this journey', 'محطات هذه الرحلة'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ...plan.routeStops.asMap().entries.map((entry) {
                final isBoard = entry.key == 0;
                final isAlight = entry.key == plan.routeStops.length - 1;
                final isPassed = entry.key < _busJourneyStopIndex;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: isBoard
                        ? oasis
                        : isAlight
                        ? terracotta
                        : isPassed
                        ? mutedBrown.withValues(alpha: 0.5)
                        : sandDeep,
                    foregroundColor: isBoard || isAlight || isPassed
                        ? Colors.white
                        : darkBrown,
                    child: Text('${entry.key + 1}'),
                  ),
                  title: Text(
                    _isArabic && entry.value.nameAr.isNotEmpty
                        ? entry.value.nameAr
                        : entry.value.nameEn,
                  ),
                  subtitle: isBoard
                      ? Text(_t('Board here', 'اصعد هنا'))
                      : isAlight
                      ? Text(_t('Get off here', 'انزل هنا'))
                      : null,
                  trailing:
                      entry.key == _busJourneyStopIndex &&
                          _busJourneyPhase == BusJourneyPhase.ride
                      ? const Icon(Icons.my_location, color: _userBlue)
                      : null,
                );
              }),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Routes and stops come from Daleel\'s offline data. There are no live bus times, so allow extra time for waiting.',
                  'الخطوط والمحطات من بيانات دليل المحفوظة. لا توجد أوقات مباشرة للحافلات، لذا خصّص وقتاً إضافياً للانتظار.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _journeyStep(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  void _stopNavigation() {
    setState(() {
      _navigationTarget = null;
      _activeBusPlan = null;
      _busJourneyPhase = BusJourneyPhase.walkToBoard;
      _busJourneyStopIndex = 0;
      _activeRoadRoute = null;
      _currentInstructionIndex = 0;
      _followUser = false;
    });
  }

  void _openAttractionDetails(Attraction attraction) {
    widget.onOpenDetails?.call(attraction.attractionId);
  }

  /// The blue "you are here" dot is a platform convention, so it stays blue.
  static const Color _userBlue = Color(0xFF1F6FD1);

  @override
  Widget build(BuildContext context) {
    final attractionMarkers = _filteredAttractions
        .map(_buildAttractionMarker)
        .toList();
    final selectedDirection = _selectedDirection;
    final selectedRoute = selectedDirection == null
        ? null
        : _routeById(selectedDirection.routeId);
    final selectedShapePoints =
        _activeBusPlan?.routeShape ?? _selectedShapePoints;
    final visibleStopLinks = _activeBusPlan == null
        ? _selectedStopLinks
        : _selectedStopLinks
              .where(
                (link) =>
                    link.stopSequence >=
                        _activeBusPlan!.boardLink.stopSequence &&
                    link.stopSequence <=
                        _activeBusPlan!.alightLink.stopSequence,
              )
              .toList();
    final busStopMarkers = _transportEnabled && selectedDirection != null
        ? visibleStopLinks
              .map((link) {
                final stop = _busStopsById[link.stopId];
                return stop == null
                    ? null
                    : _buildBusStopMarker(
                        stop,
                        link.stopSequence,
                        selectedDirection,
                        selectedRoute,
                      );
              })
              .whereType<Marker>()
              .toList()
        : <Marker>[];
    final navigating = _navigationTarget != null;
    final busy = _isCalculatingRoute || _isCalculatingTripRoute;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Directionality(
        textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: sand,
          body: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(24.18, 55.75),
                    initialZoom: 11,
                    minZoom: 8,
                    maxZoom: 18,
                    cameraConstraint: CameraConstraint.unconstrained(),
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all,
                      scrollWheelVelocity: 0.005,
                    ),
                  ),
                  children: [
                    if (_offlineMap != null)
                      vt.VectorTileLayer(
                        key: ValueKey<String>(
                          'offline-map-${_isArabic ? 'ar' : 'en'}-'
                          '${Theme.of(context).brightness.name}',
                        ),
                        theme: _offlineMap!.style.theme,
                        tileProviders: _offlineMap!.style.providers,
                        rasterSources: _offlineMap!.style.rasterSources,
                        sprites: _offlineMap!.style.sprites,
                        // Keep the map predictable inside the full app. The
                        // package defaults may retain up to 256 MiB of GPU
                        // tiles on a large/high-DPI display.
                        concurrency: 2,
                        diskCacheMaximumSizeInBytes: 0,
                        memoryCacheMaxBytes: 12 * 1024 * 1024,
                        rasterCacheMaxBytes: 64 * 1024 * 1024,
                        logger: const vt.Logger.console(),
                      )
                    else
                      const ColoredBox(color: sand),
                    if (_transportEnabled &&
                        selectedRoute != null &&
                        selectedShapePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: selectedShapePoints,
                            color: selectedRoute.color,
                            strokeWidth: 5,
                            borderColor: Colors.white,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (_tripDisplayPoints.length >= 2 && !navigating)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _tripDisplayPoints,
                            color: _travelModeColor,
                            strokeWidth: 6,
                            borderColor: Colors.white,
                            borderStrokeWidth: 2,
                            pattern: const StrokePattern.solid(),
                          ),
                        ],
                      ),
                    if (_navigationPoints.length >= 2 && _activeBusPlan == null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _navigationPoints,
                            color: _travelModeColor,
                            strokeWidth: 6,
                            borderColor: Colors.white,
                            borderStrokeWidth: 2,
                            pattern: const StrokePattern.solid(),
                          ),
                        ],
                      ),
                    if (_activeBusPlan != null &&
                        _currentLocation != null &&
                        navigating)
                      PolylineLayer(
                        polylines: [
                          if (_activeBusPlan!.walkToBoardRoute != null)
                            Polyline(
                              points: _activeBusPlan!.walkToBoardRoute!.points,
                              color:
                                  _busJourneyPhase == BusJourneyPhase.walkToBoard
                                  ? terracotta
                                  : mutedBrown.withValues(alpha: 0.6),
                              strokeWidth:
                                  _busJourneyPhase == BusJourneyPhase.walkToBoard
                                  ? 7
                                  : 4,
                              pattern: const StrokePattern.dotted(),
                            ),
                          if (_activeBusPlan!.walkFromAlightRoute != null)
                            Polyline(
                              points:
                                  _activeBusPlan!.walkFromAlightRoute!.points,
                              color:
                                  _busJourneyPhase ==
                                      BusJourneyPhase.walkToDestination
                                  ? terracotta
                                  : terracotta.withValues(alpha: 0.55),
                              strokeWidth:
                                  _busJourneyPhase ==
                                      BusJourneyPhase.walkToDestination
                                  ? 7
                                  : 4,
                              pattern: const StrokePattern.dotted(),
                            ),
                        ],
                      ),
                    if (_clusteringEnabled)
                      MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          markers: attractionMarkers,
                          maxClusterRadius: 55,
                          size: const Size(48, 48),
                          padding: const EdgeInsets.all(50),
                          maxZoom: 17,
                          disableClusteringAtZoom: 16,
                          zoomToBoundsOnClick: true,
                          spiderfyCluster: true,
                          markerChildBehavior: true,
                          builder: (context, markers) =>
                              _buildCluster(markers.length),
                        ),
                      )
                    else
                      MarkerLayer(markers: attractionMarkers),
                    if (_transportEnabled && busStopMarkers.isNotEmpty)
                      MarkerLayer(markers: busStopMarkers),
                    if (_currentLocation != null)
                      MarkerLayer(
                        markers: [
                          _buildCurrentLocationMarker(_currentLocation!),
                        ],
                      ),
                    const RichAttributionWidget(
                      alignment: AttributionAlignment.bottomLeft,
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
              ),
              if (_isLoadingData)
                Positioned.fill(
                  child: ColoredBox(
                    color: sand.withValues(alpha: 0.72),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (!_isLoadingData &&
                  _dataError == null &&
                  _filteredAttractions.isEmpty &&
                  !navigating)
                Positioned.fill(child: _buildEmptyState()),
              if (_offlineMapError != null && _dataError == null)
                PositionedDirectional(
                  start: 12,
                  bottom: 48,
                  child: _buildOfflineMapErrorNotice(),
                ),
              // Floating controls over the map. During directions the search
              // and filters step aside so the route gets the screen.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (navigating)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: _buildNavigationBanner(),
                        )
                      else ...[
                        _buildSearchBar(),
                        _buildChipRow(),
                        if (_transportEnabled) _buildRoutePicker(),
                      ],
                      if (busy)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: const LinearProgressIndicator(minHeight: 4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_dataError != null) Positioned.fill(child: _buildDataError()),
            ],
          ),
          floatingActionButton: _dataError == null ? _buildFabs() : null,
        ),
      ),
    );
  }

  Widget _floatingSurface({
    required Widget child,
    BorderRadiusGeometry? radius,
    ShapeBorder? shape,
  }) {
    return Material(
      color: parchment,
      elevation: 3,
      shadowColor: darkBrown.withValues(alpha: 0.35),
      shape:
          shape ??
          RoundedRectangleBorder(
            borderRadius: radius ?? BorderRadius.circular(18),
            side: const BorderSide(color: duneLine),
          ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: _floatingSurface(
        shape: const StadiumBorder(side: BorderSide(color: duneLine)),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 16, end: 8),
              child: Icon(Icons.search, color: mutedBrown),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _searchAttractions,
                onSubmitted: _submitSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _t('Search places', 'ابحث عن مكان'),
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              IconButton(
                onPressed: _clearSearch,
                tooltip: _t('Clear search', 'مسح البحث'),
                icon: const Icon(Icons.close),
              )
            else
              IconButton(
                onPressed: _isLoadingLocation ? null : _enableNearMe,
                tooltip: _t('Places near me', 'أماكن قريبة مني'),
                icon: const Icon(Icons.near_me_outlined),
              ),
            IconButton(
              onPressed: _showMapOptions,
              tooltip: _t('Map options', 'خيارات الخريطة'),
              icon: const Icon(Icons.layers_outlined),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildChipRow() {
    final shadow = darkBrown.withValues(alpha: 0.3);
    Widget gap(Widget chip) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: chip,
    );
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        children: [
          gap(
            FilterChip(
              elevation: 2,
              shadowColor: shadow,
              showCheckmark: false,
              avatar: const Icon(
                Icons.directions_bus_outlined,
                size: 18,
                color: falaj,
              ),
              label: Text(_t('Buses', 'الحافلات')),
              selected: _transportEnabled,
              onSelected: (_) => _toggleTransport(),
            ),
          ),
          gap(
            FilterChip(
              elevation: 2,
              shadowColor: shadow,
              showCheckmark: false,
              avatar: Icon(
                _savedOnly ? Icons.bookmark : Icons.bookmark_border,
                size: 18,
                color: terracotta,
              ),
              label: Text(_t('Saved', 'المحفوظة')),
              selected: _savedOnly,
              onSelected: (on) => setState(() => _savedOnly = on),
            ),
          ),
          gap(
            ChoiceChip(
              elevation: 2,
              shadowColor: shadow,
              showCheckmark: false,
              label: Text(_t('All', 'الكل')),
              selected: _selectedCategoryId == null,
              onSelected: (_) => setState(() => _selectedCategoryId = null),
            ),
          ),
          for (final category in _categories)
            gap(
              ChoiceChip(
                elevation: 2,
                shadowColor: shadow,
                showCheckmark: false,
                avatar: Icon(
                  PlaceCategory.icon(category.categoryId),
                  size: 18,
                  color: PlaceCategory.color(category.categoryId),
                ),
                label: Text(_isArabic ? category.nameAr : category.nameEn),
                selected: _selectedCategoryId == category.categoryId,
                onSelected: (on) => setState(
                  () => _selectedCategoryId = on ? category.categoryId : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoutePicker() {
    final direction = _selectedDirection;
    final route = direction == null ? null : _routeById(direction.routeId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: _floatingSurface(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
          child: Row(
            children: [
              const Icon(Icons.directions_bus, color: falaj),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedDirectionId,
                    isExpanded: true,
                    menuMaxHeight: 420,
                    dropdownColor: parchment,
                    borderRadius: BorderRadius.circular(16),
                    items: _routeDirections.map((item) {
                      final itemRoute = _routeById(item.routeId);
                      final destination =
                          _isArabic && item.destinationAr.isNotEmpty
                          ? item.destinationAr
                          : item.destinationEn;
                      return DropdownMenuItem(
                        value: item.directionId,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: itemRoute?.color ?? falaj,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${_t('Route', 'خط')} ${itemRoute?.routeNumber ?? '?'} → $destination',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _selectRouteDirection,
                  ),
                ),
              ),
              if (route != null) const SizedBox(width: 4),
              IconButton(
                onPressed: _toggleTransport,
                tooltip: _t('Hide buses', 'إخفاء الحافلات'),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFabs() {
    final navigating = _navigationTarget != null;
    final tripLabel = _tripRouteError != null
        ? _t('Trip · route unavailable', 'الرحلة · المسار غير متاح')
        : _t(
            '${_tripStopIds.length} stops · ${_tripDistanceKm.toStringAsFixed(1)} km · ~$_tripDurationMinutes min',
            '${_tripStopIds.length} محطات · ${_tripDistanceKm.toStringAsFixed(1)} كم · ~$_tripDurationMinutes دقيقة',
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!navigating) ...[
          if (_tripStopIds.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: 'plannerButton',
              onPressed: _showTripPlanner,
              tooltip: _t('Open trip planner', 'فتح مخطط الرحلة'),
              icon: _isCalculatingTripRoute
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_travelModeIcon),
              label: Text(tripLabel),
            )
          else
            FloatingActionButton.small(
              heroTag: 'plannerButton',
              onPressed: _showTripPlanner,
              tooltip: _t('Plan a trip', 'خطط رحلة'),
              child: const Icon(Icons.route),
            ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          heroTag: 'currentLocationButton',
          onPressed: _isLoadingLocation ? null : _toggleLiveTracking,
          tooltip: _t(
            _liveTrackingEnabled
                ? (_followUser ? 'Stop following me' : 'Follow me')
                : 'Show my location',
            _liveTrackingEnabled
                ? (_followUser ? 'إيقاف تتبعي' : 'تتبعني')
                : 'أظهر موقعي',
          ),
          child: _isLoadingLocation
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Icon(
                  _liveTrackingEnabled
                      ? (_followUser
                            ? Icons.navigation
                            : Icons.location_searching)
                      : Icons.my_location,
                ),
        ),
      ],
    );
  }

  void _showAllPlaces() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedCategoryId = null;
      _savedOnly = false;
    });
  }

  Widget _buildEmptyState() {
    final savedEmpty = _savedOnly && _favoriteIds.isEmpty;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: _floatingSurface(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  savedEmpty ? Icons.bookmark_border : Icons.travel_explore,
                  size: 34,
                  color: mutedBrown,
                ),
                const SizedBox(height: 10),
                Text(
                  savedEmpty
                      ? _t('No saved places yet', 'لا توجد أماكن محفوظة بعد')
                      : _t('No places match', 'لا توجد أماكن مطابقة'),
                  textAlign: TextAlign.center,
                  style: text.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  savedEmpty
                      ? _t(
                          'Tap Save on a place and it will appear here.',
                          'اضغط «حفظ» في أي مكان وسيظهر هنا.',
                        )
                      : _t(
                          'Try another search or category.',
                          'جرّب بحثاً أو فئة أخرى.',
                        ),
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _showAllPlaces,
                  child: Text(_t('Show all places', 'عرض كل الأماكن')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMapOptions() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('Map options', 'خيارات الخريطة'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.directions_bus_outlined),
                  title: Text(_t('Show bus routes', 'إظهار مسارات الحافلات')),
                  value: _transportEnabled,
                  onChanged: (_) {
                    _toggleTransport();
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.bubble_chart_outlined),
                  title: Text(_t('Group nearby places', 'تجميع الأماكن المتقاربة')),
                  subtitle: Text(
                    _t(
                      'Shows a number where places overlap',
                      'يعرض رقماً عندما تتداخل الأماكن',
                    ),
                  ),
                  value: _clusteringEnabled,
                  onChanged: (_) {
                    _toggleClustering();
                    setSheetState(() {});
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.zoom_out_map),
                  title: Text(_t('Reset map view', 'إعادة ضبط عرض الخريطة')),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _resetMapView();
                  },
                ),
                const Divider(height: 28),
                Text(
                  _t('Map key', 'مفتاح الخريطة'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    for (final category in _categories)
                      MetaItem(
                        icon: PlaceCategory.icon(category.categoryId),
                        label: _isArabic ? category.nameAr : category.nameEn,
                        color: PlaceCategory.color(category.categoryId),
                      ),
                    MetaItem(
                      icon: Icons.bookmark,
                      label: _t('Saved place', 'مكان محفوظ'),
                      color: terracotta,
                    ),
                    MetaItem(
                      icon: Icons.directions_bus,
                      label: _t('Bus stop', 'محطة حافلات'),
                      color: falaj,
                    ),
                    MetaItem(
                      icon: Icons.navigation,
                      label: _t('Your location', 'موقعك'),
                      color: _userBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color get _travelModeColor => switch (_travelMode) {
    TravelMode.walking => terracotta,
    TravelMode.driving => darkBrown,
    TravelMode.bus => falaj,
  };

  Widget _buildCluster(int count) {
    return Semantics(
      button: true,
      label: _t('$count places here, tap to zoom in', '$count أماكن هنا، اضغط للتكبير'),
      child: Container(
        decoration: BoxDecoration(
          color: terracotta,
          shape: BoxShape.circle,
          border: Border.all(color: parchment, width: 3),
          boxShadow: [
            BoxShadow(
              color: darkBrown.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationBanner() {
    final target = _navigationTarget!;
    final plan = _activeBusPlan;
    final instruction = _currentRoadInstruction;
    final subtitle = plan == null
        ? _t(
            '${_navigationDistanceKm.toStringAsFixed(1)} km · about $_navigationEtaMinutes min${instruction == null ? '' : ' · ${_instructionText(instruction)}'}',
            '${_navigationDistanceKm.toStringAsFixed(1)} كم · حوالي $_navigationEtaMinutes دقيقة${instruction == null ? '' : ' · ${_instructionText(instruction)}'}',
          )
        : switch (_busJourneyPhase) {
            BusJourneyPhase.walkToBoard => _t(
              'Walk ${plan.walkToBoardKm.toStringAsFixed(1)} km to ${plan.boardStop.nameEn} · board route ${plan.route.routeNumber}',
              'امشِ ${plan.walkToBoardKm.toStringAsFixed(1)} كم إلى ${plan.boardStop.nameAr} · اركب خط ${plan.route.routeNumber}',
            ),
            BusJourneyPhase.ride => _t(
              'Ride route ${plan.route.routeNumber} · ${math.max(0, plan.routeStops.length - 1 - _busJourneyStopIndex)} stops remaining · get off at ${plan.alightStop.nameEn}',
              'استمر على خط ${plan.route.routeNumber} · ${math.max(0, plan.routeStops.length - 1 - _busJourneyStopIndex)} محطات متبقية · انزل عند ${plan.alightStop.nameAr}',
            ),
            BusJourneyPhase.walkToDestination => _t(
              'Get off at ${plan.alightStop.nameEn} · walk ${plan.walkFromAlightKm.toStringAsFixed(1)} km to ${target.nameEn}',
              'انزل عند ${plan.alightStop.nameAr} · امشِ ${plan.walkFromAlightKm.toStringAsFixed(1)} كم إلى ${target.nameAr}',
            ),
          };
    return _floatingSurface(
      child: InkWell(
        onTap: plan == null
            ? _showRoadDirectionsSheet
            : () => _showBusJourneySheet(plan, target),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 4, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _travelModeColor,
                  shape: BoxShape.circle,
                ),
                child: Transform.rotate(
                  angle: _navigationBearingRadians,
                  child: const Icon(Icons.navigation, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isArabic ? target.nameAr : target.nameEn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (plan == null &&
                        _activeRoadRoute?.fromOfflineCache == true)
                      Text(
                        _t(
                          'Using a route saved for offline navigation',
                          'يتم استخدام مسار محفوظ للتنقل دون اتصال',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: oasis,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (_liveTrackingEnabled && _currentSpeedMps > 0.5)
                      Text(
                        _t(
                          '${(_currentSpeedMps * 3.6).toStringAsFixed(0)} km/h',
                          '${(_currentSpeedMps * 3.6).toStringAsFixed(0)} كم/س',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _t('End directions', 'إنهاء الاتجاهات'),
                onPressed: _stopNavigation,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double get _navigationBearingRadians {
    final location = _currentLocation;
    final points = _navigationPoints;
    if (location == null || points.length < 2) return 0;
    final nearestIndex = _nearestRoutePointIndex(points, location);
    final lookAheadIndex = math.min(nearestIndex + 4, points.length - 1);
    final bearing = _distance.bearing(location, points[lookAheadIndex]);
    final relativeBearing = bearing - _currentHeading;
    return relativeBearing * math.pi / 180;
  }

  RouteInstruction? get _currentRoadInstruction {
    final instructions = _activeRoadRoute?.instructions ?? const [];
    if (instructions.isEmpty) return null;
    return instructions[_currentInstructionIndex.clamp(
      0,
      instructions.length - 1,
    )];
  }

  String _instructionText(RouteInstruction instruction) {
    final road = instruction.roadName.isEmpty
        ? _t('the road', 'الطريق')
        : instruction.roadName;
    switch (instruction.type) {
      case 'depart':
        return _t('Start on $road', 'ابدأ على $road');
      case 'arrive':
        return _t('Arrive at the destination', 'الوصول إلى الوجهة');
      case 'roundabout':
      case 'rotary':
        return _t('Enter the roundabout toward $road', 'ادخل الدوار نحو $road');
      case 'merge':
        return _t('Merge onto $road', 'اندمج في $road');
      case 'fork':
        return _t(
          'Keep ${instruction.modifier} on $road',
          'استمر ${instruction.modifier} على $road',
        );
      default:
        final modifier = instruction.modifier.replaceAll('_', ' ');
        if (modifier.contains('left')) {
          return _t('Turn left onto $road', 'انعطف يساراً إلى $road');
        }
        if (modifier.contains('right')) {
          return _t('Turn right onto $road', 'انعطف يميناً إلى $road');
        }
        if (modifier == 'uturn') {
          return _t('Make a U-turn onto $road', 'قم بالاستدارة إلى $road');
        }
        return _t('Continue on $road', 'استمر على $road');
    }
  }

  void _showRoadDirectionsSheet() {
    final route = _activeRoadRoute;
    if (route == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  _t('Turn-by-turn directions', 'إرشادات خطوة بخطوة'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: route.instructions.length,
                  itemBuilder: (context, index) {
                    final item = route.instructions[index];
                    final active = index == _currentInstructionIndex;
                    return ListTile(
                      selected: active,
                      leading: CircleAvatar(
                        backgroundColor: active
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        foregroundColor: active ? Colors.white : null,
                        child: Icon(
                          item.type == 'arrive' ? Icons.flag : Icons.turn_right,
                        ),
                      ),
                      title: Text(_instructionText(item)),
                      subtitle: Text(
                        item.distanceMeters < 1000
                            ? '${item.distanceMeters.round()} m'
                            : '${(item.distanceMeters / 1000).toStringAsFixed(1)} km',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _travelModeIcon => switch (_travelMode) {
    TravelMode.walking => Icons.directions_walk,
    TravelMode.driving => Icons.directions_car,
    TravelMode.bus => Icons.directions_bus,
  };

  Widget _buildDataError() {
    return ColoredBox(
      color: sand.withValues(alpha: 0.96),
      child: ErrorPanel(
        icon: Icons.map_outlined,
        title: _t('The map could not load', 'تعذّر تحميل الخريطة'),
        body: _t(
          'Daleel could not read its offline map data. Please try again.',
          'تعذّر على دليل قراءة بيانات الخريطة المحفوظة. حاول مرة أخرى.',
        ),
        retryLabel: _t('Try again', 'حاول مرة أخرى'),
        onRetry: _loadMapData,
      ),
    );
  }

  Widget _buildOfflineMapErrorNotice() {
    return _floatingSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.offline_bolt_outlined, size: 18),
            const SizedBox(width: 8),
            Text(_t('Street map unavailable', 'خريطة الشوارع غير متاحة')),
          ],
        ),
      ),
    );
  }

  Marker _buildAttractionMarker(Attraction attraction) {
    final tripIndex = _tripStopIds.indexOf(attraction.attractionId);
    final saved = _favoriteIds.contains(attraction.attractionId);
    final color = _colorForCategory(attraction.categoryId);
    final name = _isArabic ? attraction.nameAr : attraction.nameEn;
    return Marker(
      point: LatLng(attraction.latitude, attraction.longitude),
      width: 52,
      height: 52,
      child: Semantics(
        button: true,
        label: name,
        child: GestureDetector(
          onTap: () => _showAttractionPopup(attraction),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: BoxDecoration(
                      color: parchment,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                          color: darkBrown.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _iconForCategory(attraction.categoryId),
                      size: 24,
                      color: color,
                    ),
                  ),
                ),
              ),
              if (saved)
                const PositionedDirectional(
                  start: -2,
                  top: -2,
                  child: _MarkerBadge(
                    color: terracotta,
                    child: Icon(Icons.bookmark, color: Colors.white, size: 12),
                  ),
                ),
              if (tripIndex >= 0)
                PositionedDirectional(
                  end: -2,
                  top: -2,
                  child: _MarkerBadge(
                    color: _travelModeColor,
                    child: Text(
                      '${tripIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _buildBusStopMarker(
    BusStop stop,
    int sequence,
    RouteDirection direction,
    BusRoute? route,
  ) {
    final plan = _activeBusPlan;
    final isBoarding = plan?.boardStop.stopId == stop.stopId;
    final isAlighting = plan?.alightStop.stopId == stop.stopId;
    final journeyIndex = plan == null
        ? -1
        : sequence - plan.boardLink.stopSequence;
    final isCurrentJourneyStop =
        plan != null &&
        _busJourneyPhase == BusJourneyPhase.ride &&
        journeyIndex == _busJourneyStopIndex;
    final isPassedJourneyStop =
        plan != null &&
        journeyIndex >= 0 &&
        journeyIndex < _busJourneyStopIndex;
    final color = isBoarding
        ? oasis
        : isAlighting
        ? terracotta
        : isCurrentJourneyStop
        ? _userBlue
        : isPassedJourneyStop
        ? mutedBrown.withValues(alpha: 0.6)
        : route?.color ?? falaj;
    final emphasized = isBoarding || isAlighting || isCurrentJourneyStop;
    return Marker(
      point: LatLng(stop.latitude, stop.longitude),
      width: emphasized ? 46 : 40,
      height: emphasized ? 46 : 40,
      child: Semantics(
        button: true,
        label:
            '${_t('Bus stop', 'محطة حافلات')} ${_isArabic && stop.nameAr.isNotEmpty ? stop.nameAr : stop.nameEn}',
        child: GestureDetector(
        onTap: () => _showBusStopPopup(stop, sequence, direction, route),
        child: Container(
          decoration: BoxDecoration(
            color: parchment,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: darkBrown.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Icon(
            isBoarding
                ? Icons.login
                : isAlighting
                ? Icons.logout
                : isCurrentJourneyStop
                ? Icons.my_location
                : Icons.directions_bus,
            size: emphasized ? 23 : 19,
            color: color,
          ),
        ),
      ),
      ),
    );
  }

  Marker _buildCurrentLocationMarker(LatLng location) {
    return Marker(
      point: location,
      width: 42,
      height: 42,
      child: Transform.rotate(
        angle: _currentHeading * math.pi / 180,
        child: Container(
          decoration: BoxDecoration(
            color: _userBlue.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                blurRadius: 6,
                offset: const Offset(0, 2),
                color: darkBrown.withValues(alpha: 0.3),
              ),
            ],
          ),
          child: const Icon(Icons.navigation, size: 22, color: _userBlue),
        ),
      ),
    );
  }

  void _showAttractionPopup(Attraction attraction) {
    // Saved state is owned by the host app, which rebuilds the map after a
    // toggle; the sheet keeps its own copy so it updates instantly.
    var saved = _favoriteIds.contains(attraction.attractionId);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final inTrip = _tripStopIds.contains(attraction.attractionId);
          final text = Theme.of(context).textTheme;
          final category = _categories
              .where((c) => c.categoryId == attraction.categoryId)
              .firstOrNull;
          final km = _currentLocation == null
              ? null
              : _distanceToAttraction(attraction);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isArabic ? attraction.nameAr : attraction.nameEn,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      if (category != null)
                        MetaItem(
                          icon: _iconForCategory(category.categoryId),
                          label: _isArabic ? category.nameAr : category.nameEn,
                          color: _colorForCategory(category.categoryId),
                        ),
                      MetaItem(
                        icon: Icons.confirmation_number_outlined,
                        label: attraction.entryPriceAed == 0
                            ? _t('Free', 'مجاني')
                            : '${attraction.entryPriceAed.toStringAsFixed(0)} ${_t('AED', 'درهم')}',
                      ),
                      if (km != null)
                        MetaItem(
                          icon: Icons.near_me_outlined,
                          label: km < 1
                              ? _t('${(km * 1000).round()} m away', 'يبعد ${(km * 1000).round()} متر')
                              : _t('${km.toStringAsFixed(1)} km away', 'يبعد ${km.toStringAsFixed(1)} كم'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetAction(
                        primary: true,
                        icon: Icons.directions,
                        label: _t('Directions', 'الاتجاهات'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _showNavigationOptions(attraction);
                        },
                      ),
                      _SheetAction(
                        icon: saved ? Icons.bookmark : Icons.bookmark_border,
                        label: saved ? _t('Saved', 'محفوظ') : _t('Save', 'حفظ'),
                        selected: saved,
                        onTap: () {
                          _toggleFavorite(attraction);
                          setSheetState(() => saved = !saved);
                        },
                      ),
                      _SheetAction(
                        icon: inTrip ? Icons.playlist_add_check : Icons.playlist_add,
                        label: inTrip
                            ? _t('In trip', 'في الرحلة')
                            : _t('Add to trip', 'أضف للرحلة'),
                        selected: inTrip,
                        onTap: () {
                          _toggleTripStop(attraction);
                          setSheetState(() {});
                        },
                      ),
                      if (widget.onOpenDetails != null)
                        _SheetAction(
                          icon: Icons.info_outline,
                          label: _t('Details', 'التفاصيل'),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openAttractionDetails(attraction);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showBusStopPopup(
    BusStop stop,
    int sequence,
    RouteDirection direction,
    BusRoute? route,
  ) {
    final nearby = _attractions.toList()
      ..sort((a, b) {
        final point = LatLng(stop.latitude, stop.longitude);
        return _distance
            .as(LengthUnit.Meter, point, LatLng(a.latitude, a.longitude))
            .compareTo(
              _distance.as(
                LengthUnit.Meter,
                point,
                LatLng(b.latitude, b.longitude),
              ),
            );
      });
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isArabic && stop.nameAr.isNotEmpty ? stop.nameAr : stop.nameEn,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              MetaItem(
                icon: Icons.directions_bus,
                color: route?.color ?? falaj,
                label:
                    '${_t('Route', 'خط')} ${route?.routeNumber ?? ''} · ${_t('stop', 'المحطة')} $sequence · ${_t('towards', 'باتجاه')} ${_isArabic ? direction.destinationAr : direction.destinationEn}',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: sandDeep,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.schedule, color: mutedBrown),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _t(
                          'Daleel has no live times or timetable for this stop, so it cannot say when the next bus comes. Allow extra time for waiting.',
                          'لا تتوفر لدى دليل أوقات مباشرة أو جدول لهذه المحطة، لذلك لا يمكنه معرفة موعد الحافلة التالية. خصّص وقتاً إضافياً للانتظار.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _t('Places near this stop', 'أماكن قريبة من هذه المحطة'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...nearby.take(3).map((attraction) {
                final meters = _distance.as(
                  LengthUnit.Meter,
                  LatLng(stop.latitude, stop.longitude),
                  LatLng(attraction.latitude, attraction.longitude),
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _iconForCategory(attraction.categoryId),
                    color: _colorForCategory(attraction.categoryId),
                  ),
                  title: Text(
                    _isArabic ? attraction.nameAr : attraction.nameEn,
                  ),
                  subtitle: Text(
                    _t('${meters.round()} m walk', '${meters.round()} متر سيراً'),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _mapController.move(
                      LatLng(attraction.latitude, attraction.longitude),
                      15,
                    );
                    _showAttractionPopup(attraction);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTripPlanner() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final stops = _tripStops;
          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.88,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _t('Your trip', 'رحلتك'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showSavedTrips(setSheetState),
                          tooltip: _t('Saved trips', 'الرحلات المحفوظة'),
                          icon: Badge(
                            isLabelVisible: _savedTrips.isNotEmpty,
                            label: Text('${_savedTrips.length}'),
                            child: const Icon(Icons.bookmarks_outlined),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<TravelMode>(
                      segments: [
                        ButtonSegment(
                          value: TravelMode.walking,
                          icon: const Icon(Icons.directions_walk),
                          label: Text(_t('Walk', 'مشي')),
                        ),
                        ButtonSegment(
                          value: TravelMode.driving,
                          icon: const Icon(Icons.directions_car),
                          label: Text(_t('Drive', 'سيارة')),
                        ),
                        ButtonSegment(
                          value: TravelMode.bus,
                          icon: const Icon(Icons.directions_bus),
                          label: Text(_t('Bus', 'حافلة')),
                        ),
                      ],
                      selected: {_travelMode},
                      onSelectionChanged: (selection) {
                        setState(() => _travelMode = selection.first);
                        setSheetState(() {});
                        _persistState();
                        unawaited(
                          _refreshTripRoute().whenComplete(
                            () => setSheetState(() {}),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: ListTile(
                        leading: Icon(_travelModeIcon, color: _travelModeColor),
                        title: Text(
                          _travelMode == TravelMode.bus && stops.isNotEmpty
                              ? _t(
                                  'From your location to ${stops.last.nameEn}',
                                  'من موقعك إلى ${stops.last.nameAr}',
                                )
                              : _t(
                                  '${_tripDistanceKm.toStringAsFixed(1)} km · about $_tripDurationMinutes min',
                                  '${_tripDistanceKm.toStringAsFixed(1)} كم · حوالي $_tripDurationMinutes دقيقة',
                                ),
                        ),
                        subtitle: Text(
                          _tripRouteError != null
                              ? _t(
                                  'This route is not saved offline yet. Connect to the internet once, then reopen the trip.',
                                  'هذا المسار غير محفوظ دون اتصال بعد. اتصل بالإنترنت مرة واحدة ثم افتح الرحلة من جديد.',
                                )
                              : _travelMode == TravelMode.bus
                              ? _t(
                                  'Bus suggestions use Daleel\'s offline routes and stops',
                                  'اقتراحات الحافلات تستخدم خطوط ومحطات دليل المحفوظة',
                                )
                              : _isCalculatingTripRoute
                              ? _t(
                                  'Calculating the route along mapped roads…',
                                  'جارٍ حساب المسار عبر الطرق المرسومة…',
                                )
                              : _t(
                                  'Route follows mapped roads and paths',
                                  'المسار يتبع الطرق والممرات المرسومة',
                                ),
                        ),
                      ),
                    ),
                    if (_travelMode == TravelMode.bus && stops.isNotEmpty)
                      _buildBusSuggestion(),
                    Expanded(
                      child: stops.isEmpty
                          ? Center(
                              child: Text(
                                _t(
                                  'Tap a place on the map and choose Add to trip, or use Add stop below.',
                                  'اضغط على مكان في الخريطة واختر «أضف للرحلة»، أو استخدم «أضف محطة» أدناه.',
                                ),
                              ),
                            )
                          : ReorderableListView.builder(
                              itemCount: stops.length,
                              onReorderItem: (oldIndex, newIndex) {
                                setState(() {
                                  final item = _tripStopIds.removeAt(oldIndex);
                                  _tripStopIds.insert(newIndex, item);
                                });
                                setSheetState(() {});
                                _persistState();
                                unawaited(
                                  _refreshTripRoute().whenComplete(
                                    () => setSheetState(() {}),
                                  ),
                                );
                              },
                              itemBuilder: (context, index) {
                                final attraction = stops[index];
                                return ListTile(
                                  key: ValueKey(attraction.attractionId),
                                  leading: CircleAvatar(
                                    backgroundColor: _travelModeColor,
                                    foregroundColor: Colors.white,
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(
                                    _isArabic
                                        ? attraction.nameAr
                                        : attraction.nameEn,
                                  ),
                                  subtitle:
                                      _travelMode == TravelMode.bus &&
                                          index == stops.length - 1
                                      ? Text(
                                          _t(
                                            'Bus from your location',
                                            'بالحافلة من موقعك',
                                          ),
                                        )
                                      : index == 0
                                      ? Text(_t('Start', 'البداية'))
                                      : null,
                                  trailing: IconButton(
                                    tooltip: _t('Remove from trip', 'إزالة من الرحلة'),
                                    onPressed: () {
                                      setState(
                                        () => _tripStopIds.remove(
                                          attraction.attractionId,
                                        ),
                                      );
                                      setSheetState(() {});
                                      _persistState();
                                      unawaited(
                                        _refreshTripRoute().whenComplete(
                                          () => setSheetState(() {}),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickTripAttraction(setSheetState),
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: Text(_t('Add stop', 'أضف محطة')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: stops.length < 3
                                ? null
                                : () => _optimizeTrip(setSheetState),
                            icon: const Icon(Icons.swap_vert),
                            label: Text(_t('Shortest order', 'أقصر ترتيب')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: stops.isEmpty || _isCalculatingRoute
                            ? null
                            : () {
                                Navigator.pop(sheetContext);
                                unawaited(_startTripNavigation());
                              },
                        icon: const Icon(Icons.navigation),
                        label: Text(
                          _travelMode == TravelMode.bus
                              ? _t(
                                  'Start bus journey',
                                  'ابدأ رحلة الحافلة',
                                )
                              : _t(
                                  'Start directions',
                                  'ابدأ الاتجاهات',
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: stops.isEmpty
                                ? null
                                : () => _saveCurrentTrip(setSheetState),
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_t('Save', 'حفظ')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: stops.isEmpty ? null : _shareTrip,
                            icon: const Icon(Icons.share_outlined),
                            label: Text(_t('Share', 'مشاركة')),
                          ),
                        ),
                        IconButton(
                          onPressed: stops.isEmpty
                              ? null
                              : () {
                                  final previous = List<int>.from(_tripStopIds);
                                  setState(_tripStopIds.clear);
                                  setSheetState(() {});
                                  _persistState();
                                  unawaited(_refreshTripRoute());
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      SnackBar(
                                        content: Text(_t('Trip cleared', 'تم مسح الرحلة')),
                                        action: SnackBarAction(
                                          label: _t('Undo', 'تراجع'),
                                          onPressed: () {
                                            if (!mounted) return;
                                            setState(
                                              () => _tripStopIds
                                                ..clear()
                                                ..addAll(previous),
                                            );
                                            if (context.mounted) {
                                              setSheetState(() {});
                                            }
                                            _persistState();
                                            unawaited(_refreshTripRoute());
                                          },
                                        ),
                                      ),
                                    );
                                },
                          tooltip: _t('Clear trip', 'مسح الرحلة'),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (_tripDisplayPoints.length >= 2 && mounted) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _tripDisplayPoints,
          padding: const EdgeInsets.all(70),
          maxZoom: 14,
        ),
      );
    }
  }

  Widget _buildBusSuggestion() {
    final suggestion = _bestBusSuggestion();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.directions_bus, color: scheme.onTertiaryContainer),
        title: Text(
          suggestion ??
              _t('No single direct route found', 'لا يوجد خط مباشر واحد'),
        ),
        subtitle: Text(
          suggestion == null
              ? _t(
                  'Start the journey and Daleel will search again from where you are.',
                  'ابدأ الرحلة وسيبحث دليل من جديد انطلاقاً من موقعك.',
                )
              : _t(
                  'You will see the walk to the stop, the ride, and the walk at the end.',
                  'سترى المشي إلى المحطة، ثم الركوب، ثم المشي في النهاية.',
                ),
        ),
      ),
    );
  }

  String? _bestBusSuggestion() {
    final stops = _tripStops;
    final origin = _currentLocation;
    if (stops.isEmpty || origin == null) return null;
    final destination = LatLng(stops.last.latitude, stops.last.longitude);
    final plan = _findBestDirectBusPlan(origin, destination);
    if (plan == null) return null;
    return _t(
      'Route ${plan.route.routeNumber}: board at ${plan.boardStop.nameEn}, exit at ${plan.alightStop.nameEn}',
      'خط ${plan.route.routeNumber}: اركب عند ${plan.boardStop.nameAr} وانزل عند ${plan.alightStop.nameAr}',
    );
  }

  Future<void> _pickTripAttraction(StateSetter setSheetState) async {
    final available = _attractions
        .where((item) => !_tripStopIds.contains(item.attractionId))
        .toList();
    final selected = await showDialog<Attraction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Add a stop', 'أضف محطة')),
        content: SizedBox(
          width: 420,
          height: 420,
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (context, index) {
              final item = available[index];
              return ListTile(
                leading: Icon(
                  _iconForCategory(item.categoryId),
                  color: _colorForCategory(item.categoryId),
                ),
                title: Text(_isArabic ? item.nameAr : item.nameEn),
                onTap: () => Navigator.pop(context, item),
              );
            },
          ),
        ),
      ),
    );
    if (selected == null) return;
    setState(() => _tripStopIds.add(selected.attractionId));
    setSheetState(() {});
    _persistState();
    unawaited(_refreshTripRoute().whenComplete(() => setSheetState(() {})));
  }

  void _optimizeTrip(StateSetter setSheetState) {
    final remaining = _tripStops.toList();
    final ordered = <Attraction>[];
    var current =
        _currentLocation ??
        LatLng(remaining.first.latitude, remaining.first.longitude);
    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        return _distance
            .as(LengthUnit.Meter, current, LatLng(a.latitude, a.longitude))
            .compareTo(
              _distance.as(
                LengthUnit.Meter,
                current,
                LatLng(b.latitude, b.longitude),
              ),
            );
      });
      final next = remaining.removeAt(0);
      ordered.add(next);
      current = LatLng(next.latitude, next.longitude);
    }
    setState(() {
      _tripStopIds
        ..clear()
        ..addAll(ordered.map((item) => item.attractionId));
    });
    setSheetState(() {});
    _persistState();
    unawaited(_refreshTripRoute().whenComplete(() => setSheetState(() {})));
  }

  void _saveCurrentTrip(StateSetter setSheetState) {
    final now = DateTime.now();
    final trip = SavedTrip(
      id: now.microsecondsSinceEpoch.toString(),
      name: _t(
        'Al Ain trip ${_savedTrips.length + 1}',
        'رحلة العين ${_savedTrips.length + 1}',
      ),
      attractionIds: List<int>.from(_tripStopIds),
      travelMode: _travelMode.name,
      createdAt: now,
    );
    setState(() => _savedTrips.add(trip));
    setSheetState(() {});
    _persistState();
    _showMessage(_t('Trip saved offline.', 'تم حفظ الرحلة دون اتصال.'));
  }

  Future<void> _showSavedTrips(StateSetter plannerState) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, dialogState) => AlertDialog(
          title: Text(_t('Saved trips', 'الرحلات المحفوظة')),
          content: SizedBox(
            width: 460,
            height: 380,
            child: _savedTrips.isEmpty
                ? Center(
                    child: Text(
                      _t('No saved trips yet.', 'لا توجد رحلات محفوظة.'),
                    ),
                  )
                : ListView.builder(
                    itemCount: _savedTrips.length,
                    itemBuilder: (context, index) {
                      final trip = _savedTrips[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.route, color: terracotta),
                          title: Text(trip.name),
                          subtitle: Text(
                            '${trip.attractionIds.length} ${_t('stops', 'محطات')}',
                          ),
                          onTap: () {
                            setState(() {
                              _tripStopIds
                                ..clear()
                                ..addAll(trip.attractionIds);
                              _travelMode = TravelMode.fromStorage(
                                trip.travelMode,
                              );
                            });
                            plannerState(() {});
                            _persistState();
                            unawaited(
                              _refreshTripRoute().whenComplete(
                                () => plannerState(() {}),
                              ),
                            );
                            Navigator.pop(dialogContext);
                          },
                          trailing: IconButton(
                            tooltip: _t('Delete trip', 'حذف الرحلة'),
                            onPressed: () {
                              setState(() => _savedTrips.removeAt(index));
                              dialogState(() {});
                              plannerState(() {});
                              _persistState();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareTrip() async {
    final buffer = StringBuffer()
      ..writeln(_t('My Al Ain trip', 'رحلتي في العين'))
      ..writeln(
        _t('Mode: ${_travelMode.name}', 'وسيلة التنقل: ${_travelMode.name}'),
      )
      ..writeln(
        '${_tripDistanceKm.toStringAsFixed(1)} km · ~$_tripDurationMinutes min',
      );
    for (var index = 0; index < _tripStops.length; index++) {
      final item = _tripStops[index];
      buffer.writeln('${index + 1}. ${_isArabic ? item.nameAr : item.nameEn}');
    }
    buffer.writeln(
      _t(
        'Times and routes are planning estimates.',
        'الأوقات والمسارات تقديرات للتخطيط.',
      ),
    );
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      _showMessage(
        _t(
          'Trip summary copied. Paste it into any app to share.',
          'تم نسخ ملخص الرحلة. الصقه في أي تطبيق للمشاركة.',
        ),
      );
    }
  }

  static IconData _iconForCategory(int id) => PlaceCategory.icon(id);

  static Color _colorForCategory(int id) => PlaceCategory.color(id);
}

/// Small round badge on a map marker (saved, trip stop number).
class _MarkerBadge extends StatelessWidget {
  const _MarkerBadge({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: parchment, width: 1.5),
    ),
    child: child,
  );
}

/// Map-app style action: a round icon above a short label.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final background = primary
        ? terracotta
        : selected
        ? dune.withValues(alpha: 0.6)
        : sandDeep;
    final foreground = primary ? Colors.white : terracottaDeep;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: foreground),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: darkBrown,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
