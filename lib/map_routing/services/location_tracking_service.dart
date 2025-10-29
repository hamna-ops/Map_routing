import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/app_exceptions.dart';
import '../utils/config.dart';

/// Service for Handyman app: Sends location updates to backend
class LocationTrackingService {
  StreamSubscription<Position>? _positionStream;
  String? _bookingId;
  String? _handymanId;
  Timer? _updateTimer;
  bool _isTracking = false;
  
  /// Checks if tracking is currently active
  bool get isTracking => _isTracking;
  
  /// Start tracking and sending location updates for a handyman
  /// 
  /// [bookingId] - The booking/order ID
  /// [handymanId] - The handyman's user ID
  /// [distanceFilter] - Minimum distance in meters before sending update (default: 8 meters)
  /// 
  /// Throws [LocationException] if location services are disabled or permissions denied
  Future<void> startTracking({
    required String bookingId,
    required String handymanId,
    double distanceFilter = 8.0,
  }) async {
    if (bookingId.isEmpty || handymanId.isEmpty) {
      throw LocationException('Booking ID and Handyman ID cannot be empty');
    }

    if (_isTracking) {
      throw LocationException('Tracking is already active. Call stopTracking() first.');
    }
    
    _bookingId = bookingId;
    _handymanId = handymanId;
    
    // Check location permissions
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException('Location services are disabled. Please enable location services in settings.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException('Location permissions are denied. Please enable location permissions.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
        'Location permissions are permanently denied. Please enable them in app settings.',
      );
    }

    _isTracking = true;

    // Listen to position changes
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    ).listen(
      (Position position) async {
        await _sendLocationUpdate(position);
      },
      onError: (error) {
        // Silently handle position stream errors - they can happen due to GPS issues
        // but we don't want to crash the app
        _isTracking = false;
      },
    );
  }

  /// Sends location update to backend
  Future<void> _sendLocationUpdate(Position position) async {
    if (_bookingId == null || _handymanId == null || !_isTracking) {
      return;
    }

    try {
      final url = Uri.parse('${Config.backendBaseUrl}/location/update');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (Config.apiToken != null) 'Authorization': 'Bearer ${Config.apiToken}',
        },
        body: json.encode({
          'bookingId': _bookingId,
          'handymanId': _handymanId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': DateTime.now().toIso8601String(),
          'accuracy': position.accuracy,
          'heading': position.heading,
          'speed': position.speed,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw ApiException('Request timeout', 408),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw ApiException(
          'Failed to update location',
          response.statusCode,
          responseData: response.body,
        );
      }
    } on ApiException {
      // Silently fail location updates - don't crash the app
      // In production, you might want to implement retry logic or offline queue
      rethrow;
    } catch (e) {
      // Log but don't crash - location updates failing shouldn't break tracking
      throw LocationException('Error sending location update: ${e.toString()}', originalError: e);
    }
  }

  /// Stop tracking and sending location updates
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _updateTimer?.cancel();
    _updateTimer = null;
    _bookingId = null;
    _handymanId = null;
    _isTracking = false;
  }

  /// Manually send current location (useful for periodic updates or testing)
  /// 
  /// Throws [LocationException] if location cannot be obtained
  Future<void> sendCurrentLocation() async {
    if (_bookingId == null || _handymanId == null) {
      throw LocationException('Tracking not started. Call startTracking() first.');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw LocationException('Timeout getting current location'),
      );
      await _sendLocationUpdate(position);
    } on LocationException {
      rethrow;
    } catch (e) {
      throw LocationException('Error getting current location: ${e.toString()}', originalError: e);
    }
  }

  /// Dispose of resources
  void dispose() {
    stopTracking();
  }
}

