begin;

create extension if not exists pgtap with schema extensions;

select plan(8);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'owner1@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'owner2@example.test');

insert into public.asset_templates (
  id, owner_id, name, description, is_builtin
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  'Owner 1 Template',
  'Custom',
  false
);

insert into public.projects (
  id, owner_id, name, template_id, identity_prompt
) values
  (
    '10000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'Owner 1 Project',
    '00000000-0000-0000-0000-000000000001',
    'Owner one identity'
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '22222222-2222-2222-2222-222222222222',
    'Owner 2 Project',
    '00000000-0000-0000-0000-000000000001',
    'Owner two identity'
  );

insert into public.generation_jobs (
  id, project_id, part_key, provider, operation, status, progress
) values
  (
    '30000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'head',
    'tripo',
    'image_to_image',
    'success',
    1
  ),
  (
    '30000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000002',
    'head',
    'tripo',
    'image_to_image',
    'success',
    1
  );

insert into public.asset_results (
  id, project_id, generation_job_id, part_key, storage_path, mime_type
) values
  (
    '40000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001',
    'head',
    '11111111-1111-1111-1111-111111111111/10000000-0000-0000-0000-000000000001/head.png',
    'image/png'
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000002',
    'head',
    '22222222-2222-2222-2222-222222222222/20000000-0000-0000-0000-000000000002/head.png',
    'image/png'
  );

insert into storage.objects (bucket_id, name)
values
  (
    'generated-images',
    '11111111-1111-1111-1111-111111111111/10000000-0000-0000-0000-000000000001/head.png'
  ),
  (
    'generated-images',
    '22222222-2222-2222-2222-222222222222/20000000-0000-0000-0000-000000000002/head.png'
  );

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select results_eq(
  $$ select count(*) from public.projects $$,
  array[1::bigint],
  'owner sees only their project'
);

select results_eq(
  $$ select count(*) from public.generation_jobs $$,
  array[1::bigint],
  'owner sees only jobs belonging to their project'
);

select results_eq(
  $$ select count(*) from public.asset_results $$,
  array[1::bigint],
  'owner sees only results belonging to their project'
);

select results_eq(
  $$ select count(*) from public.asset_templates
     where is_builtin = true $$,
  array[1::bigint],
  'authenticated owner can read built-in template'
);

select results_eq(
  $$ select count(*) from public.asset_templates
     where owner_id = '11111111-1111-1111-1111-111111111111'::uuid $$,
  array[1::bigint],
  'owner can read own custom template'
);

select results_eq(
  $$ select count(*) from public.projects
     where owner_id = '22222222-2222-2222-2222-222222222222'::uuid $$,
  array[0::bigint],
  'owner cannot read another user project'
);

select results_eq(
  $$ update public.projects
     set name = 'Hacked'
     where id = '20000000-0000-0000-0000-000000000002'::uuid
     returning 1 $$,
  $$ select 1 where false $$,
  'owner cannot update another user project'
);

select results_eq(
  $$ select count(*) from storage.objects
     where bucket_id = 'generated-images' $$,
  array[1::bigint],
  'storage RLS exposes only the authenticated user folder'
);

select * from finish();
rollback;
