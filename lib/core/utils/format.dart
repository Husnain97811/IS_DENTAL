/// 14:30 → "2:30 PM". Display only — storage is unchanged.
String fmtTime12(DateTime t) {
  final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}
