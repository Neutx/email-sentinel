import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';

import '../helpers/fake_api.dart';

void main() {
  test('EmailItem parses the API fixture', () {
    final email = EmailItem.fromJson(fixtureMap('email_item'));
    expect(email.id, 1);
    expect(email.category, EmailCategory.urgentActionable);
    expect(email.urgency, 5);
    expect(email.senderName, 'Legal');
    expect(email.actionRequired, isTrue);
    expect(email.actionDescription, 'Review and respond');
    expect(email.receivedAt, isNotNull);
    expect(email.createdAt!.isUtc, isFalse, reason: 'converted to local time');
  });

  test('EmailPage exposes the pagination cursor', () {
    final page = EmailPage.fromJson(fixtureMap('email_page'));
    expect(page.items, hasLength(4));
    expect(page.nextCursor, page.items.last.id);
  });

  test('unknown categories degrade to FYI instead of crashing', () {
    expect(EmailCategory.fromWire('something_new'), EmailCategory.generalFyi);
    for (final c in EmailCategory.values) {
      expect(EmailCategory.fromWire(c.wire), c);
    }
  });

  test('every list/detail fixture parses', () {
    expect(Health.fromJson(fixtureMap('health')).status, 'ok');
    final status = SystemStatus.fromJson(fixtureMap('status'));
    expect(status.lastScan!.status, ScanStatus.succeeded);
    expect(status.settings.minUrgencyToNotify, inInclusiveRange(1, 5));
    expect(Stats.fromJson(fixtureMap('stats')).openActionsCount, isNonNegative);
    expect(AlertsResponse.fromJson(fixtureMap('alerts')).cursor, isPositive);
    expect(
      (fixture('projects')! as List<Object?>)
          .map((e) => ProjectSummary.fromJson(e! as Json))
          .first
          .name,
      'Murphy-Labs/core',
    );
    expect(
      (fixture('project_updates')! as List<Object?>).map(
        (e) => ProjectUpdate.fromJson(e! as Json),
      ),
      isNotEmpty,
    );
    expect(
      (fixture('unsubscribes')! as List<Object?>)
          .map((e) => UnsubscribeLog.fromJson(e! as Json))
          .first
          .success,
      isTrue,
    );
    expect(
      (fixture('scans')! as List<Object?>).map(
        (e) => ScanRun.fromJson(e! as Json),
      ),
      isNotEmpty,
    );
    final briefing = Briefing.fromJson(fixtureMap('briefing'));
    expect(briefing.periodLabel, 'Morning');
    expect(
      ActionResult.fromJson(fixtureMap('action_result')).email!.isDone,
      isTrue,
    );
    expect(RuntimeSettings.fromJson(fixtureMap('settings')).dryRun, isFalse);
  });

  test('RuntimeSettingsPatch only sends provided fields', () {
    expect(
      const RuntimeSettingsPatch(dryRun: true, minUrgencyToNotify: 3).toJson(),
      {'dry_run': true, 'min_urgency_to_notify': 3},
    );
  });
}
