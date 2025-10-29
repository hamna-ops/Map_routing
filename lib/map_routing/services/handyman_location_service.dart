import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/handyman_location_model.dart';
import '../utils/app_exceptions.dart';
import '../utils/config.dart';

/// Service for Customer app: Fetches handyman's current location from backend
class HandymanLocationService {
  /// Fetches handyman's current location for a booking
  /// 
  /// [bookingId] - The booking/order ID
  /// Returns the handyman's current position or null if not available (404)
  /// Throws [ApiException] for other HTTP errors
  Future<HandymanLocationModel?> getHandymanLocation(String bookingId) async {
    if (bookingId.isEmpty) {
      throw LocationException('Booking ID cannot be empty');
    }

    try {
      final url = Uri.parse('${Config.backendBaseUrl}/location/handyman/$bookingId');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (Config.apiToken != null) 'Authorization': 'Bearer ${Config.apiToken}',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw ApiException('Request timeout', 408),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return HandymanLocationModel.fromJson(data);
      } else if (response.statusCode == 404) {
        // Handyman location not available yet - this is expected
        return null;
      } else {
        throw ApiException(
          'Failed to get handyman location',
          response.statusCode,
          responseData: response.body,
        );
      }
    } on ApiException {
      rethrow;
    } on FormatException catch (e) {
      throw LocationException('Failed to parse location response: ${e.message}', originalError: e);
    } catch (e) {
      throw LocationException('Unexpected error fetching handyman location: ${e.toString()}', originalError: e);
    }
  }
}

