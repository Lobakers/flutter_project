import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

class LocationMapWidget extends StatefulWidget {
  final double latitude;
  final double longitude;
  final double height;
  final bool showRefreshButton;
  final VoidCallback? onRefresh;
  final List<ClientMarkerData>? clientMarkers;
  final double? radiusInMeters;

  const LocationMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.height = 200,
    this.showRefreshButton = false,
    this.onRefresh,
    this.clientMarkers,
    this.radiusInMeters,
  });

  @override
  State<LocationMapWidget> createState() => _LocationMapWidgetState();
}

class _LocationMapWidgetState extends State<LocationMapWidget>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseController;
  bool _isLiveTracking = true; // ✨ Default to tracking mode (Waze-style)

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _mapController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LocationMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✨ "Waze-mode": If tracking is active, follow the user!
    if (_isLiveTracking) {
      // Check if location actually changed to avoid unnecessary moves
      if (oldWidget.latitude != widget.latitude ||
          oldWidget.longitude != widget.longitude) {
        _recenterMap(animate: true, fromUpdate: true);
      }
    }
  }

  void _recenterMap({bool animate = true, bool fromUpdate = false}) {
    if (!fromUpdate) {
      // If manually clicked, re-enable tracking
      setState(() {
        _isLiveTracking = true;
      });
    }

    if (animate) {
      _mapController.move(LatLng(widget.latitude, widget.longitude), 16.0);
    } else {
      _mapController.move(LatLng(widget.latitude, widget.longitude), 16.0);
    }
  }

  // ✨ Handle user interaction
  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture && _isLiveTracking) {
      // User touched the map -> Stop following them
      setState(() {
        _isLiveTracking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16), // Slightly more rounded
        border: Border.all(
          color: Colors.white,
          width: 2,
        ), // Premium white border
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              14,
            ), // Match container minus border
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(widget.latitude, widget.longitude),
                initialZoom: 16.0,
                onPositionChanged:
                    _onMapPositionChanged, // ✨ Listen for gestures
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                // OpenStreetMap tiles
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yourcompany.beewhere',
                ),
                // Radius circle (if provided)
                if (widget.radiusInMeters != null && widget.radiusInMeters! > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(widget.latitude, widget.longitude),
                        radius: widget.radiusInMeters!,
                        useRadiusInMeter: true,
                        color: Colors.blue.withOpacity(0.1),
                        borderColor: Colors.blue.withOpacity(0.3),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                // ✨ Client markers with clustering
                if (widget.clientMarkers != null &&
                    widget.clientMarkers!.isNotEmpty)
                  MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      maxClusterRadius: 80, // Distance to group markers
                      size: const Size(50, 50),
                      markers: widget.clientMarkers!.map((client) {
                        final isInsideRadius = widget.radiusInMeters != null
                            ? client.distance <= widget.radiusInMeters!
                            : true;
                        final markerColor = isInsideRadius
                            ? Colors.green
                            : Colors.orange;

                        return Marker(
                          point: LatLng(client.latitude, client.longitude),
                          width: 80,
                          height: 80,
                          child: GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${client.name}\n${client.distance.toStringAsFixed(0)}m away',
                                  ),
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: markerColor,
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: markerColor,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.business,
                                    color: markerColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    client.abbreviation,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: markerColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      // ✨ Custom cluster marker builder
                      builder: (context, markers) {
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 74, 74, 228),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${markers.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                // User location marker (always on top)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(widget.latitude, widget.longitude),
                      width: 60,
                      height: 60,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulsing effect
                          ScaleTransition(
                            scale: _pulseController.drive(
                              Tween(
                                begin: 0.8,
                                end: 1.2,
                              ).chain(CurveTween(curve: Curves.easeInOut)),
                            ),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue.withOpacity(0.3),
                              ),
                            ),
                          ),
                          // Main marker
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.my_location, // Changed icon for variety
                              color: Colors.blueAccent,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Attribution
          Positioned(
            bottom: 30, // Moved up to not be covered by buttons
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: const Text(
                '© OpenStreetMap',
                style: TextStyle(fontSize: 9, color: Colors.black87),
              ),
            ),
          ),
          // Radius info indicator
          if (widget.radiusInMeters != null && widget.radiusInMeters! > 0)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.radar, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.radiusInMeters!.toStringAsFixed(0)}m',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Client count indicator
          if (widget.clientMarkers != null && widget.clientMarkers!.isNotEmpty)
            Positioned(
              top: widget.radiusInMeters != null && widget.radiusInMeters! > 0
                  ? 50
                  : 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.business, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.clientMarkers!.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Action Buttons Column
          Positioned(
            bottom: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Recenter Button
                FloatingActionButton.small(
                  heroTag: 'recenter_map',
                  onPressed: () => _recenterMap(),
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.center_focus_strong,
                    // ✨ Visual feedback: Blue when tracking, Grey when free-look
                    color: _isLiveTracking ? Colors.blueAccent : Colors.grey,
                  ),
                ),
                // Refresh button (if enabled)
                if (widget.showRefreshButton && widget.onRefresh != null) ...[
                  const SizedBox(height: 12),
                  FloatingActionButton.small(
                    heroTag: 'refresh_location',
                    onPressed: widget.onRefresh,
                    backgroundColor: Colors.blueAccent,
                    child: const Icon(Icons.refresh, color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Data class for client markers
class ClientMarkerData {
  final String clientGuid;
  final String? locationGuid; // ✨ NEW: Identify specific location
  final String name;
  final String abbreviation;
  final double latitude;
  final double longitude;
  final String? address; // ✨ NEW: Show specific address
  final double distance;

  ClientMarkerData({
    required this.clientGuid,
    this.locationGuid,
    required this.name,
    required this.abbreviation,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.distance,
  });
}
