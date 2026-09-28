// Typed mirrors of docs/api/openapi.json. Field names match the JSON keys
// (snake_case on the wire, camelCase in Dart). Parsers are tolerant of
// missing optional fields but strict about required ones.

typedef Json = Map<String, Object?>;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

List<T> _list<T>(Object? value, T Function(Json) parse) =>
    (value as List<Object?>? ?? const [])
        .map((e) => parse(e! as Json))
        .toList(growable: false);

enum EmailCategory {
  urgentActionable('urgent_actionable', 'Urgent'),
  projectUpdate('project_update', 'Project'),
  transactional('transactional', 'Receipt'),
  generalFyi('general_fyi', 'FYI'),
  marketingPromo('marketing_promo', 'Marketing'),
  spam('spam', 'Spam');

  const EmailCategory(this.wire, this.label);

  /// Value used by the API.
  final String wire;

  /// Short human label (DESIGN_BRIEF §3.2).
  final String label;

  static EmailCategory fromWire(String value) => values.firstWhere(
    (c) => c.wire == value,
    orElse: () => EmailCategory.generalFyi,
  );
}

class Health {
  const Health({required this.status, required this.version});
  factory Health.fromJson(Json j) =>
      Health(status: j['status']! as String, version: j['version']! as String);
  final String status;
  final String version;
}

class EmailItem {
  const EmailItem({
    required this.id,
    required this.category,
    required this.urgency,
    this.messageId,
    this.sender = '',
    this.senderEmail = '',
    this.subject = '',
    this.receivedAt,
    this.summary = '',
    this.projectName,
    this.actionRequired = false,
    this.actionDescription,
    this.isTrashed = false,
    this.isUnsubscribed = false,
    this.isDone = false,
    this.reclassified = false,
    this.dryRun = false,
    this.createdAt,
  });

  factory EmailItem.fromJson(Json j) => EmailItem(
    id: j['id']! as int,
    messageId: j['message_id'] as String?,
    sender: j['sender'] as String? ?? '',
    senderEmail: j['sender_email'] as String? ?? '',
    subject: j['subject'] as String? ?? '',
    receivedAt: _date(j['received_at']),
    category: EmailCategory.fromWire(j['category']! as String),
    urgency: j['urgency'] as int? ?? 1,
    summary: j['summary'] as String? ?? '',
    projectName: j['project_name'] as String?,
    actionRequired: j['action_required'] as bool? ?? false,
    actionDescription: j['action_description'] as String?,
    isTrashed: j['is_trashed'] as bool? ?? false,
    isUnsubscribed: j['is_unsubscribed'] as bool? ?? false,
    isDone: j['is_done'] as bool? ?? false,
    reclassified: j['reclassified'] as bool? ?? false,
    dryRun: j['dry_run'] as bool? ?? false,
    createdAt: _date(j['created_at']),
  );

  final int id;
  final String? messageId;
  final String sender;
  final String senderEmail;
  final String subject;
  final DateTime? receivedAt;
  final EmailCategory category;
  final int urgency;
  final String summary;
  final String? projectName;
  final bool actionRequired;
  final String? actionDescription;
  final bool isTrashed;
  final bool isUnsubscribed;
  final bool isDone;
  final bool reclassified;
  final bool dryRun;
  final DateTime? createdAt;

  /// Display name: `Legal <legal@client.io>` -> `Legal`.
  String get senderName {
    final lt = sender.indexOf('<');
    final name = (lt > 0 ? sender.substring(0, lt) : sender).trim();
    return name.isNotEmpty
        ? name.replaceAll('"', '')
        : (senderEmail.isNotEmpty ? senderEmail : 'Unknown sender');
  }

  /// Timestamp used for sorting/grouping in the feed.
  DateTime? get timestamp => receivedAt ?? createdAt;

  EmailItem copyWith({
    bool? isDone,
    EmailCategory? category,
    bool? isTrashed,
  }) => EmailItem(
    id: id,
    messageId: messageId,
    sender: sender,
    senderEmail: senderEmail,
    subject: subject,
    receivedAt: receivedAt,
    category: category ?? this.category,
    urgency: urgency,
    summary: summary,
    projectName: projectName,
    actionRequired: actionRequired,
    actionDescription: actionDescription,
    isTrashed: isTrashed ?? this.isTrashed,
    isUnsubscribed: isUnsubscribed,
    isDone: isDone ?? this.isDone,
    reclassified: category != null || reclassified,
    dryRun: dryRun,
    createdAt: createdAt,
  );
}

class EmailPage {
  const EmailPage({required this.items, this.nextCursor});
  factory EmailPage.fromJson(Json j) => EmailPage(
    items: _list(j['items'], EmailItem.fromJson),
    nextCursor: j['next_cursor'] as int?,
  );
  final List<EmailItem> items;
  final int? nextCursor;
}

class AlertsResponse {
  const AlertsResponse({required this.items, required this.cursor});
  factory AlertsResponse.fromJson(Json j) => AlertsResponse(
    items: _list(j['items'], EmailItem.fromJson),
    cursor: j['cursor']! as int,
  );
  final List<EmailItem> items;
  final int cursor;
}

class ActionResult {
  const ActionResult({required this.ok, this.message = '', this.email});
  factory ActionResult.fromJson(Json j) => ActionResult(
    ok: j['ok']! as bool,
    message: j['message'] as String? ?? '',
    email: j['email'] == null ? null : EmailItem.fromJson(j['email']! as Json),
  );
  final bool ok;
  final String message;
  final EmailItem? email;
}

class ProjectSummary {
  const ProjectSummary({
    required this.name,
    required this.updateCount,
    this.lastUpdateAt,
    this.openActions = 0,
    this.maxUrgency = 1,
  });
  factory ProjectSummary.fromJson(Json j) => ProjectSummary(
    name: j['name']! as String,
    updateCount: j['update_count']! as int,
    lastUpdateAt: _date(j['last_update_at']),
    openActions: j['open_actions'] as int? ?? 0,
    maxUrgency: j['max_urgency'] as int? ?? 1,
  );
  final String name;
  final int updateCount;
  final DateTime? lastUpdateAt;
  final int openActions;
  final int maxUrgency;
}

class ProjectUpdate {
  const ProjectUpdate({
    required this.id,
    required this.projectName,
    this.emailId,
    this.sender,
    this.subject,
    this.summary,
    this.urgency = 1,
    this.actionRequired = false,
    this.actionDescription,
    this.receivedAt,
    this.isDone = false,
    this.createdAt,
  });
  factory ProjectUpdate.fromJson(Json j) => ProjectUpdate(
    id: j['id']! as int,
    emailId: j['email_id'] as int?,
    projectName: j['project_name']! as String,
    sender: j['sender'] as String?,
    subject: j['subject'] as String?,
    summary: j['summary'] as String?,
    urgency: j['urgency'] as int? ?? 1,
    actionRequired: j['action_required'] as bool? ?? false,
    actionDescription: j['action_description'] as String?,
    receivedAt: _date(j['received_at']),
    isDone: j['is_done'] as bool? ?? false,
    createdAt: _date(j['created_at']),
  );
  final int id;
  final int? emailId;
  final String projectName;
  final String? sender;
  final String? subject;
  final String? summary;
  final int urgency;
  final bool actionRequired;
  final String? actionDescription;
  final DateTime? receivedAt;
  final bool isDone;
  final DateTime? createdAt;
}

class UnsubscribeLog {
  const UnsubscribeLog({
    required this.id,
    required this.method,
    required this.success,
    this.emailId,
    this.senderEmail = '',
    this.domain = '',
    this.target,
    this.httpStatus,
    this.errorMessage,
    this.attemptedAt,
  });
  factory UnsubscribeLog.fromJson(Json j) => UnsubscribeLog(
    id: j['id']! as int,
    emailId: j['email_id'] as int?,
    senderEmail: j['sender_email'] as String? ?? '',
    domain: j['domain'] as String? ?? '',
    method: j['method']! as String,
    target: j['target'] as String?,
    httpStatus: j['http_status'] as int?,
    success: j['success']! as bool,
    errorMessage: j['error_message'] as String?,
    attemptedAt: _date(j['attempted_at']),
  );
  final int id;
  final int? emailId;
  final String senderEmail;
  final String domain;
  final String method;
  final String? target;
  final int? httpStatus;
  final bool success;
  final String? errorMessage;
  final DateTime? attemptedAt;
}

class Stats {
  const Stats({
    required this.totalEmailsProcessed,
    required this.unsubscribedCount,
    required this.trashedCount,
    required this.projectUpdatesCount,
    required this.notificationsSentCount,
    required this.openActionsCount,
    required this.categories,
  });
  factory Stats.fromJson(Json j) => Stats(
    totalEmailsProcessed: j['total_emails_processed']! as int,
    unsubscribedCount: j['unsubscribed_count']! as int,
    trashedCount: j['trashed_count']! as int,
    projectUpdatesCount: j['project_updates_count']! as int,
    notificationsSentCount: j['notifications_sent_count']! as int,
    openActionsCount: j['open_actions_count']! as int,
    categories: (j['categories']! as Json).map(
      (k, v) => MapEntry(k, v! as int),
    ),
  );
  final int totalEmailsProcessed;
  final int unsubscribedCount;
  final int trashedCount;
  final int projectUpdatesCount;
  final int notificationsSentCount;
  final int openActionsCount;
  final Map<String, int> categories;
}

enum ScanStatus { running, succeeded, failed, abandoned }

class ScanRun {
  const ScanRun({
    required this.id,
    required this.trigger,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.processedCount = 0,
    this.skippedCount = 0,
    this.summary = const {},
    this.error,
  });
  factory ScanRun.fromJson(Json j) => ScanRun(
    id: j['id']! as int,
    trigger: j['trigger']! as String,
    status: ScanStatus.values.byName(j['status']! as String),
    startedAt: _date(j['started_at'])!,
    finishedAt: _date(j['finished_at']),
    processedCount: j['processed_count'] as int? ?? 0,
    skippedCount: j['skipped_count'] as int? ?? 0,
    summary: j['summary'] as Json? ?? const {},
    error: j['error'] as String?,
  );
  final int id;
  final String trigger;
  final ScanStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int processedCount;
  final int skippedCount;
  final Json summary;
  final String? error;

  bool get isRunning => status == ScanStatus.running;
}

class RuntimeSettings {
  const RuntimeSettings({
    required this.dryRun,
    required this.autoUnsubscribe,
    required this.autoDeleteMarketing,
    required this.autoMarkReadProcessed,
    required this.notifyOnProjectUpdates,
    required this.notifyOnUrgent,
    required this.minUrgencyToNotify,
    required this.protectedDomains,
    required this.projectKeywords,
  });
  factory RuntimeSettings.fromJson(Json j) => RuntimeSettings(
    dryRun: j['dry_run']! as bool,
    autoUnsubscribe: j['auto_unsubscribe']! as bool,
    autoDeleteMarketing: j['auto_delete_marketing']! as bool,
    autoMarkReadProcessed: j['auto_mark_read_processed']! as bool,
    notifyOnProjectUpdates: j['notify_on_project_updates']! as bool,
    notifyOnUrgent: j['notify_on_urgent']! as bool,
    minUrgencyToNotify: j['min_urgency_to_notify']! as int,
    protectedDomains: (j['protected_domains']! as List<Object?>).cast<String>(),
    projectKeywords: (j['project_keywords']! as List<Object?>).cast<String>(),
  );
  final bool dryRun;
  final bool autoUnsubscribe;
  final bool autoDeleteMarketing;
  final bool autoMarkReadProcessed;
  final bool notifyOnProjectUpdates;
  final bool notifyOnUrgent;
  final int minUrgencyToNotify;
  final List<String> protectedDomains;
  final List<String> projectKeywords;
}

/// Partial update for PATCH /api/settings. Only non-null fields are sent.
class RuntimeSettingsPatch {
  const RuntimeSettingsPatch({
    this.dryRun,
    this.autoUnsubscribe,
    this.autoDeleteMarketing,
    this.autoMarkReadProcessed,
    this.notifyOnProjectUpdates,
    this.notifyOnUrgent,
    this.minUrgencyToNotify,
    this.protectedDomains,
    this.projectKeywords,
  });
  final bool? dryRun;
  final bool? autoUnsubscribe;
  final bool? autoDeleteMarketing;
  final bool? autoMarkReadProcessed;
  final bool? notifyOnProjectUpdates;
  final bool? notifyOnUrgent;
  final int? minUrgencyToNotify;
  final List<String>? protectedDomains;
  final List<String>? projectKeywords;

  Json toJson() => {
    'dry_run': ?dryRun,
    'auto_unsubscribe': ?autoUnsubscribe,
    'auto_delete_marketing': ?autoDeleteMarketing,
    'auto_mark_read_processed': ?autoMarkReadProcessed,
    'notify_on_project_updates': ?notifyOnProjectUpdates,
    'notify_on_urgent': ?notifyOnUrgent,
    'min_urgency_to_notify': ?minUrgencyToNotify,
    'protected_domains': ?protectedDomains,
    'project_keywords': ?projectKeywords,
  };
}

class SystemStatus {
  const SystemStatus({
    required this.version,
    required this.serverTime,
    required this.mailbox,
    required this.llmProvider,
    required this.llmModel,
    required this.scanRunning,
    required this.settings,
    this.lastScan,
    this.latestBriefingId,
  });
  factory SystemStatus.fromJson(Json j) => SystemStatus(
    version: j['version']! as String,
    serverTime: _date(j['server_time'])!,
    mailbox: j['mailbox']! as String,
    llmProvider: j['llm_provider']! as String,
    llmModel: j['llm_model']! as String,
    scanRunning: j['scan_running']! as bool,
    lastScan: j['last_scan'] == null
        ? null
        : ScanRun.fromJson(j['last_scan']! as Json),
    latestBriefingId: j['latest_briefing_id'] as int?,
    settings: RuntimeSettings.fromJson(j['settings']! as Json),
  );
  final String version;
  final DateTime serverTime;
  final String mailbox;
  final String llmProvider;
  final String llmModel;
  final bool scanRunning;
  final ScanRun? lastScan;
  final int? latestBriefingId;
  final RuntimeSettings settings;
}

class Briefing {
  const Briefing({
    required this.id,
    required this.period,
    required this.title,
    required this.summary,
    required this.bodyMarkdown,
    required this.source,
    required this.createdAt,
  });
  factory Briefing.fromJson(Json j) => Briefing(
    id: j['id']! as int,
    period: j['period']! as String,
    title: j['title']! as String,
    summary: j['summary']! as String,
    bodyMarkdown: j['body_markdown']! as String,
    source: j['source']! as String,
    createdAt: _date(j['created_at'])!,
  );
  final int id;
  final String period;
  final String title;
  final String summary;
  final String bodyMarkdown;
  final String source;
  final DateTime createdAt;

  /// "Morning" / "Evening" / "Briefing".
  String get periodLabel => switch (period) {
    'morning' => 'Morning',
    'evening' => 'Evening',
    _ => 'Briefing',
  };
}
