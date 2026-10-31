import 'package:flutter/material.dart';

class BusRoute {
  const BusRoute({
    required this.routeId,
    required this.routeNumber,
    required this.nameEn,
    required this.nameAr,
    required this.colorHex,
    required this.isActive,
  });

  final String routeId;
  final String routeNumber;
  final String nameEn;
  final String nameAr;
  final String colorHex;
  final bool isActive;

  Color get color {
    final value = int.tryParse(colorHex, radix: 16) ?? 0x1565C0;
    return Color(0xFF000000 | value);
  }

  factory BusRoute.fromMap(Map<String, Object?> map) {
    return BusRoute(
      routeId: map['route_id'] as String,
      routeNumber: map['route_number'] as String,
      nameEn: map['name_en'] as String,
      nameAr: map['name_ar'] as String? ?? '',
      colorHex: map['color_hex'] as String? ?? '1565C0',
      isActive: (map['is_active'] as num?)?.toInt() != 0,
    );
  }
}
