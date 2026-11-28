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
}
