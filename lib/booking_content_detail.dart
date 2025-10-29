import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'map_routing/services/route_service.dart';
import 'map_routing/services/location_tracking_service.dart';
import 'map_routing/services/handyman_location_service.dart';
import 'map_routing/models/location_model.dart';
import 'map_routing/models/route_model.dart';
import 'map_routing/models/handyman_location_model.dart';
import 'map_routing/utils/config.dart';
import 'map_routing/utils/app_exceptions.dart';
import 'utils/app_constants.dart';

class BookingContentDetail extends StatefulWidget {
  final Map<String, dynamic> booking;

  const BookingContentDetail({
    super.key,
    required this.booking,
  });

  @override
  State<BookingContentDetail> createState() => _BookingContentDetailState();
}

class _BookingContentDetailState extends State<BookingContentDetail> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  RouteModel? _route;
  bool _isLoadingRoute = false;

  // Start and destination coordinates
  // Waxon Consultants, Johar Town, Lahore
  static const double _startLat = 31.472587095494305;
  static const double _startLng = 74.2717197265554;
  // Emporium Mall, Lahore
  static const double _destLat = 31.4670;
  static const double _destLng = 74.2660;

  // Handyman tracking path for live polyline
  List<LatLng> _handymanPath = [];
  Timer? _simulationTimer;
  int _currentRoutePointIndex = 0; // Track current position on route
  double _progressAlongSegment = 0.0; // Progress between current and next route point (0.0 to 1.0)

  // Timeline indicator state
  double _indicatorPosition = 0.0; // Starts at position 0 (Start)
  bool _startTicked = false;
  bool _arrivedTicked = false;
  bool _ongoingTicked = false;
  bool _finishedHighlighted = false; // Finished highlighted but not ticked
  bool _finishedTicked = false; // Tick only when Finish is pressed
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  
  // Handyman location tracking
  final HandymanLocationService _handymanLocationService = HandymanLocationService();
  HandymanLocationModel? _handymanLocation;
  Timer? _locationPollTimer;
  Timer? _ongoingTimer; // Timer to check On-going after 10 seconds of arrival

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _locationPollTimer?.cancel();
    _simulationTimer?.cancel();
    _ongoingTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    // Add start and destination markers
    _addMarkers();
    
    // Calculate route
    await _calculateRoute();
    
    // Start location tracking (for checking if user reached destination)
    _startLocationTracking();
    
    // Start polling for handyman's location (for customer app)
    _startHandymanLocationPolling();
    
    // Note: Simulation will start after route is calculated
    
    // Position camera to show both markers (with delay to ensure map is ready)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _positionCamera();
      }
    });
  }

  /// Simulate handyman movement for live tracking polyline
  void _startHandymanPathSimulation() {
    // Wait for route to be available
    if (_route == null || _route!.polylinePoints.isEmpty) {
      return;
    }
    
    final routePoints = _route!.polylinePoints;
    
    // Start from the first route point (or closest to start)
    _handymanPath = [routePoints.first];
    _currentRoutePointIndex = 0;
    _progressAlongSegment = 0.0;
    _startTicked = true; // Mark start as ticked when movement begins
    
    // Simulate movement every 2 seconds (faster updates for smoother movement)
    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _route == null || routePoints.isEmpty) {
        timer.cancel();
        return;
      }
        
      // Check if we've reached the destination
      if (_currentRoutePointIndex >= routePoints.length - 1) {
        timer.cancel();
        // Set final position to destination if not already there
        final destPoint = routePoints.last;
        if (_handymanPath.isEmpty || 
            _handymanPath.last.latitude != destPoint.latitude ||
            _handymanPath.last.longitude != destPoint.longitude) {
          setState(() {
            _handymanPath.add(destPoint);
            _updateHandymanTrackingPolyline();
            _handymanLocation = HandymanLocationModel(
              latitude: destPoint.latitude,
              longitude: destPoint.longitude,
              timestamp: DateTime.now(),
            );
            _updateHandymanMarker(_handymanLocation!);
          });
        }
        return;
      }
      
      // Get current and next route points (staying on the route)
      final currentPoint = routePoints[_currentRoutePointIndex];
      final nextPoint = routePoints[_currentRoutePointIndex + 1];
      
      // Move along the segment between current and next route point
      // Each update moves about 50-100 meters along the road
      final segmentDistance = Geolocator.distanceBetween(
        currentPoint.latitude,
        currentPoint.longitude,
        nextPoint.latitude,
        nextPoint.longitude,
      );
      
      // How much to progress along this segment (about 80 meters per update)
      final moveDistance = 80.0; // meters
      final progressIncrement = (segmentDistance > 0) ? (moveDistance / segmentDistance) : 1.0;
      
      _progressAlongSegment += progressIncrement;
      
      LatLng newPoint;
      
      if (_progressAlongSegment >= 1.0) {
        // Move to next route point and continue along next segment
        _progressAlongSegment = _progressAlongSegment - 1.0;
        _currentRoutePointIndex++;
        
        // If we have more points, interpolate along next segment
        if (_currentRoutePointIndex < routePoints.length - 1) {
          final newCurrent = routePoints[_currentRoutePointIndex];
          final newNext = routePoints[_currentRoutePointIndex + 1];
          
          // Interpolate along the new segment
          newPoint = _interpolateBetweenPoints(newCurrent, newNext, _progressAlongSegment);
        } else {
          // Reached the end, use last point
          newPoint = routePoints.last;
        }
      } else {
        // Still on current segment, interpolate
        newPoint = _interpolateBetweenPoints(currentPoint, nextPoint, _progressAlongSegment);
      }
      
      setState(() {
        _handymanPath.add(newPoint);
        _updateHandymanTrackingPolyline();
        
        // Also update the marker
        _handymanLocation = HandymanLocationModel(
          latitude: newPoint.latitude,
          longitude: newPoint.longitude,
          timestamp: DateTime.now(),
        );
        _updateHandymanMarker(_handymanLocation!);
        
        // Update timeline based on route progress
        _updateTimelineProgress(newPoint);
        
        // Check if handyman reached destination
        _checkHandymanDestinationReached(_handymanLocation!);
      });
    });
  }
  
  /// Interpolate a point between two route points (staying on the road)
  LatLng _interpolateBetweenPoints(LatLng start, LatLng end, double progress) {
    // Clamp progress between 0 and 1
    progress = progress.clamp(0.0, 1.0);
    
    if (progress >= 1.0) return end;
    if (progress <= 0.0) return start;
    
    // Linear interpolation along the route segment (stays on the road)
    final lat = start.latitude + (end.latitude - start.latitude) * progress;
    final lng = start.longitude + (end.longitude - start.longitude) * progress;
    
    return LatLng(lat, lng);
  }

  /// Update the polyline showing handyman's traveled path
  void _updateHandymanTrackingPolyline() {
    if (_handymanPath.length < 2) return;
    
    // Remove old tracking polyline
    _polylines.removeWhere((poly) => poly.polylineId.value == 'handyman_tracking');
    
    // Add new tracking polyline
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('handyman_tracking'),
        points: _handymanPath,
        color: Colors.blue, // Blue color for live tracking
        width: 4,
        geodesic: true,
        patterns: [],
      ),
    );
  }

  /// Start polling for handyman's live location updates
  void _startHandymanLocationPolling() {
    // Check if location polling is enabled in config
    // This can be disabled until backend is ready
    if (!Config.enableLocationPolling) {
      return;
    }
    
    // Poll every 10 seconds for handyman's location
    _locationPollTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      // Get booking ID from widget.booking
      final bookingId = widget.booking['id']?.toString() ?? 
                        widget.booking['bookingId']?.toString() ?? 
                        'default_booking_id';
      
      final location = await _handymanLocationService.getHandymanLocation(bookingId);
      
      if (mounted) {
        setState(() {
          if (location != null) {
            final oldLocation = _handymanLocation;
            _handymanLocation = location;
            
            // Update handyman marker on map
            _updateHandymanMarker(location);
            
            // Check if handyman reached destination and update timeline
            _checkHandymanDestinationReached(location);
            
            // If location changed significantly, update camera
            if (oldLocation == null || 
                _calculateDistance(
                  oldLocation.latitude, 
                  oldLocation.longitude,
                  location.latitude,
                  location.longitude,
                ) > 100) { // More than 100 meters
              _updateCameraForHandyman(location);
            }
          }
        });
      }
    });
    
    // Also fetch immediately
    _fetchHandymanLocation();
  }

  /// Fetch handyman's location once
  Future<void> _fetchHandymanLocation() async {
    final bookingId = widget.booking['id']?.toString() ?? 
                      widget.booking['bookingId']?.toString() ?? 
                      'default_booking_id';
    
    final location = await _handymanLocationService.getHandymanLocation(bookingId);
    
    if (mounted && location != null) {
      setState(() {
        _handymanLocation = location;
        _updateHandymanMarker(location);
      });
    }
  }

  /// Update handyman marker on the map
  void _updateHandymanMarker(HandymanLocationModel location) {
    setState(() {
      // Remove old handyman marker if exists
      _markers.removeWhere((marker) => marker.markerId.value == 'handyman');
      
      // Add new handyman marker
      _markers.add(
        Marker(
          markerId: const MarkerId('handyman'),
          position: LatLng(location.latitude, location.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: 'Handyman Location',
            snippet: 'Last updated: ${_formatTime(location.timestamp)}',
          ),
        ),
      );
    });
  }

  /// Update camera to follow handyman's location
  void _updateCameraForHandyman(HandymanLocationModel location) {
    if (_mapController != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(location.latitude, location.longitude),
        ),
      );
    }
  }

  /// Calculate distance between two coordinates in meters
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// Format timestamp for display
  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    // Listen to position changes
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _checkDestinationReached(position);
        });
      }
    });
  }

  void _checkDestinationReached(Position position) {
    // Calculate distance to destination
    double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _destLat,
      _destLng,
    );

    // If within 50 meters of destination, tick Arrived and set timer for On-going
    if (distance <= 50) {
      if (!_arrivedTicked) {
        setState(() {
          _arrivedTicked = true;
          _indicatorPosition = 1.0; // Move to Arrived position
        });
        
        // Start 10 second timer to check On-going
        _ongoingTimer?.cancel();
        _ongoingTimer = Timer(const Duration(seconds: 10), () {
          if (mounted && !_ongoingTicked) {
            setState(() {
              _ongoingTicked = true;
              _indicatorPosition = 2.0; // Move to On-going position
            });
          }
        });
      }
    }
  }

  /// Update timeline progress based on handyman's position along the route
  void _updateTimelineProgress(LatLng currentPosition) {
    // Don't update indicator position automatically based on route progress
    // Only update when specific steps are reached (arrived, ongoing, etc.)
    // This prevents the line from turning blue before steps are checked
  }

  /// Check if handyman reached destination based on tracked location
  void _checkHandymanDestinationReached(HandymanLocationModel location) {
    // Calculate distance to destination
    double distance = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      _destLat,
      _destLng,
    );

    // If within 50 meters of destination, tick Arrived and set timer for On-going
    if (distance <= 50) {
      if (!_arrivedTicked) {
        setState(() {
          _arrivedTicked = true;
          _indicatorPosition = 1.0; // Move to Arrived position
        });
        
        // Start 10 second timer to check On-going
        _ongoingTimer?.cancel();
        _ongoingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && !_ongoingTicked) {
            setState(() {
              _ongoingTicked = true;
              _indicatorPosition = 2.0; // Move to On-going position
            });
          }
        });
      }
    }
  }

  void _addMarkers() {
    setState(() {
      _markers.clear();
      
          // Start marker
      _markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: const LatLng(_startLat, _startLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: 'Start Location',
            snippet: 'Waxon Consultants, Johar Town',
          ),
        ),
      );
      
      // Destination marker
      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: const LatLng(_destLat, _destLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(
            title: 'Destination',
            snippet: 'Emporium Mall',
          ),
        ),
      );
    });
  }

  Future<void> _calculateRoute() async {
    setState(() {
      _isLoadingRoute = true;
    });

    try {
      final startLocation = const LocationModel(
        latitude: _startLat,
        longitude: _startLng,
      );
      final destLocation = const LocationModel(
        latitude: _destLat,
        longitude: _destLng,
      );

      final routes = await RouteService.getRoutes(
        origin: startLocation,
        destination: destLocation,
      );

      if (routes.isNotEmpty && mounted) {
        setState(() {
          _route = routes.first;
          // Remove only route polyline, keep tracking polyline
          _polylines.removeWhere((poly) => poly.polylineId.value == 'route');
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: _route!.polylinePoints,
              color: const Color(AppConstants.routePolylineColorValue),
              width: 4,
              geodesic: true,
            ),
          );
          // Update tracking polyline if exists
          if (_handymanPath.isNotEmpty) {
            _updateHandymanTrackingPolyline();
          }
          // Start simulation after route is calculated
          _startHandymanPathSimulation();
          _isLoadingRoute = false;
        });
      } else {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    } on RouteException catch (e) {
      // Route calculation failed - could show error message to user
      // For now, silently handle by setting loading to false
      setState(() {
        _isLoadingRoute = false;
      });
    } catch (e) {
      // Unexpected error
      setState(() {
        _isLoadingRoute = false;
      });
    }
  }

  void _positionCamera() {
    if (_mapController != null && _markers.length >= 2) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          _startLat < _destLat ? _startLat - 0.005 : _destLat - 0.005,
          _startLng < _destLng ? _startLng - 0.005 : _destLng - 0.005,
        ),
        northeast: LatLng(
          _startLat > _destLat ? _startLat + 0.005 : _destLat + 0.005,
          _startLng > _destLng ? _startLng + 0.005 : _destLng + 0.005,
        ),
      );
      
      Future.delayed(const Duration(milliseconds: 300), () {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100.0),
        );
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _positionCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Map Area (Top 60% of screen)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.6,
            child: _buildMapArea(),
          ),
          
          // Bottom Sheet Content (Bottom 50% of screen)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            top: MediaQuery.of(context).size.height * 0.4,
            child: _buildBottomSheet(context),
          ),
          
          // Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16.h,
            left: 16.w,
            child: GestureDetector(
              onTap: () {
                try {
                  Navigator.of(context).pop();
                } catch (e) {
                  // Fallback navigation if pop fails
                  Navigator.of(context).maybePop();
                }
              },
              child: Container(
                width: 50.w,
                height: 50.h,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2A66).withOpacity(0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.arrow_back,
                  color: const Color(0xFF0A2A66),
                  size: 20.sp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapArea() {
    // Calculate center point between start and destination
    final centerLat = (_startLat + _destLat) / 2;
    final centerLng = (_startLng + _destLng) / 2;

    return GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: LatLng(centerLat, centerLng),
        zoom: 14.0,
      ),
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      mapType: MapType.normal,
      zoomControlsEnabled: false,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      tiltGesturesEnabled: true,
      rotateGesturesEnabled: true,
      minMaxZoomPreference: const MinMaxZoomPreference(5.0, 20.0),
      cameraTargetBounds: CameraTargetBounds.unbounded,
    );
  }

  Widget _buildBottomSheet(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.r),
          topRight: Radius.circular(20.r),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressTracker(context),
            SizedBox(height: 20.h),
            _buildBookingDetails(),
            SizedBox(height: 20.h),
            _buildServiceProviderProfile(),
            SizedBox(height: 20.h),
            _buildActionButtons(),
            SizedBox(height: 20.h),
            _buildFinishButton(context),
            SizedBox(height: 40.h), // Extra padding at bottom for better scrolling
          ],
        ),
      ),
    );
  }

  // Active step based on indicator position
  int get activeStep {
    if (_indicatorPosition < 1) return 0; // Start
    if (_indicatorPosition < 2) return 1; // Arrived
    if (_indicatorPosition < 3) return 2; // On-going
    return 3; // Finished
  }

  Widget _buildProgressTracker(BuildContext context) {
    // Detect tablet/iPad using screen width
    bool isTablet = MediaQuery.of(context).size.width >= 768;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        // The dynamic line: solid for completed steps, dotted for future steps
        Positioned(
          top: isTablet ? 50.h : 35.h, // Move further down for tablet/iPad
          left: 20.w,
          right: 20.w,
          child: LayoutBuilder(
            builder: (context, constraints) {
              double totalWidth = constraints.maxWidth;
              double segmentWidth = totalWidth / 3;

              return Row(
                children: [
                  // Solid line for completed steps
                  Container(
                    width: ((activeStep - 0.2) * segmentWidth).clamp(0.0, totalWidth),
                    height: isTablet ? 3.h : 2.h, // Thicker line for tablet/iPad
                    color: const Color(0xFF0A2A66),
                  ),
                  // Remaining dotted line
                  Expanded(
                    child: CustomPaint(
                      key: const ValueKey('dotted_line'),
                      painter: DottedLinePainter(isTablet: isTablet),
                      size: Size.fromHeight(isTablet ? 3.h : 2.h),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Row of progress columns, placed on top of the line
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildProgressColumn('Start', activeStep >= 0, _startTicked),
            _buildProgressColumn('Arrived', activeStep >= 1, _arrivedTicked),
            _buildProgressColumn('On-going', activeStep >= 2, _ongoingTicked),
            _buildProgressColumn('Finished', activeStep >= 3, _finishedTicked, _finishedHighlighted),
          ],
        ),
        // Draggable indicator on the timeline
        Positioned(
          top: isTablet ? 50.h : 35.h,
          left: 20.w,
          right: 20.w,
          child: LayoutBuilder(
            builder: (context, constraints) {
              double totalWidth = constraints.maxWidth;
              // Calculate position based on indicator position (0-3)
              double normalizedPos = _indicatorPosition.clamp(0.0, 3.0);
              double indicatorX = (normalizedPos / 3.0) * totalWidth;

              return GestureDetector(
                onPanStart: (DragStartDetails details) {
                  // Tick "Start" as soon as user starts dragging the indicator
                  if (!_startTicked) {
                    setState(() {
                      _startTicked = true;
                    });
                  }
                },
                onPanUpdate: (DragUpdateDetails details) {
                  double newX = details.localPosition.dx;
                  double clampedX = newX.clamp(0.0, totalWidth);
                  double normalizedPos = (clampedX / totalWidth) * 3.0;
                  
                  setState(() {
                    _indicatorPosition = normalizedPos;
                  });
                },
                onPanEnd: (DragEndDetails details) {
                  // Snap to nearest step position but keep it at least 0
                  double snappedPos = _indicatorPosition.roundToDouble().clamp(0.0, 3.0);
                  setState(() {
                    _indicatorPosition = snappedPos;
                  });
                },
                child: Stack(
                  children: [
                    // Invisible hit area for the entire line
                    Container(
                      height: 40.h,
                      width: totalWidth,
                      color: Colors.transparent,
                    ),
                    // Visible draggable indicator
                    Positioned(
                      left: indicatorX - 12.w,
                      top: (40.h - 24.w) / 2,
                      child: Container(
                        width: 24.w,
                        height: 24.w,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.drag_handle,
                          color: Colors.transparent,
                          size: 12.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCircle(bool isActive, bool isCompleted, [bool isHighlighted = false]) {
    // Use standard color scheme - dark blue when active/highlighted, white otherwise
    return Container(
      width: 20.w,
      height: 20.w,
      decoration: BoxDecoration(
        color: isActive || isHighlighted ? const Color(0xFF0A2A66) : Colors.white,
        shape: BoxShape.circle,
        border: (isActive || isHighlighted) ? null : Border.all(color: Colors.grey[300]!, width: 2),
      ),
      child: isCompleted
          ? Icon(
              Icons.check,
              color: Colors.white,
              size: 12.sp,
            )
          : null,
    );
  }

  Widget _buildProgressLabel(String title, bool isActive) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16.sp,
        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        color: isActive ? const Color(0xFF0A2A66) : Colors.black,
      ),
    );
  }

  Widget _buildProgressColumn(String title, bool isActive, bool isCompleted, [bool isHighlighted = false]) {
    return Column(
      children: [
        _buildProgressLabel(title, isActive || isHighlighted),
        SizedBox(height: 4.h),
        _buildProgressCircle(isActive || isHighlighted, isCompleted, isHighlighted),
      ],
    );
  }

  Widget _buildBookingDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // First destination
        Row(
          children: [
            Expanded(
              child: Text(
                'Waxon Consultants, Johar Town',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0A2A66),
                ),
              ),
            ),
            Text(
              '16:00 PM',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        
        SizedBox(height: 16.h),
        
        // Vertical line connecting the two addresses
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vertical line with car icon
            Column(
              children: [
                // Solid line (top portion)
                Container(
                  width: 2.w,
                  height: 80.h,
                  color: Colors.blue[400],
                ),
                // Car icon at transition point
                Container(
                  width: 16.w,
                  height: 16.w,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A2A66),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: 10.sp,
                  ),
                ),
                // Dotted line (bottom portion)
                Container(
                  width: 2.w,
                  height: 80.h,
                  child: CustomPaint(
                    key: const ValueKey('vertical_dotted_line'),
                    painter: VerticalDottedLinePainter(),
                    size: Size(2.w, 80.h),
                  ),
                ),
              ],
            ),
            SizedBox(width: 12.w),
            // Progress info next to line
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info next to solid line (top)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '4Km',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: const Color(0xFF0A2A66),
                      ),
                    ),
                    Text(
                      '24mints',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: const Color(0xFF0A2A66),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 80.h), // Space to align with dotted line
                // Info next to dotted line (bottom)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2Km Left',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: const Color(0xFF0A2A66),
                      ),
                    ),
                    Text(
                      '12 mints',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: const Color(0xFF0A2A66),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        
        SizedBox(height: 16.h),
        
        // Second destination
        Row(
          children: [
            Expanded(
              child: Text(
                'Emporium Mall',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0A2A66),
                ),
              ),
            ),
            Text(
              '16:24 PM',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceProviderProfile() {
    return Row(
      children: [
        // Profile image
        Container(
          width: 58.w,
          height: 58.h,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: AssetImage('assets/images/image-profile.png'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        SizedBox(width: 12.w),
        
        // Provider details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'John Michael',
                    style: TextStyle(
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0A2A66),
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(
                    Icons.verified,
                    color: Colors.amber,
                    size: 16.sp,
                  ),
                ],
              ),
              SizedBox(height: 2.h),
              Text(
                'Carpenter',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        
        // Rating and price
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Icon(
                  Icons.star,
                  color: Colors.amber,
                  size: 16.sp,
                ),
                SizedBox(width: 4.w),
                Text(
                  '4.9',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 2.h),
            Text(
              '\$25/hr',
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildActionButton(
          icon: Icons.favorite,
          color: Colors.red,
          onTap: () {},
        ),
        SizedBox(width: 12.w),
        _buildActionButton(
          icon: Icons.headphones,
          color: const Color(0xFF0A2A66),
          onTap: () {},
        ),
        SizedBox(width: 12.w),
        _buildActionButton(
          icon: Icons.message,
          label: 'Message',
          color: const Color(0xFF0A2A66),
          onTap: () {},
          isCompact: true,
        ),
        SizedBox(width: 12.w),
        _buildActionButton(
          icon: Icons.phone,
          label: 'Call',
          color: const Color(0xFF0A2A66),
          onTap: () {},
          isCompact: true,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    String? label,
    required VoidCallback onTap,
    bool isCompact = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12.w : (label != null ? 16.w : 12.w),
          vertical: 12.h,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 18.sp,
            ),
            if (label != null) ...[
              SizedBox(width: isCompact ? 4.w : 8.w),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinishButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            _finishedTicked = true;
            if (_indicatorPosition < 3.0) _indicatorPosition = 3.0;
          });
          // Optionally navigate back after ticking finished
          Navigator.of(context).pop();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0A2A66),
          padding: EdgeInsets.symmetric(vertical: 16.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          elevation: 2,
        ),
        child: Text(
          'Finish',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

}


class DottedLinePainter extends CustomPainter {
  final bool isTablet;
  
  const DottedLinePainter({this.isTablet = false});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = isTablet ? 2.0 : 1.0 // Thicker stroke for tablet/iPad
      ..style = PaintingStyle.stroke;

    final double dashWidth = isTablet ? 8.0 : 5.0; // Larger dashes for tablet/iPad
    final double dashSpace = isTablet ? 4.0 : 3.0; // More space for tablet/iPad
    double startX = 0.0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}


class VerticalDottedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const double dashHeight = 4.0;
    const double dashSpace = 3.0;
    double startY = 0.0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}