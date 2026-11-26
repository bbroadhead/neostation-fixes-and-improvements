import '../l10n/app_locale.dart';
import '../models/ra_compatibility.dart';

extension RaCompatibilityLabels on RaCompatibilityStatus {
  String get labelKey => switch (this) {
    RaCompatibilityStatus.supported => AppLocale.raCompatibilitySupported,
    RaCompatibilityStatus.differentRomRequired =>
      AppLocale.raCompatibilityDifferent,
    RaCompatibilityStatus.noAchievementSet => AppLocale.raCompatibilityNoSet,
    RaCompatibilityStatus.unknown => AppLocale.raCompatibilityUnknown,
    RaCompatibilityStatus.hashFailed => AppLocale.raReviewHashFailed,
    RaCompatibilityStatus.verificationUnavailable =>
      AppLocale.raReviewVerificationUnavailable,
  };
}
