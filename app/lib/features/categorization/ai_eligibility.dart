/// A conservative convenience filter, not proof that a name is public.
/// The edge function repeats this check before making any provider request.
bool isEligibleAiName(String name) {
  final s = name.trim();
  if (s.length < 3 || s.length > 80 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(s)) {
    return false;
  }
  if (RegExp(
    r'[@/:\\]|\b(?:https?|www|iban|account|card|visa|mastercard)\b',
    caseSensitive: false,
    unicode: true,
  ).hasMatch(s)) {
    return false;
  }
  if (RegExp(
    r'\b[\p{L}\p{N}-]+\.[a-z]{2,}\b',
    caseSensitive: false,
    unicode: true,
  ).hasMatch(s)) {
    return false;
  }
  if (RegExp(r'\d{3}|(?:\d[\s().-]*){5}').hasMatch(s)) return false;
  if (!RegExp(r"^[\p{L}\p{M}\p{N}\s&.,'()\-]+$", unicode: true).hasMatch(s)) {
    return false;
  }
  return RegExp(r'\p{L}', unicode: true).hasMatch(s);
}

/// Select at most one request's worth, excluding names blocked by the filter.
Set<String> initiallySelectedAiGroups(List<Map<String, dynamic>> candidates) =>
    candidates
        .where((c) => isEligibleAiName(c['merchant'] as String))
        .take(10)
        .map((c) => c['group_id'] as String)
        .toSet();
