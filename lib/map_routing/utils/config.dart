/// Configuration for the application
/// 
/// IMPORTANT: For production, move API keys to environment variables or secure storage
/// This file should not be committed to version control with real API keys
class Config {
  /// Google Maps API Key
  /// TODO: Move to environment variable for production
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyDARKwJ-VM6gpR1Qd4DfX1Qc8uttsmhxDA', // TODO: Replace with your key
  );

  /// Backend API base URL
  /// TODO: Replace with your actual backend URL
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://your-backend-api.com/api',
  );

  /// API token for authentication (if needed)
  /// TODO: Load from secure storage in production
  static const String? apiToken = String.fromEnvironment(
    'API_TOKEN',
    defaultValue: null,
  );

  /// Enable/disable location polling for development
  static const bool enableLocationPolling = true;
}

