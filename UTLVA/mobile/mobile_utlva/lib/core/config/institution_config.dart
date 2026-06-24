/// Holds institution-specific branding values.
///
/// All widgets that display institution identity read from this model.
/// Nothing is hardcoded in widgets — logo and name come from here.
///
/// For now the [defaults] constant is used throughout the app.
/// Phase N: System Administrator settings screen will update [current]
/// and persist the values via the backend API.
class InstitutionSettings {
  final String institutionName;

  /// Local asset path, e.g. 'assets/images/logo.png'.
  /// Null means show the default placeholder.
  final String? logoAssetPath;

  /// Remote URL for a network-hosted logo (set by admin later).
  /// Takes priority over [logoAssetPath] if both are provided.
  final String? logoNetworkUrl;

  const InstitutionSettings({
    this.institutionName = 'Your Institution Name',
    this.logoAssetPath,
    this.logoNetworkUrl,
  });

  /// Application-wide defaults used before an admin configures the institution.
  static const InstitutionSettings defaults = InstitutionSettings(
    institutionName: 'Your Institution Name',
  );

  bool get hasLogo => logoNetworkUrl != null || logoAssetPath != null;

  InstitutionSettings copyWith({
    String? institutionName,
    String? logoAssetPath,
    String? logoNetworkUrl,
  }) {
    return InstitutionSettings(
      institutionName: institutionName ?? this.institutionName,
      logoAssetPath: logoAssetPath ?? this.logoAssetPath,
      logoNetworkUrl: logoNetworkUrl ?? this.logoNetworkUrl,
    );
  }
}
