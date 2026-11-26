enum RaCompatibilityStatus {
  supported,
  differentRomRequired,
  noAchievementSet,
  unknown,
  hashFailed,
  verificationUnavailable;

  bool get isIncompatible => switch (this) {
    differentRomRequired || noAchievementSet => true,
    supported || unknown || hashFailed || verificationUnavailable => false,
  };
}

class RaCompatibility {
  const RaCompatibility(this.status, {this.gameId, this.catalogueRefreshedAt});

  final RaCompatibilityStatus status;
  final int? gameId;
  final DateTime? catalogueRefreshedAt;
}
