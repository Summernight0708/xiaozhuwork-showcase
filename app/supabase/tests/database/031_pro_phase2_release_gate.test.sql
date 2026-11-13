begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select ok(
  (
    select bool_and(private.capability_is_released(code))
    from (
      values
        ('file_full_history'::text),
        ('file_batch_rollback'::text),
        ('file_version_compare'::text),
        ('project_recovery_point'::text),
        ('file_large_upload'::text)
    ) released(code)
  ),
  'G Stage 1 release capabilities remain published'
);

select ok(
  not private.capability_is_released('totally_unknown_capability'),
  'unknown capability remains fail closed'
);

select ok(
  not private.capability_is_released(null),
  'null capability remains fail closed'
);

select ok(
  not has_function_privilege('anon','private.capability_is_released(text)','EXECUTE'),
  'anon cannot execute the private release registry directly'
);

select ok(
  not has_function_privilege('authenticated','private.capability_is_released(text)','EXECUTE'),
  'authenticated cannot execute the private release registry directly'
);

select ok(
  not has_function_privilege('service_role','private.capability_is_released(text)','EXECUTE'),
  'service_role cannot bypass feature entrypoints by invoking the registry directly'
);

select * from finish();
rollback;
