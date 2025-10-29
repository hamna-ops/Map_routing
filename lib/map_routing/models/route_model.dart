import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'location_model.dart';

/// Model representing a route between two locations
class RouteModel {
  final LocationModel origin;
  final LocationModel destination;
  final List<LatLng> polylinePoints;
  final double distanceInMeters;
  final double durationInSeconds;

  const RouteModel({
    required this.origin,
    required this.destination,
    required this.polylinePoints,
    required this.distanceInMeters,
    required this.durationInSeconds,
  });

  /// Get distance formatted as kilometers
  double get distanceInKilometers => distanceInMeters / 1000.0;

  /// Get duration formatted as minutes
  double get durationInMinutes => durationInSeconds / 60.0;

  /// Get duration formatted as hours
  double get durationInHours => durationInSeconds / 3600.0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RouteModel &&
        other.origin == origin &&
        other.destination == destination &&
        other.distanceInMeters == distanceInMeters &&
        other.durationInSeconds == durationInSeconds &&
        other.polylinePoints.length == polylinePoints.length;
  }

  @override
  int get hashCode {
    return Object.hash(
      origin,
      destination,
      distanceInMeters,
      durationInSeconds,
      polylinePoints.length,
    );
  }

  @override
  String toString() {
    return 'RouteModel(origin: $origin, destination: $destination, '
        'distance: ${distanceInKilometers.toStringAsFixed(2)}km, '
        'duration: ${durationInMinutes.toStringAsFixed(1)}min)';
  }
}

