import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/error/app_failure.dart';
import '../../../data/models/geo/wgs84_coordinate.dart';
import '../../../data/models/session/session_snapshot.dart';
import '../../../services/location_session_service.dart';

class LocationWorkspaceController extends GetxController {
  LocationWorkspaceController(this._session);

  final LocationSessionService _session;

  final formKey = GlobalKey<FormState>();
  final latitudeController = TextEditingController();
  final longitudeController = TextEditingController();

  SessionSnapshot get snapshot => _session.snapshot;
  bool get isBusy => _session.isBusy;
  bool get canConnect => _session.canConnect;
  bool get canSet => _session.canSet;
  bool get canClear => _session.canClear;
  DateTime get now => _session.now;
  AppFailure? get lastError => _session.lastError;

  String? validateLatitude(String? value) =>
      _validateNumber(value, name: '纬度', limit: 90);

  String? validateLongitude(String? value) =>
      _validateNumber(value, name: '经度', limit: 180);

  String? _validateNumber(
    String? value, {
    required String name,
    required int limit,
  }) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite) return '请输入有效的$name数值';
    if (parsed < -limit || parsed > limit) return '$name范围为 −$limit 至 $limit';
    return null;
  }

  void selectPreset(double latitude, double longitude) {
    latitudeController.text = latitude.toString();
    longitudeController.text = longitude.toString();
    formKey.currentState?.validate();
  }

  Future<void> connect() => _session.connect();

  Future<void> submitCoordinate() async {
    if (formKey.currentState?.validate() != true || !canSet) return;
    final coordinate = Wgs84Coordinate.parse(
      latitudeController.text,
      longitudeController.text,
    );
    await _session.setLocation(coordinate);
  }

  Future<void> clearSimulation() => _session.clearSimulation();

  @override
  void onClose() {
    latitudeController.dispose();
    longitudeController.dispose();
    super.onClose();
  }
}
