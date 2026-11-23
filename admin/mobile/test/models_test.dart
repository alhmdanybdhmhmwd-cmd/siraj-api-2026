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
}
