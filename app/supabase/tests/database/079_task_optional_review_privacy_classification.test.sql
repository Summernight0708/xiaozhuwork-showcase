begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select is(
 (select classification from private.lifecycle_pii_classifications
  where schema_name='public' and table_name='tasks'
    and column_name='requires_review'),
 'structured','new review policy field is explicitly categorized for F2 inventory'
);
select is(
 (select disposition from private.lifecycle_pii_classifications
  where schema_name='public' and table_name='tasks'
    and column_name='requires_review'),
 'manual_review_required','classification never approves privacy cleanup'
);
select is(
 (select count(*)::integer from jsonb_array_elements(private.f2_privacy_schema()->'columns') c
  where not exists (
    select 1 from private.lifecycle_pii_classifications k
    where k.schema_name=c->>'schema' and k.table_name=c->>'table'
      and k.column_name=c->>'column' and k.data_type=c->>'type'
  )),0,'F2 inventory detects no unclassified schema drift'
);
select * from finish();
rollback;