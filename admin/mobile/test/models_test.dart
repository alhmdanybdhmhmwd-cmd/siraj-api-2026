import 'package:flutter_test/flutter_test.dart';
import 'package:barq_admin/models.dart';

void main() {
  test('AdminTask reads API snake_case and camelCase fields', () {
    final task = AdminTask.fromJson({
      'id': 'task-1',
      'title': 'Prepare BARQ launch',
      'status': 'running',
      'checkpoint_version': 4,
      'next_action': 'Review draft',
    });
    expect(task.checkpointVersion, 4);
    expect(task.nextAction, 'Review draft');
    expect(task.toJson()['status'], 'running');
  });

  test('AdminApproval safely parses preview', () {
    final approval = AdminApproval.fromJson({
      'id': 'approval-1',
      'action_type': 'public_publish',
      'status': 'pending',
      'preview': {'summary': 'Review post', 'environment': 'external'},
    });
    expect(approval.preview['summary'], 'Review post');
    expect(approval.status, 'pending');
  });

  test(
    'offline outbox drafts restore beside cached tasks and deduplicate',
    () {
      const cached = [
        AdminTask(id: 'server-1', title: 'Server task', status: 'queued'),
      ];
      final pending = [
        {'idempotencyKey': 'offline-1', 'title': '  Draft task  '},
        {'idempotencyKey': 'offline-1', 'title': 'Duplicate draft'},
        {'idempotencyKey': '', 'title': 'Invalid draft'},
        {'idempotencyKey': 'offline-2', 'title': '   '},
      ];
      final merged = mergeOutboxDrafts(cached, pending);
      expect(
        merged.map((task) => task.id).toList(),
        ['local-offline-1', 'server-1'],
      );
      expect(merged.first.title, 'Draft task');
      expect(merged.first.status, 'draft_offline');
      expect(merged.first.nextAction, 'سيتم الإرسال عند عودة الاتصال');
    },
  );

  test('offline outbox drafts retain description and priority', () {
    final merged = mergeOutboxDrafts(
      const [
        AdminTask(id: 'server-1', title: 'Server task', status: 'queued'),
      ],
      [
        {
          'idempotencyKey': 'offline-details',
          'title': 'Offline task',
          'description': 'Saved before connection returned',
          'priority': 'high',
        },
      ],
    );

    expect(merged, hasLength(2));
    expect(merged.first.id, 'local-offline-details');
    expect(merged.first.description, 'Saved before connection returned');
    expect(merged.first.priority, 'high');
    expect(merged.last.id, 'server-1');
  });

  test('outbox merge skips drafts already represented by server ids', () {
    const syncedTask = AdminTask(
      id: 'local-already-synced',
      title: 'Server copy',
      status: 'queued',
    );

    final merged = mergeOutboxDrafts(
      const [syncedTask],
      [
        {'idempotencyKey': 'already-synced', 'title': 'Stale local copy'},
        {'idempotencyKey': 'new-draft', 'title': 'New draft'},
        {'idempotencyKey': 'new-draft', 'title': 'Duplicate draft'},
      ],
    );

    expect(merged, hasLength(2));
    expect(merged.first.id, 'local-new-draft');
    expect(merged.first.title, 'New draft');
    expect(merged.last.id, 'local-already-synced');
  });


  test('outbox sync splits pending work into a small ordered batch', () {
    final pending = List<Map<String, dynamic>>.generate(
      7,
      (index) => {'idempotencyKey': 'draft-$index', 'title': 'Draft $index'},
    );

    final batch = splitOutboxBatch(pending);

    expect(
      batch.toSend.map((item) => item['idempotencyKey']).toList(),
      ['draft-0', 'draft-1', 'draft-2'],
    );
    expect(
      batch.deferred.map((item) => item['idempotencyKey']).toList(),
      ['draft-3', 'draft-4', 'draft-5', 'draft-6'],
    );
    expect(
      [...batch.toSend, ...batch.deferred],
      pending,
    );
  });

  test('outbox sync accepts a smaller custom batch and rejects zero', () {
    final pending = [
      {'idempotencyKey': 'one', 'title': 'One'},
      {'idempotencyKey': 'two', 'title': 'Two'},
    ];

    final batch = splitOutboxBatch(pending, limit: 1);
    expect(batch.toSend, [pending.first]);
    expect(batch.deferred, [pending.last]);
    expect(() => splitOutboxBatch(pending, limit: 0), throwsArgumentError);
  });

}
