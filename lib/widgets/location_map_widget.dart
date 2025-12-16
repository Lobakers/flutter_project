import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

class LocationMapWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(latitude, longitude),
                initialZoom: 14.0,
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
                if (radiusInMeters != null && radiusInMeters! > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(latitude, longitude),
                        radius: radiusInMeters!,
                        useRadiusInMeter: true,
                        color: Colors.blue.withOpacity(0.15),
                        borderColor: Colors.blue.withOpacity(0.5),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                // ✨ Client markers with clustering
                if (clientMarkers != null && clientMarkers!.isNotEmpty)
                  MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      maxClusterRadius: 80, // Distance to group markers
                      size: const Size(50, 50),
                      markers: clientMarkers!.map((client) {
                        final isInsideRadius = radiusInMeters != null
                            ? client.distance <= radiusInMeters!
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
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
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
                                      fontSize: 9,
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
                      point: LatLng(latitude, longitude),
                      width: 50,
                      height: 50,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.blue,
                              size: 32,
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
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                ),
              ),
              child: const Text(
                '© OpenStreetMap',
                style: TextStyle(fontSize: 8, color: Colors.black54),
              ),
            ),
          ),
          // Radius info indicator
          if (radiusInMeters != null && radiusInMeters! > 0)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
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
                    const Icon(Icons.radar, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${radiusInMeters!.toStringAsFixed(0)}m',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Client count indicator
          if (clientMarkers != null && clientMarkers!.isNotEmpty)
            Positioned(
              top: radiusInMeters != null && radiusInMeters! > 0 ? 40 : 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
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
                    const Icon(Icons.business, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${clientMarkers!.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Refresh button
          if (showRefreshButton && onRefresh != null)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.blue),
                  onPressed: onRefresh,
                  tooltip: 'Refresh Location',
                ),
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
  final String name;
  final String abbreviation;
  final double latitude;
  final double longitude;
  final double distance;

  ClientMarkerData({
    required this.clientGuid,
    required this.name,
    required this.abbreviation,
    required this.latitude,
    required this.longitude,
    required this.distance,
  });
}
