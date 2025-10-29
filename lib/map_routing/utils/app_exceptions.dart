/// Custom exception classes for better error handling
class RouteException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  RouteException(this.message, {this.statusCode, this.originalError});

  @override
  String toString() => 'RouteException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

class LocationException implements Exception {
  final String message;
  final dynamic originalError;

  LocationException(this.message, {this.originalError});

  @override
  String toString() => 'LocationException: $message';
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final dynamic responseData;

  ApiException(this.message, this.statusCode, {this.responseData});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

