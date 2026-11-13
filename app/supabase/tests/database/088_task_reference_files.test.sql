begin;

select plan(5);

select has_column(
  'public',
  'task_files',
  'purpose',
  'task_files distinguishes reference material from deliverables'
);

select has_column(
  'public',
  'task_files_visible',
  'purpose',
  'task_files_visible exposes the non-sensitive file purpose'
);

select has_function(
  'public',
  'cmd_mark_task_file_reference',
  array['uuid','uuid','uuid','uuid','integer'],
  'reference purpose is assigned through an authoritative command'
);

select has_trigger(
  'public',
  'task_review_round_files',
  'task_review_round_files_reject_reference',
  'reference material cannot enter formal submission attachments'
);

select has_trigger(
  'public',
  'task_file_final_designations',
  'task_file_final_designations_reject_reference',
  'reference material cannot be marked as a final deliverable'
);

select * from finish();
rollback;
