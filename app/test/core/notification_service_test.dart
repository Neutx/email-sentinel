import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/app/routes.dart';
import 'package:sentinel/core/notifications/notification_service.dart';
import 'package:sentinel/data/models.dart';

void main() {
  final urgentEmail = EmailItem(
    id: 42,
    messageId: '<urgent@example.com>',
    sender: 'CEO <ceo@example.com>',
    senderEmail: 'ceo@example.com',
    subject: 'Urgent contract approval',
    receivedAt: DateTime.utc(2026, 9, 28, 10),
    category: EmailCategory.urgentActionable,
    urgency: 5,
    summary: 'Approve the contract immediately',
    projectName: null,
    actionRequired: true,
    actionDescription: 'Sign the contract',
    isTrashed: false,
    isUnsubscribed: false,
    isDone: false,
    reclassified: false,
    dryRun: false,
    createdAt: DateTime.utc(2026, 9, 28, 10, 5),
  );

  final projectEmail = EmailItem(
    id: 43,
    messageId: '<project@example.com>',
    sender: 'GitHub <notifications@github.com>',
    senderEmail: 'notifications@github.com',
    subject: 'PR #100 merged',
    receivedAt: DateTime.utc(2026, 9, 28, 10),
    category: EmailCategory.projectUpdate,
    urgency: 3,
    summary: 'PR 100 merged into main',
    projectName: 'Murphy-Labs/core',
    actionRequired: false,
    actionDescription: null,
    isTrashed: false,
    isUnsubscribed: false,
    isDone: false,
    reclassified: false,
    dryRun: false,
    createdAt: DateTime.utc(2026, 9, 28, 10, 5),
  );

  final emptySummaryEmail = EmailItem(
    id: 44,
    messageId: '<empty@example.com>',
    sender: 'Finance <finance@example.com>',
    senderEmail: 'finance@example.com',
    subject: 'Monthly invoice',
    receivedAt: DateTime.utc(2026, 9, 28, 10),
    category: EmailCategory.transactional,
    urgency: 2,
    summary: '',
    projectName: null,
    actionRequired: false,
    actionDescription: null,
    isTrashed: false,
    isUnsubscribed: false,
    isDone: false,
    reclassified: false,
    dryRun: false,
    createdAt: DateTime.utc(2026, 9, 28, 10, 5),
  );

  final morningBriefing = Briefing(
    id: 7,
    period: 'morning',
    title: 'Morning briefing',
    summary: 'All systems green today.',
    bodyMarkdown: '# Briefing\nAll good.',
    source: 'hermes',
    createdAt: DateTime.utc(2026, 9, 28, 8),
  );

  group('NotificationService routing and pure helpers', () {
    test(
      'channelFor routes urgent emails to urgent and others to projects',
      () {
        expect(NotificationService.channelFor(urgentEmail), 'urgent');
        expect(NotificationService.channelFor(projectEmail), 'projects');
        expect(NotificationService.channelFor(emptySummaryEmail), 'projects');
      },
    );

    test('payloadFor constructs correct email deep link', () {
      expect(NotificationService.payloadFor(urgentEmail), Routes.email(42));
      expect(NotificationService.payloadFor(projectEmail), Routes.email(43));
    });

    test('summaryNeeded requires 4 or more emails', () {
      expect(NotificationService.summaryNeeded(0), isFalse);
      expect(NotificationService.summaryNeeded(1), isFalse);
      expect(NotificationService.summaryNeeded(2), isFalse);
      expect(NotificationService.summaryNeeded(3), isFalse);
      expect(NotificationService.summaryNeeded(4), isTrue);
      expect(NotificationService.summaryNeeded(10), isTrue);
    });

    test('briefingTitle formats periodLabel in lowercase', () {
      expect(
        NotificationService.briefingTitle(morningBriefing),
        'Your morning briefing is ready',
      );
    });

    test('emailTitle formats category and senderName', () {
      expect(NotificationService.emailTitle(urgentEmail), 'Urgent · CEO');
      expect(NotificationService.emailTitle(projectEmail), 'Project · GitHub');
    });

    test('emailBody prefers summary and falls back to subject', () {
      expect(
        NotificationService.emailBody(urgentEmail),
        'Approve the contract immediately',
      );
      expect(
        NotificationService.emailBody(emptySummaryEmail),
        'Monthly invoice',
      );
    });
  });
}
