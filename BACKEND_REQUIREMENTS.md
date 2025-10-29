# Backend Requirements for Live Handyman Tracking

## Overview
To implement live tracking of handyman location, you need a backend server that:
1. Receives location updates from the handyman's app
2. Stores/updates the handyman's current location
3. Provides an API endpoint for customers to fetch the handyman's location

## API Endpoints Required

### 1. Update Handyman Location (POST)
**Endpoint:** `POST /api/location/update`

**Request Body:**
```json
{
  "bookingId": "booking_123",
  "handymanId": "handyman_456",
  "latitude": 31.472587,
  "longitude": 74.271719,
  "timestamp": "2024-01-15T10:30:00Z",
  "accuracy": 10.5,
  "heading": 45.0,
  "speed": 15.2
}
```

**Response:**
```json
{
  "success": true,
  "message": "Location updated successfully"
}
```

**Status Codes:**
- `200` or `201`: Success
- `400`: Bad Request
- `401`: Unauthorized
- `500`: Server Error

### 2. Get Handyman Location (GET)
**Endpoint:** `GET /api/location/handyman/{bookingId}`

**Response:**
```json
{
  "latitude": 31.472587,
  "longitude": 74.271719,
  "timestamp": "2024-01-15T10:30:00Z",
  "accuracy": 10.5,
  "heading": 45.0,
  "speed": 15.2
}
```

**Status Codes:**
- `200`: Success (location found)
- `404`: Location not found (handyman hasn't started tracking yet)
- `401`: Unauthorized
- `500`: Server Error

## Database Schema Example

### Location Updates Table
```sql
CREATE TABLE handyman_locations (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  booking_id VARCHAR(255) NOT NULL,
  handyman_id VARCHAR(255) NOT NULL,
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  accuracy DECIMAL(10, 2),
  heading DECIMAL(6, 2),
  speed DECIMAL(10, 2),
  timestamp TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_booking (booking_id),
  INDEX idx_handyman (handyman_id),
  INDEX idx_timestamp (timestamp)
);
```

### Alternative: Use Redis/Cache
For faster updates, you can store the latest location in Redis:
```
Key: handyman_location:{bookingId}
Value: {
  "latitude": 31.472587,
  "longitude": 74.271719,
  "timestamp": "2024-01-15T10:30:00Z",
  ...
}
TTL: 5 minutes (auto-expire if no updates)
```

## Implementation Options

### Option 1: REST API with Polling (Current Implementation)
- **Handyman App:** Sends location updates every 10-15 seconds
- **Customer App:** Polls the API every 10 seconds
- **Pros:** Simple, works with any backend
- **Cons:** Slightly higher battery/network usage, slight delay

### Option 2: WebSocket (Real-time)
- **Handyman App:** Sends location via WebSocket
- **Customer App:** Receives updates via WebSocket push
- **Pros:** Real-time, efficient, lower battery usage
- **Cons:** More complex, requires WebSocket server

### Option 3: Server-Sent Events (SSE)
- **Handyman App:** Sends location via REST API
- **Customer App:** Receives updates via SSE stream
- **Pros:** Real-time, simpler than WebSocket
- **Cons:** One-way only, requires SSE support

## Security Considerations

1. **Authentication:**
   - Add JWT token or API key to headers
   - Verify handyman has permission to update location for that booking
   - Verify customer has permission to view handyman location

2. **Rate Limiting:**
   - Limit location updates to max 1 update per second per handyman
   - Prevent API abuse

3. **Data Privacy:**
   - Only allow location access for active bookings
   - Auto-delete location data after booking completion (GDPR compliance)

## Testing

Update the `_baseUrl` in `location_tracking_service.dart`:
```dart
static const String _baseUrl = 'https://your-backend-api.com/api';
```

Replace with your actual backend URL.

## Usage in Flutter App

### For Handyman App:
```dart
final trackingService = LocationTrackingService();
await trackingService.startTracking(
  bookingId: 'booking_123',
  handymanId: 'handyman_456',
  updateInterval: Duration(seconds: 15),
);

// Stop tracking when job is complete
trackingService.stopTracking();
```

### For Customer App:
The customer app automatically polls for handyman location when `BookingContentDetail` is opened. No additional code needed!

