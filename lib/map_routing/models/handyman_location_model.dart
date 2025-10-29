/// Model for handyman's location data received from the backend
class HandymanLocationModel {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracy;
  final double? heading;
  final double? speed;

  const HandymanLocationModel({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.heading,
    this.speed,
  });

  factory HandymanLocationModel.fromJson(Map<String, dynamic> json) {
    return HandymanLocationModel(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracy: json['accuracy'] != null ? (json['accuracy'] as num).toDouble() : null,
      heading: json['heading'] != null ? (json['heading'] as num).toDouble() : null,
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      if (accuracy != null) 'accuracy': accuracy,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HandymanLocationModel &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.timestamp == timestamp &&
        other.accuracy == accuracy &&
        other.heading == heading &&
        other.speed == speed;
  }

  @override
  int get hashCode {
    return Object.hash(
      latitude,
      longitude,
      timestamp,
      accuracy,
      heading,
      speed,
    );
  }

  @override
  String toString() {
    return 'HandymanLocationModel(lat: $latitude, lng: $longitude, '
        'timestamp: $timestamp, accuracy: $accuracy, heading: $heading, speed: $speed)';
  }
}

