enum RaCompatibilityStatus {
  supported,
  differentRomRequired,
  noAchievementSet,
  unknown;

  bool get isIncompatible => switch (this) {
    differentRomRequired || noAchievementSet => true,
    supported || unknown => false,
  };
}

class RaCompatibility {
  const RaCompatibility(this.status, {this.gameId, this.catalogueRefreshedAt});

  final RaCompatibilityStatus status;
  final int? gameId;
  final DateTime? catalogueRefreshedAt;
}
