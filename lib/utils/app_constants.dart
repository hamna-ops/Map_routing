/// Application-wide constants
class AppConstants {
  // Route calculation
  static const double destinationThresholdMeters = 50.0;
  static const double handymanCameraUpdateThresholdMeters = 100.0;
  static const int routeRequestTimeoutSeconds = 30;
  static const int locationRequestTimeoutSeconds = 10;
  
  // Location polling
  static const int locationPollingIntervalSeconds = 10;
  static const double locationTrackingDistanceFilterMeters = 8.0;
  
  // Timeline
  static const int ongoingTimerDelaySeconds = 3;
  
  // Map
  static const double defaultZoomLevel = 14.0;
  static const double mapBoundsPadding = 0.005;
  static const double cameraPadding = 100.0;
  
  // Simulation
  static const int simulationUpdateIntervalSeconds = 2;
  static const double simulationMoveDistanceMeters = 80.0;
  
  // UI
  static const double designWidth = 375.0;
  static const double designHeight = 812.0;
  
  // Colors
  static const int primaryColorValue = 0xFF0A2A66;
  static const int routePolylineColorValue = 0xFF9C27B0; // Purple
  
  // Private constructor to prevent instantiation
  AppConstants._();
}

