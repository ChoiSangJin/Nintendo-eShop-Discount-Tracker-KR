/// Korea has a fixed UTC+09:00 offset and no daylight saving time.
class DailyCollectionPolicy {
  static const koreaOffset = Duration(hours: 9);
  static const retryDelay = Duration(minutes: 30);

  /// Most recent 01:00 in Korea, expressed in UTC.
  static DateTime boundary(DateTime now) {
    final korea = now.toUtc().add(koreaOffset);
    var date = DateTime.utc(korea.year, korea.month, korea.day, 1);
    if (korea.isBefore(date)) date = date.subtract(const Duration(days: 1));
    return date.subtract(koreaOffset);
  }

  static DateTime nextRun(DateTime now) =>
      boundary(now).add(const Duration(days: 1));

  static bool isDue(DateTime now, DateTime? catalogAt, DateTime? pricesAt) {
    final slot = boundary(now);
    return catalogAt == null ||
        pricesAt == null ||
        catalogAt.isBefore(slot) ||
        pricesAt.isBefore(slot) ||
        catalogAt.isAfter(now) ||
        pricesAt.isAfter(now);
  }
}
