/// Formats a timestamp as short relative copy ("Just now", "2h ago",
/// "3d ago"), falling back to a plain date once it's more than a week old.
String relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);

  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';

  return '${dt.day}/${dt.month}/${dt.year}';
}
