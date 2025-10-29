import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/route_model.dart';
import '../models/location_model.dart';
import '../utils/constants.dart';
import '../utils/app_exceptions.dart';

/// Service for fetching routes from Google Directions API
class RouteService {
  static const String _directionsEndpoint = 'https://maps.googleapis.com/maps/api/directions/json';
  static const List<String> _validModes = ['driving', 'walking', 'bicycling', 'transit'];
  
  /// Decodes Google polyline encoding algorithm to convert encoded string to LatLng coordinates
  static List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return poly;
  }

  /// Validates location coordinates
  static void _validateLocations(LocationModel origin, LocationModel destination) {
    if (origin.latitude < -90 || origin.latitude > 90 ||
        origin.longitude < -180 || origin.longitude > 180) {
      throw RouteException('Invalid origin coordinates');
    }
    if (destination.latitude < -90 || destination.latitude > 90 ||
        destination.longitude < -180 || destination.longitude > 180) {
      throw RouteException('Invalid destination coordinates');
    }
  }

  /// Builds the API URL with query parameters
  static Uri _buildUrl({
    required LocationModel origin,
    required LocationModel destination,
    required String mode,
    bool alternatives = false,
  }) {
    return Uri.parse(_directionsEndpoint).replace(queryParameters: {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'key': Constants.googleMapsApiKey,
      'mode': mode,
      if (alternatives) 'alternatives': 'true',
    });
  }

  /// Parses a single route from API response data
  static RouteModel _parseRoute(
    Map<String, dynamic> routeData,
    LocationModel origin,
    LocationModel destination,
  ) {
    final leg = routeData['legs'][0];
    final String encodedPolyline = routeData['overview_polyline']['points'];
    final List<LatLng> polylineCoordinates = _decodePolyline(encodedPolyline);
    final distance = (leg['distance']['value'] as num).toDouble();
    final duration = (leg['duration']['value'] as num).toDouble();

    return RouteModel(
      origin: origin,
      destination: destination,
      polylinePoints: polylineCoordinates,
      distanceInMeters: distance,
      durationInSeconds: duration,
    );
  }

  /// Fetches a single route between origin and destination
  /// 
  /// Throws [RouteException] if the route cannot be found or if there's an API error.
  static Future<RouteModel> getRoute({
    required LocationModel origin,
    required LocationModel destination,
    String mode = 'driving',
  }) async {
    _validateLocations(origin, destination);
    
    if (!_validModes.contains(mode)) {
      throw RouteException('Invalid travel mode: $mode. Valid modes: $_validModes');
    }

    try {
      final url = _buildUrl(
        origin: origin,
        destination: destination,
        mode: mode,
      );
      final response = await http.get(url).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw RouteException('Request timeout'),
      );

      if (response.statusCode != 200) {
        throw RouteException(
          'Failed to load route: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status != 'OK') {
        throw RouteException(
          'API error: ${data['error_message'] ?? status ?? 'Unknown error'}',
          statusCode: response.statusCode,
        );
      }

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        throw RouteException('No routes found');
      }

      return _parseRoute(
        routes[0] as Map<String, dynamic>,
        origin,
        destination,
      );
    } on RouteException {
      rethrow;
    } on FormatException catch (e) {
      throw RouteException('Failed to parse API response: ${e.message}', originalError: e);
    } catch (e) {
      throw RouteException('Unexpected error: ${e.toString()}', originalError: e);
    }
  }

  /// Fetches primary and alternative routes (sorted by duration, fastest first)
  /// 
  /// Returns multiple routes if available, sorted by duration in ascending order.
  /// Throws [RouteException] if no routes can be found or if there's an API error.
  static Future<List<RouteModel>> getRoutes({
    required LocationModel origin,
    required LocationModel destination,
    String mode = 'driving',
  }) async {
    _validateLocations(origin, destination);
    
    if (!_validModes.contains(mode)) {
      throw RouteException('Invalid travel mode: $mode. Valid modes: $_validModes');
    }

    try {
      final url = _buildUrl(
        origin: origin,
        destination: destination,
        mode: mode,
        alternatives: true,
      );
      final response = await http.get(url).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw RouteException('Request timeout'),
      );

      if (response.statusCode != 200) {
        throw RouteException(
          'Failed to load routes: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status != 'OK') {
        throw RouteException(
          'API error: ${data['error_message'] ?? status ?? 'Unknown error'}',
          statusCode: response.statusCode,
        );
      }

      final routesData = data['routes'] as List?;
      if (routesData == null || routesData.isEmpty) {
        throw RouteException('No routes found');
      }

      final routes = <RouteModel>[];
      for (final routeData in routesData) {
        routes.add(_parseRoute(
          routeData as Map<String, dynamic>,
          origin,
          destination,
        ));
      }

      // Sort by duration ascending (fastest first)
      routes.sort((a, b) => a.durationInSeconds.compareTo(b.durationInSeconds));
      return routes;
    } on RouteException {
      rethrow;
    } on FormatException catch (e) {
      throw RouteException('Failed to parse API response: ${e.message}', originalError: e);
    } catch (e) {
      throw RouteException('Unexpected error: ${e.toString()}', originalError: e);
    }
  }
}

