import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import 'models.dart';

/// One typed method per endpoint in docs/api/API.md. Screens and controllers
/// talk to this class only — never to Dio or ApiClient directly.
class SentinelRepository {
  SentinelRepository(this._api);

  final ApiClient _api;

  Future<Health> health() async =>
      Health.fromJson(await _api.get('/api/health') as Json);

  Future<SystemStatus> status() async =>
      SystemStatus.fromJson(await _api.get('/api/status') as Json);

  Future<Stats> stats() async =>
      Stats.fromJson(await _api.get('/api/stats') as Json);

  Future<EmailPage> emails({
    Set<EmailCategory> categories = const {},
    bool includeDone = false,
    bool includeTrashed = true,
    String? project,
    int limit = 50,
    int? beforeId,
  }) async {
    final data = await _api.get(
      '/api/emails',
      query: {
        if (categories.isNotEmpty)
          'category': categories.map((c) => c.wire).toList(),
        'include_done': includeDone,
        'include_trashed': includeTrashed,
        'project': ?project,
        'limit': limit,
        'before_id': ?beforeId,
      },
    );
    return EmailPage.fromJson(data as Json);
  }

  Future<EmailItem> email(int id) async =>
      EmailItem.fromJson(await _api.get('/api/emails/$id') as Json);

  Future<ActionResult> setDone(int id, {required bool done}) async =>
      ActionResult.fromJson(
        await _api.post('/api/emails/$id/done', body: {'done': done}) as Json,
      );

  Future<ActionResult> reclassify(int id, EmailCategory category) async =>
      ActionResult.fromJson(
        await _api.post(
          '/api/emails/$id/reclassify',
          body: {'category': category.wire},
        ) as Json,
      );

  Future<ActionResult> protectSender(int id) async => ActionResult.fromJson(
    await _api.post('/api/emails/$id/protect-sender') as Json,
  );

  Future<ActionResult> restore(int id) async =>
      ActionResult.fromJson(await _api.post('/api/emails/$id/restore') as Json);

  Future<AlertsResponse> alerts({required int afterId, int limit = 50}) async =>
      AlertsResponse.fromJson(
        await _api.get(
          '/api/alerts',
          query: {'after_id': afterId, 'limit': limit},
        ) as Json,
      );

  Future<List<ProjectSummary>> projects() async =>
      (await _api.get('/api/projects') as List<Object?>)
          .map((e) => ProjectSummary.fromJson(e! as Json))
          .toList(growable: false);

  Future<List<ProjectUpdate>> projectUpdates(
    String project, {
    int limit = 50,
  }) async =>
      (await _api.get(
            '/api/project-updates',
            query: {'project': project, 'limit': limit},
          ) as List<Object?>)
          .map((e) => ProjectUpdate.fromJson(e! as Json))
          .toList(growable: false);

  Future<List<UnsubscribeLog>> unsubscribes({int limit = 50}) async =>
      (await _api.get('/api/unsubscribes', query: {'limit': limit})
              as List<Object?>)
          .map((e) => UnsubscribeLog.fromJson(e! as Json))
          .toList(growable: false);

  Future<ScanRun> startScan({int limit = 20}) async => ScanRun.fromJson(
    await _api.post('/api/scan', body: {'limit': limit}) as Json,
  );

  Future<ScanRun> scan(int id) async =>
      ScanRun.fromJson(await _api.get('/api/scans/$id') as Json);

  Future<List<ScanRun>> scans({int limit = 20}) async =>
      (await _api.get('/api/scans', query: {'limit': limit}) as List<Object?>)
          .map((e) => ScanRun.fromJson(e! as Json))
          .toList(growable: false);

  Future<RuntimeSettings> settings() async =>
      RuntimeSettings.fromJson(await _api.get('/api/settings') as Json);

  Future<RuntimeSettings> updateSettings(RuntimeSettingsPatch patch) async =>
      RuntimeSettings.fromJson(
        await _api.patch('/api/settings', body: patch.toJson()) as Json,
      );

  /// Latest briefing, or null when Hermes has not written one yet (404).
  Future<Briefing?> latestBriefing() async {
    try {
      return Briefing.fromJson(await _api.get('/api/briefings/latest') as Json);
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.notFound) return null;
      rethrow;
    }
  }

  Future<List<Briefing>> briefings({int limit = 20}) async =>
      (await _api.get('/api/briefings', query: {'limit': limit})
              as List<Object?>)
          .map((e) => Briefing.fromJson(e! as Json))
          .toList(growable: false);
}
