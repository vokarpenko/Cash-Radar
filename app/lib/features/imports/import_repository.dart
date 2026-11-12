import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const maxStatementBytes = 1024 * 1024;

class ImportProblem implements Exception {
  const ImportProblem(this.message);
  final String message;
}

class SelectedStatement {
  const SelectedStatement(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  bool get isEncryptedOffice =>
      bytes.length >= 8 &&
      const [
        0xd0,
        0xcf,
        0x11,
        0xe0,
        0xa1,
        0xb1,
        0x1a,
        0xe1,
      ].asMap().entries.every((e) => bytes[e.key] == e.value);
}

abstract interface class StatementFilePicker {
  Future<SelectedStatement?> pick();
}

class PlatformStatementFilePicker implements StatementFilePicker {
  @override
  Future<SelectedStatement?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'pdf'],
    );
    if (file == null) return null;
    final size = file.lengthSync() ?? await file.length();
    if (size != null && (size <= 0 || size > maxStatementBytes)) {
      throw const ImportProblem('Файл пуст или больше 1 МиБ.');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final part in file.readAsByteStream()) {
      if (buffer.length + part.length > maxStatementBytes) {
        throw const ImportProblem('Файл больше 1 МиБ.');
      }
      buffer.add(part);
    }
    if (buffer.length == 0) throw const ImportProblem('Файл пуст.');
    return SelectedStatement(file.name, buffer.takeBytes());
  }
}

class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.accountId,
    required this.accountCurrency,
    required this.filename,
    required this.status,
    required this.rowCount,
    required this.errorCount,
    required this.importedCount,
    required this.errors,
    required this.createdAt,
    required this.format,
    this.periodStart,
    this.periodEnd,
  });
  final String id,
      accountId,
      accountCurrency,
      filename,
      status,
      createdAt,
      format;
  final int rowCount, errorCount, importedCount;
  final String? periodStart, periodEnd;
  final List<ImportIssue> errors;
  factory ImportBatch.fromJson(Map<String, dynamic> row) => ImportBatch(
    id: row['id'] as String,
    accountId: row['account_id'] as String,
    accountCurrency: row['account_currency'] as String,
    filename: row['original_filename'] as String,
    status: row['status'] as String,
    rowCount: row['row_count'] as int,
    errorCount: row['error_count'] as int,
    importedCount: row['imported_count'] as int,
    errors: (row['errors'] as List)
        .map(
          (x) => ImportIssue(
            row: x['row'] as int,
            message: x['message'] as String,
          ),
        )
        .toList(growable: false),
    createdAt: row['created_at'] as String,
    format: row['format'] as String,
    periodStart: row['period_start'] as String?,
    periodEnd: row['period_end'] as String?,
  );
}

class ImportIssue {
  const ImportIssue({required this.row, required this.message});
  final int row;
  final String message;
}

class ImportRow {
  const ImportRow({
    required this.rowNumber,
    required this.date,
    required this.type,
    required this.amount,
    required this.currency,
    required this.accountAmount,
    required this.category,
    this.description,
    this.commissionAmount,
  });
  final int rowNumber;
  final String date, type, amount, currency, accountAmount, category;
  final String? description, commissionAmount;
  factory ImportRow.fromJson(Map<String, dynamic> row) => ImportRow(
    rowNumber: row['row_number'] as int,
    date: row['transaction_date'] as String,
    type: row['transaction_type'] as String,
    amount: row['amount'] as String,
    currency: row['currency'] as String,
    accountAmount: row['account_amount'] as String,
    category: row['category_name'] as String,
    description: row['raw_description'] as String?,
    commissionAmount: row['commission_amount'] as String?,
  );
}

class ImportDetail {
  const ImportDetail(this.batch, this.rows);
  final ImportBatch batch;
  final List<ImportRow> rows;
}

class PrepareResult {
  const PrepareResult(this.id, this.duplicate);
  final String id;
  final bool duplicate;
}

abstract interface class ImportsRepository {
  Future<List<ImportBatch>> loadBatches();
  Future<ImportDetail> loadDetail(String id);
  Future<PrepareResult> prepare(
    String accountId,
    SelectedStatement file,
    String expectedUserId, {
    String? password,
  });
  Future<void> confirm(String id);
  Future<void> cancel(String id);
}

class SupabaseImportsRepository implements ImportsRepository {
  SupabaseImportsRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<ImportBatch>> loadBatches() async {
    final rows = await client
        .from('import_batches')
        .select(
          'id,account_id,account_currency,original_filename,status,row_count,error_count,imported_count,errors,created_at,format,period_start,period_end',
        )
        .order('created_at', ascending: false)
        .order('id');
    return rows.map(ImportBatch.fromJson).toList(growable: false);
  }

  @override
  Future<ImportDetail> loadDetail(String id) async {
    final row = await client
        .from('import_batches')
        .select(
          'id,account_id,account_currency,original_filename,status,row_count,error_count,imported_count,errors,created_at,format,period_start,period_end',
        )
        .eq('id', id)
        .single();
    final items = await client
        .from('import_item_details')
        .select(
          'row_number,transaction_date,transaction_type,amount,currency,account_amount,category_name,raw_description,commission_amount',
        )
        .eq('batch_id', id)
        .order('row_number');
    return ImportDetail(
      ImportBatch.fromJson(row),
      items.map(ImportRow.fromJson).toList(growable: false),
    );
  }

  @override
  Future<PrepareResult> prepare(
    String accountId,
    SelectedStatement file,
    String expectedUserId, {
    String? password,
  }) async {
    final session = client.auth.currentSession;
    if (session == null || session.user.id != expectedUserId) {
      throw const ImportProblem('Сессия изменилась. Выберите файл заново.');
    }
    try {
      final result = await client.functions.invoke(
        'import-statement',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {
          'account_id': accountId,
          'filename': file.name,
          'file_base64': base64Encode(file.bytes),
          if (password != null && password.isNotEmpty) 'password': password,
        },
      );
      final data = result.data as Map<String, dynamic>;
      return PrepareResult(data['id'] as String, data['duplicate'] as bool);
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] is String) {
        throw ImportProblem(details['error'] as String);
      }
      throw const ImportProblem(
        'Не удалось подготовить импорт. Проверьте подключение.',
      );
    }
  }

  @override
  Future<void> confirm(String id) async {
    await client.rpc('confirm_statement_import', params: {'p_batch_id': id});
  }

  @override
  Future<void> cancel(String id) async {
    await client.rpc('cancel_statement_import', params: {'p_batch_id': id});
  }
}

final statementFilePickerProvider = Provider<StatementFilePicker>(
  (ref) => PlatformStatementFilePicker(),
  dependencies: const [],
);
final importsRepositoryProvider = Provider<ImportsRepository>(
  (ref) => SupabaseImportsRepository(Supabase.instance.client),
  dependencies: const [],
);
final importBatchesProvider = FutureProvider.autoDispose<List<ImportBatch>>(
  (ref) => ref.watch(importsRepositoryProvider).loadBatches(),
  dependencies: [importsRepositoryProvider],
  retry: (_, _) => null,
);
final importDetailProvider = FutureProvider.autoDispose
    .family<ImportDetail, String>(
      (ref, id) => ref.watch(importsRepositoryProvider).loadDetail(id),
      dependencies: [importsRepositoryProvider],
      retry: (_, _) => null,
    );
