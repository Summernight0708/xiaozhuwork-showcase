begin;

select plan(3);

select has_trigger(
  'public',
  'task_review_rounds',
  'task_review_rounds_protect_history',
  'historical review immutability trigger still exists after array backfill'
);

select is(
  (
    select tgenabled::text
    from pg_trigger
    where tgrelid='public.task_review_rounds'::regclass
      and tgname='task_review_rounds_protect_history'
      and not tgisinternal
  ),
  'O',
  'historical review immutability trigger is re-enabled after migration'
);

select ok(
  not exists (
    select 1
    from public.task_review_rounds
    where required_submission_file_types_snapshot is distinct from
      case
        when required_submission_file_type_snapshot is null then '{}'::text[]
        else array[required_submission_file_type_snapshot]::text[]
      end
  ),
  'all pre-existing review rounds have a canonical array snapshot'
);


select * from finish();

rollback;
