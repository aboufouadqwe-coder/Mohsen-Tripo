begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

select has_table('public', 'projects', 'projects table exists');
select has_table('public', 'asset_templates', 'asset_templates table exists');
select has_table('public', 'template_parts', 'template_parts table exists');
select has_table('public', 'generation_jobs', 'generation_jobs table exists');
select has_table('public', 'asset_results', 'asset_results table exists');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.projects'::regclass),
  'projects has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.asset_templates'::regclass),
  'asset_templates has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.template_parts'::regclass),
  'template_parts has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.generation_jobs'::regclass),
  'generation_jobs has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.asset_results'::regclass),
  'asset_results has RLS enabled'
);

select results_eq(
  $$ select count(*) from storage.buckets
     where id in ('reference-images', 'generated-images', 'generated-models')
       and public = false $$,
  array[3::bigint],
  'all three application buckets are private'
);

select results_eq(
  $$ select count(*) from public.template_parts tp
     join public.asset_templates t on t.id = tp.template_id
     where t.id = '00000000-0000-0000-0000-000000000001'::uuid
       and t.is_builtin = true $$,
  array[7::bigint],
  'built-in Character Parts template has seven parts'
);

select ok(
  has_table_privilege('authenticated', 'public.projects', 'SELECT')
    and has_table_privilege('authenticated', 'public.projects', 'INSERT')
    and has_table_privilege('authenticated', 'public.projects', 'UPDATE')
    and has_table_privilege('authenticated', 'public.projects', 'DELETE')
    and has_table_privilege('authenticated', 'public.asset_templates', 'SELECT')
    and has_table_privilege('authenticated', 'public.template_parts', 'SELECT')
    and has_table_privilege('authenticated', 'public.generation_jobs', 'SELECT')
    and has_table_privilege('authenticated', 'public.asset_results', 'SELECT'),
  'authenticated role has explicit Data API table grants'
);

select * from finish();
rollback;
