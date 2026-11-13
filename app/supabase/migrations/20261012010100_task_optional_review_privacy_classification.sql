-- F2 keeps an explicit manual-review inventory of ALL columns. The new
-- boolean task policy column must be classified after it is introduced;
-- this registers it for review and does NOT approve privacy cleanup.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='tasks'
      and column_name='requires_review' and data_type='boolean'
  ) then
    raise exception 'REQUIRES_REVIEW_SCHEMA_NOT_READY';
  end if;
  insert into private.lifecycle_pii_classifications
    (schema_name,table_name,column_name,data_type,classification,disposition)
  values ('public','tasks','requires_review','boolean','structured',
          'manual_review_required')
  on conflict (schema_name,table_name,column_name) do nothing;
  if not exists (
    select 1 from private.lifecycle_pii_classifications
    where schema_name='public' and table_name='tasks'
      and column_name='requires_review' and data_type='boolean'
      and classification='structured'
      and disposition='manual_review_required'
  ) then
    raise exception 'REQUIRES_REVIEW_PRIVACY_CLASSIFICATION_MISMATCH';
  end if;
end;
$$;