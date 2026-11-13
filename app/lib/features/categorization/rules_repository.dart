import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CategoryRule {
  const CategoryRule({
    required this.id,
    required this.kind,
    required this.matchType,
    required this.pattern,
    required this.categoryId,
    required this.priority,
    required this.enabled,
  });
  final String id, kind, matchType, pattern, categoryId;
  final int priority;
  final bool enabled;
  factory CategoryRule.fromJson(Map<String, dynamic> row) => CategoryRule(
    id: row['id'] as String,
    kind: row['kind'] as String,
    matchType: row['match_type'] as String,
    pattern: row['pattern'] as String,
    categoryId: row['category_id'] as String,
    priority: row['priority'] as int,
    enabled: row['enabled'] as bool,
  );
}

class MerchantAlias {
  const MerchantAlias({
    required this.id,
    required this.kind,
    required this.alias,
    required this.canonicalName,
    this.categoryId,
  });
  final String id, kind, alias, canonicalName;
  final String? categoryId;
  factory MerchantAlias.fromJson(Map<String, dynamic> r) => MerchantAlias(
    id: r['id'] as String,
    kind: r['kind'] as String,
    alias: r['alias'] as String,
    canonicalName: r['canonical_name'] as String,
    categoryId: r['category_id'] as String?,
  );
}

class CategoryMemory {
  const CategoryMemory({
    required this.id,
    required this.kind,
    required this.merchant,
    required this.categoryId,
  });
  final String id, kind, merchant, categoryId;
  factory CategoryMemory.fromJson(Map<String, dynamic> r) => CategoryMemory(
    id: r['id'] as String,
    kind: r['kind'] as String,
    merchant: r['merchant_key'] as String,
    categoryId: r['category_id'] as String,
  );
}

class RuleData {
  const RuleData(this.rules, this.aliases, this.memories);
  final List<CategoryRule> rules;
  final List<MerchantAlias> aliases;
  final List<CategoryMemory> memories;
}

abstract interface class RulesRepository {
  Future<RuleData> load();
  Future<void> addRule({
    required String kind,
    required String matchType,
    required String pattern,
    required String categoryId,
    required int priority,
  });
  Future<void> setRuleEnabled(String id, bool enabled);
  Future<void> deleteRule(String id);
  Future<void> addAlias({
    required String kind,
    required String alias,
    required String canonicalName,
    String? categoryId,
  });
  Future<void> deleteAlias(String id);
  Future<void> deleteMemory(String id);
}

class SupabaseRulesRepository implements RulesRepository {
  SupabaseRulesRepository(this.client);
  final SupabaseClient client;
  @override
  Future<RuleData> load() async {
    final rules = await client
        .from('category_rules')
        .select('id,kind,match_type,pattern,category_id,priority,enabled')
        .order('priority', ascending: false)
        .order('id');
    final aliases = await client
        .from('merchant_aliases')
        .select('id,kind,alias,canonical_name,category_id')
        .order('alias')
        .order('id');
    final memories = await client
        .from('category_feedback')
        .select('id,kind,merchant_key,category_id')
        .order('merchant_key')
        .order('id');
    return RuleData(
      rules.map(CategoryRule.fromJson).toList(),
      aliases.map(MerchantAlias.fromJson).toList(),
      memories.map(CategoryMemory.fromJson).toList(),
    );
  }

  @override
  Future<void> addRule({
    required String kind,
    required String matchType,
    required String pattern,
    required String categoryId,
    required int priority,
  }) async {
    await client.from('category_rules').insert({
      'kind': kind,
      'match_type': matchType,
      'pattern': pattern.trim(),
      'category_id': categoryId,
      'priority': priority,
    });
  }

  @override
  Future<void> setRuleEnabled(String id, bool enabled) async {
    await client
        .from('category_rules')
        .update({'enabled': enabled})
        .eq('id', id)
        .select('id')
        .single();
  }

  @override
  Future<void> deleteRule(String id) async {
    await client
        .from('category_rules')
        .delete()
        .eq('id', id)
        .select('id')
        .single();
  }

  @override
  Future<void> addAlias({
    required String kind,
    required String alias,
    required String canonicalName,
    String? categoryId,
  }) async {
    await client.from('merchant_aliases').insert({
      'kind': kind,
      'alias': alias.trim(),
      'canonical_name': canonicalName.trim(),
      'category_id': categoryId,
    });
  }

  @override
  Future<void> deleteAlias(String id) async {
    await client
        .from('merchant_aliases')
        .delete()
        .eq('id', id)
        .select('id')
        .single();
  }

  @override
  Future<void> deleteMemory(String id) async {
    await client
        .from('category_feedback')
        .delete()
        .eq('id', id)
        .select('id')
        .single();
  }
}

final rulesRepositoryProvider = Provider<RulesRepository>(
  (ref) => SupabaseRulesRepository(Supabase.instance.client),
  dependencies: const [],
);
final rulesProvider = FutureProvider.autoDispose<RuleData>(
  (ref) => ref.watch(rulesRepositoryProvider).load(),
  dependencies: [rulesRepositoryProvider],
  retry: (_, _) => null,
);
