final class Wgs84Coordinate {
  factory Wgs84Coordinate({
    required double latitude,
    required double longitude,
  }) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw const FormatException('纬度必须是 -90 至 90 之间的有限数字');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw const FormatException('经度必须是 -180 至 180 之间的有限数字');
    }
    return Wgs84Coordinate._(latitude, longitude);
  }

  const Wgs84Coordinate._(this.latitude, this.longitude);

  factory Wgs84Coordinate.parse(String latitude, String longitude) {
    final lat = double.tryParse(latitude.trim());
    final lng = double.tryParse(longitude.trim());
    if (lat == null || lng == null) {
      throw const FormatException('请输入有效的纬度和经度');
    }
    return Wgs84Coordinate(latitude: lat, longitude: lng);
  }

  final double latitude;
  final double longitude;
  String get label =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  @override
  bool operator ==(Object other) =>
      other is Wgs84Coordinate &&
      latitude == other.latitude &&
      longitude == other.longitude;
  @override
  int get hashCode => Object.hash(latitude, longitude);
}
