enum RaCompatibilityStatus {
  supported,
  differentRomRequired,
  noAchievementSet,
  unknown,
}

class RaCompatibility {
  const RaCompatibility(this.status, {this.gameId, this.catalogueRefreshedAt});

  final RaCompatibilityStatus status;
  final int? gameId;
  final DateTime? catalogueRefreshedAt;
}
