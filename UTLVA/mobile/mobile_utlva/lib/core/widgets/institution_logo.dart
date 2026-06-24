import 'package:flutter/material.dart';
import '../config/institution_config.dart';
import '../theme/app_colors.dart';

/// Displays the institution logo from [InstitutionSettings].
///
/// Priority order:
///   1. Network URL  (logoNetworkUrl)
///   2. Local asset  (logoAssetPath)
///   3. Default placeholder — styled "U" tile, consistent with UTLVA branding
///
/// The placeholder always renders correctly — no blank/broken states.
class InstitutionLogo extends StatelessWidget {
  final InstitutionSettings settings;
  final double size;

  /// Background color of the placeholder tile.
  /// Defaults to [AppColors.surface] (white), which shows well on dark AppBars.
  final Color placeholderBackground;

  /// Text/icon color inside the placeholder tile.
  final Color placeholderForeground;

  const InstitutionLogo({
    super.key,
    this.settings = InstitutionSettings.defaults,
    this.size = 44,
    this.placeholderBackground = AppColors.surface,
    this.placeholderForeground = AppColors.secondary,
  });

  @override
  Widget build(BuildContext context) {
    if (settings.logoNetworkUrl != null) {
      return _networkLogo(settings.logoNetworkUrl!);
    }
    if (settings.logoAssetPath != null) {
      return _assetLogo(settings.logoAssetPath!);
    }
    return _placeholder();
  }

  Widget _networkLogo(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, st) => _placeholder(),
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : _placeholder(),
      ),
    );
  }

  Widget _assetLogo(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, st) => _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: placeholderBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: placeholderForeground.withAlpha(30),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          'U',
          style: TextStyle(
            color: placeholderForeground,
            fontSize: size * 0.48,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}
