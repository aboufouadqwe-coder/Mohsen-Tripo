import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../features/bootstrap/session_bootstrapper.dart';
import 'generation_gateway.dart';
import 'project_repository.dart';
import 'reference_image_repository.dart';
import 'results_repository.dart';
import 'template_repository.dart';

final class SupabaseAuthPort implements AuthPort {
  const SupabaseAuthPort(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<String?> signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    return response.user?.id;
  }
}

final class SupabaseProjectDataSource implements ProjectDataSource {
  const SupabaseProjectDataSource(this._client);

  final SupabaseClient _client;

  static const _selection =
      'id,name,reference_image_path,template_id,identity_prompt';
  static const _defaultTemplateId =
      '00000000-0000-0000-0000-000000000001';

  @override
  Future<List<Map<String, Object?>>> listForOwner(String ownerId) async {
    final rows = await _client
        .from('projects')
        .select(_selection)
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false);

    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  @override
  Future<Map<String, Object?>> createForOwner({
    required String ownerId,
    required String name,
    required String identityPrompt,
  }) async {
    final row = await _client
        .from('projects')
        .insert({
          'owner_id': ownerId,
          'name': name,
          'identity_prompt': identityPrompt,
          'template_id': _defaultTemplateId,
        })
        .select(_selection)
        .single();

    return Map<String, Object?>.from(row);
  }

  @override
  Future<Map<String, Object?>> updateReferenceImage({
    required String ownerId,
    required String projectId,
    required String storagePath,
  }) async {
    final row = await _client
        .from('projects')
        .update({'reference_image_path': storagePath})
        .eq('id', projectId)
        .eq('owner_id', ownerId)
        .select(_selection)
        .single();

    return Map<String, Object?>.from(row);
  }
}

final class SupabaseTemplateDataSource implements TemplateDataSource {
  const SupabaseTemplateDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, Object?>>> listVisibleTemplates() async {
    final rows = await _client
        .from('asset_templates')
        .select(
          'id,name,description,is_builtin,'
          'template_parts(key,label,prompt_fragment,sort_order,enabled_by_default)',
        )
        .order('is_builtin', ascending: false)
        .order('name');

    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }
}

final class SupabaseFunctionInvoker implements FunctionInvoker {
  const SupabaseFunctionInvoker(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, Object?>> invoke(
    String functionName,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _client.functions.invoke(
        functionName,
        body: body,
      );

      if (response.status < 200 || response.status >= 300) {
        throw AppFailure.function();
      }

      final data = response.data;
      if (data is! Map) throw AppFailure.function();

      return Map<String, Object?>.from(
        data.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.function();
    }
  }
}

final class SupabaseGenerationJobDataSource implements GenerationJobDataSource {
  const SupabaseGenerationJobDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, Object?>>> listActiveJobs(
    String projectId,
  ) async {
    final rows = await _client
        .from('generation_jobs')
        .select(
          'id,project_id,part_key,provider,operation,provider_task_id,'
          'status,progress,error_code,error_message,created_at,completed_at',
        )
        .eq('project_id', projectId)
        .inFilter('status', const ['queued', 'running'])
        .order('created_at');

    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }
}

final class SupabaseResultsDataSource implements ResultsDataSource {
  const SupabaseResultsDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, Object?>>> listHistoryRows(
    String projectId,
  ) async {
    final rows = await _client
        .from('generation_jobs')
        .select(
          'id,project_id,part_key,provider,operation,provider_task_id,'
          'status,progress,error_code,error_message,created_at,completed_at,'
          'asset_results(id,project_id,generation_job_id,part_key,'
          'storage_path,mime_type,width,height,created_at)',
        )
        .eq('project_id', projectId)
        .order('created_at', ascending: false);

    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  @override
  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    required int expiresIn,
  }) {
    return _client.storage.from(bucket).createSignedUrl(
          path,
          expiresIn,
        );
  }
}

final class SupabaseReferenceStoragePort implements ReferenceStoragePort {
  const SupabaseReferenceStoragePort(this._client);

  final SupabaseClient _client;

  @override
  Future<Uint8List> downloadReference(String path) {
    return _client.storage.from('reference-images').download(path);
  }

  @override
  Future<Uint8List> downloadGenerated(String path) {
    return _client.storage.from('generated-images').download(path);
  }

  @override
  Future<void> upload({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      await _client.storage.from('reference-images').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );
    } catch (_) {
      throw AppFailure.storage();
    }
  }
}

String requireCurrentSupabaseUserId(SupabaseClient client) {
  final userId = client.auth.currentUser?.id.trim();
  if (userId == null || userId.isEmpty) {
    throw AppFailure.authentication();
  }
  return userId;
}
