import 'package:flutter/material.dart';

import 'theme.dart';

/// One icon and one colour per attraction category, shared by Explore,
/// the map markers, the map legend and the place screen.
/// Colours come from the Daleel palette and all pass 4.5:1 on white.
class PlaceCategory {
  static IconData icon(int id) => switch (id) {
        1 => Icons.fort, // Heritage & Culture
        2 => Icons.museum_outlined, // Museums
        3 => Icons.terrain, // Nature & Mountains
        4 => Icons.attractions, // Family & Adventure
        5 => Icons.storefront_outlined, // Shopping
        6 => Icons.park_outlined, // Parks & Gardens
        7 => Icons.mosque_outlined, // Religious Sites
        8 => Icons.sports_soccer, // Sports & Recreation
        _ => Icons.place_outlined,
      };

  static Color color(int id) => switch (id) {
        1 => terracotta,
        2 => const Color(0xFF7A3E48), // date red
        3 => const Color(0xFF56636E), // Jebel Hafeet stone
        4 => const Color(0xFF9A6A12), // saffron
        5 => const Color(0xFF3E4A7A), // kohl
        6 => oasis,
        7 => falaj,
        8 => const Color(0xFF4A6E95),
        _ => mutedBrown,
      };
}

/// A narrow band in the style of Al Sadu weaving (UNESCO intangible heritage
/// of the UAE): a row of interlocking triangles between two thin rules.
/// The only decorative motif in the app; use it sparingly.
class SaduBand extends StatelessWidget {
  const SaduBand({super.key, this.height = 12});
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _SaduPainter()),
        ),
      );
}

class _SaduPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final rule = h * 0.14;
    final band = Paint()..color = darkBrown;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, rule), band);
    canvas.drawRect(Rect.fromLTWH(0, h - rule, size.width, rule), band);

    final inner = h - rule * 2;
    final w = inner * 1.2; // width of one triangle
    final up = Paint()..color = terracotta;
    final down = Paint()..color = dune;
    var i = 0;
    for (var x = -w / 2; x < size.width + w; x += w / 2, i++) {
      final top = rule;
      final bottom = h - rule;
      final path = Path();
      if (i.isEven) {
        path
          ..moveTo(x, bottom)
          ..lineTo(x + w / 2, top)
          ..lineTo(x + w, bottom);
        canvas.drawPath(path..close(), up);
      } else {
        path
          ..moveTo(x, top)
          ..lineTo(x + w / 2, bottom)
          ..lineTo(x + w, top);
        canvas.drawPath(path..close(), down);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// UNESCO World Heritage badge. The strongest fact about a place, so it
/// gets its own treatment instead of looking like the price chip.
class UnescoBadge extends StatelessWidget {
  const UnescoBadge({super.key, required this.arabic, this.compact = false});
  final bool arabic;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = arabic ? 'تراث عالمي · يونسكو' : 'UNESCO World Heritage';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: oasis,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: compact ? 14 : 16, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small "meta" line: an icon and a label in muted text.
class MetaItem extends StatelessWidget {
  const MetaItem({super.key, required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color ?? mutedBrown),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color ?? mutedBrown, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
}

/// Friendly full-area error with a retry button. Never shows raw exceptions.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    super.key,
    required this.title,
    required this.body,
    this.retryLabel,
    this.onRetry,
    this.icon = Icons.cloud_off_outlined,
  });
  final String title, body;
  final String? retryLabel;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: mutedBrown),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mutedBrown)),
              if (onRetry != null && retryLabel != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(retryLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

/// A soft placeholder block for loading states.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 14, this.width, this.radius = 8});
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: sandDeep,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}
