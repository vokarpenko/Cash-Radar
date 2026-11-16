import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransfersRepository {
  TransfersRepository(this.client);
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> candidates() async => (await client
      .from('transfer_candidates')
      .select()
      .order('debit_date', ascending: false)
      .limit(300));
  Future<List<Map<String, dynamic>>> groups() async => (await client
      .from('transfer_group_details')
      .select()
      .order('created_at', ascending: false));
  Future<void> confirm(
    String debit,
    String credit, {
    String? fee,
    String? debitVersion,
    String? creditVersion,
    String? feeVersion,
  }) async => client.rpc(
    'confirm_transfer',
    params: {
      'p_debit': debit,
      'p_credit': credit,
      'p_fee': fee,
      'p_debit_version': debitVersion,
      'p_credit_version': creditVersion,
      'p_fee_version': feeVersion,
    },
  );
  Future<void> reject(String debit, String credit) async => client.rpc(
    'reject_transfer_candidate',
    params: {'p_debit': debit, 'p_credit': credit},
  );
  Future<void> unlink(String id) async =>
      client.rpc('unlink_transfer', params: {'p_id': id});
  Future<void> cash(
    String debit,
    String wallet, {
    String? debitVersion,
  }) async => client.rpc(
    'transfer_to_cash',
    params: {
      'p_debit': debit,
      'p_cash': wallet,
      'p_debit_version': debitVersion,
    },
  );
  Future<void> create({
    required String from,
    required String to,
    required String date,
    required String fromAmount,
    required String toAmount,
    required String fee,
    required String requestId,
    String? description,
  }) async => client.rpc(
    'create_manual_transfer',
    params: {
      'p_from': from,
      'p_to': to,
      'p_date': date,
      'p_from_amount': fromAmount,
      'p_to_amount': toAmount,
      'p_fee': fee,
      'p_request_id': requestId,
      'p_description': description,
    },
  );
}

final transfersRepositoryProvider = Provider<TransfersRepository>(
  (ref) => TransfersRepository(Supabase.instance.client),
  dependencies: const [],
);
final transferCandidatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(transfersRepositoryProvider).candidates(),
      dependencies: [transfersRepositoryProvider],
      retry: (_, _) => null,
    );
final transferGroupsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(transfersRepositoryProvider).groups(),
      dependencies: [transfersRepositoryProvider],
      retry: (_, _) => null,
    );
