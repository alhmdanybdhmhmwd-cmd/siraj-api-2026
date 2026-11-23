class AdminTask {
  const AdminTask({
    required this.id,
    required this.title,
    required this.status,
    this.description = '',
    this.nextAction = '',
    this.priority = 'normal',
    this.checkpointVersion = 0,
  });

  final String id;
  final String title;
  final String status;
  final String description;
  final String nextAction;
  final String priority;
  final int checkpointVersion;

  factory AdminTask.fromJson(Map<String, dynamic> json) => AdminTask(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        status: (json['status'] ?? 'queued').toString(),
        description: (json['description'] ?? '').toString(),
        nextAction:
            (json['next_action'] ?? json['nextAction'] ?? '').toString(),
        priority: (json['priority'] ?? 'normal').toString(),
        checkpointVersion: (json['checkpoint_version'] ??
            json['checkpointVersion'] ??
            0) as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status,
        'description': description,
        'next_action': nextAction,
        'priority': priority,
        'checkpoint_version': checkpointVersion,
      };
}

class AdminApproval {
  const AdminApproval({
    required this.id,
    required this.actionType,
    required this.status,
    required this.preview,
  });

  final String id;
  final String actionType;
  final String status;
  final Map<String, dynamic> preview;

  factory AdminApproval.fromJson(Map<String, dynamic> json) => AdminApproval(
        id: (json['id'] ?? '').toString(),
        actionType:
            (json['action_type'] ?? json['actionType'] ?? '').toString(),
        status: (json['status'] ?? 'pending').toString(),
        preview: Map<String, dynamic>.from(
          json['preview'] is Map ? json['preview'] as Map : const {},
        ),
      );
}

List<AdminTask> mergeOutboxDrafts(List<AdminTask> serverTasks, List<Map<String, dynamic>> pending) {
  final existingIds = serverTasks.map((task) => task.id).toSet();
  final drafts = <AdminTask>[];
  for (final item in pending) {
    final key = (item['idempotencyKey'] ?? '').toString();
    final title = (item['title'] ?? '').toString().trim();
    if (key.isEmpty || title.isEmpty) continue;
    final id = 'local-' + key;
    if (!existingIds.add(id)) continue;
    drafts.add(AdminTask(id: id, title: title, description: (item['description'] ?? '').toString(), priority: (item['priority'] ?? 'normal').toString(), status: 'draft_offline', nextAction: 'سيتم الإرسال عند عودة الاتصال'));
  }
  return [...drafts, ...serverTasks];
}
