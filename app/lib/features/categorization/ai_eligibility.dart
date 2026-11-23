/// Select at most one request's worth of available groups.
Set<String> initiallySelectedAiGroups(List<Map<String, dynamic>> candidates) =>
    candidates.take(25).map((c) => c['group_id'] as String).toSet();
