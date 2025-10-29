/// Model representing a geographic location
class LocationModel {
  final double latitude;
  final double longitude;
  final String? address;

  const LocationModel({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  /// Validates that coordinates are within valid ranges
  bool get isValid {
    return latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
  }

  LocationModel copyWith({
    double? latitude,
    double? longitude,
    String? address,
  }) {
    return LocationModel(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationModel &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.address == address;
  }

  @override
  int get hashCode {
    return Object.hash(latitude, longitude, address);
  }

  @override
  String toString() {
    if (address != null && address!.isNotEmpty) {
      return 'LocationModel($address, lat: $latitude, lng: $longitude)';
    }
    return 'LocationModel(lat: $latitude, lng: $longitude)';
  }
}

