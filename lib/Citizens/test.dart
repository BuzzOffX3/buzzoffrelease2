import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapSmokeTest extends StatefulWidget {
  const MapSmokeTest({super.key});
  @override
  State<MapSmokeTest> createState() => _MapSmokeTestState();
}

class _MapSmokeTestState extends State<MapSmokeTest> {
  final _ctrl = Completer<GoogleMapController>();
  static const _colombo = CameraPosition(
    target: LatLng(6.9271, 79.8612),
    zoom: 14,
  );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: GoogleMap(
        initialCameraPosition: _colombo,
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        mapType: MapType.normal,
      ),
    );
  }
}
