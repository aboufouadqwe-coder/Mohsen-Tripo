create extension if not exists pgcrypto with schema extensions;

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  reference_image_path text,
  template_id uuid,
  identity_prompt text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.asset_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  description text not null default '',
  is_builtin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((is_builtin and owner_id is null) or (not is_builtin and owner_id is not null))
);

alter table public.projects
  add constraint projects_template_id_fkey
  foreign key (template_id)
  references public.asset_templates(id)
  on delete set null;

create table public.template_parts (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.asset_templates(id) on delete cascade,
  key text not null check (char_length(trim(key)) between 1 and 120),
  label text not null check (char_length(trim(label)) between 1 and 160),
  prompt_fragment text not null default '',
  sort_order integer not null default 0 check (sort_order >= 0),
  enabled_by_default boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_id, key)
);

create table public.generation_jobs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  part_key text,
  provider text not null,
  operation text not null check (
    operation in ('text_to_image', 'image_to_image', 'image_to_model')
  ),
  provider_task_id text,
  status text not null default 'queued' check (
    status in ('queued', 'running', 'success', 'failed', 'cancelled')
  ),
  progress double precision not null default 0 check (progress >= 0 and progress <= 1),
  request_payload_redacted jsonb not null default '{}'::jsonb,
  error_code text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index generation_jobs_project_id_idx
  on public.generation_jobs(project_id);

create index generation_jobs_provider_task_id_idx
  on public.generation_jobs(provider_task_id)
  where provider_task_id is not null;

create table public.asset_results (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  generation_job_id uuid not null references public.generation_jobs(id) on delete cascade,
  part_key text,
  storage_path text not null check (char_length(trim(storage_path)) > 0),
  mime_type text not null check (char_length(trim(mime_type)) > 0),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  created_at timestamptz not null default now()
);

create index asset_results_project_id_idx
  on public.asset_results(project_id);

create index asset_results_generation_job_id_idx
  on public.asset_results(generation_job_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger projects_set_updated_at
before update on public.projects
for each row execute function public.set_updated_at();

create trigger asset_templates_set_updated_at
before update on public.asset_templates
for each row execute function public.set_updated_at();

create trigger template_parts_set_updated_at
before update on public.template_parts
for each row execute function public.set_updated_at();

create trigger generation_jobs_set_updated_at
before update on public.generation_jobs
for each row execute function public.set_updated_at();

alter table public.projects enable row level security;
alter table public.asset_templates enable row level security;
alter table public.template_parts enable row level security;
alter table public.generation_jobs enable row level security;
alter table public.asset_results enable row level security;

grant usage on schema public to authenticated;

grant select, insert, update, delete
  on public.projects, public.asset_templates, public.template_parts
  to authenticated;

grant select
  on public.generation_jobs, public.asset_results
  to authenticated;

grant select, insert, update, delete
  on public.projects,
     public.asset_templates,
     public.template_parts,
     public.generation_jobs,
     public.asset_results
  to service_role;

create policy "projects_select_own"
on public.projects for select
to authenticated
using ((select auth.uid()) = owner_id);

create policy "projects_insert_own"
on public.projects for insert
to authenticated
with check ((select auth.uid()) = owner_id);

create policy "projects_update_own"
on public.projects for update
to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

create policy "projects_delete_own"
on public.projects for delete
to authenticated
using ((select auth.uid()) = owner_id);

create policy "asset_templates_select_visible"
on public.asset_templates for select
to authenticated
using (
  is_builtin = true
  or (select auth.uid()) = owner_id
);

create policy "asset_templates_insert_own_custom"
on public.asset_templates for insert
to authenticated
with check (
  is_builtin = false
  and (select auth.uid()) = owner_id
);

create policy "asset_templates_update_own_custom"
on public.asset_templates for update
to authenticated
using (
  is_builtin = false
  and (select auth.uid()) = owner_id
)
with check (
  is_builtin = false
  and (select auth.uid()) = owner_id
);

create policy "asset_templates_delete_own_custom"
on public.asset_templates for delete
to authenticated
using (
  is_builtin = false
  and (select auth.uid()) = owner_id
);

create policy "template_parts_select_visible"
on public.template_parts for select
to authenticated
using (
  exists (
    select 1
    from public.asset_templates t
    where t.id = template_parts.template_id
      and (
        t.is_builtin = true
        or t.owner_id = (select auth.uid())
      )
  )
);

create policy "template_parts_insert_own_custom"
on public.template_parts for insert
to authenticated
with check (
  exists (
    select 1
    from public.asset_templates t
    where t.id = template_parts.template_id
      and t.is_builtin = false
      and t.owner_id = (select auth.uid())
  )
);

create policy "template_parts_update_own_custom"
on public.template_parts for update
to authenticated
using (
  exists (
    select 1
    from public.asset_templates t
    where t.id = template_parts.template_id
      and t.is_builtin = false
      and t.owner_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.asset_templates t
    where t.id = template_parts.template_id
      and t.is_builtin = false
      and t.owner_id = (select auth.uid())
  )
);

create policy "template_parts_delete_own_custom"
on public.template_parts for delete
to authenticated
using (
  exists (
    select 1
    from public.asset_templates t
    where t.id = template_parts.template_id
      and t.is_builtin = false
      and t.owner_id = (select auth.uid())
  )
);

create policy "generation_jobs_select_own"
on public.generation_jobs for select
to authenticated
using (
  exists (
    select 1
    from public.projects p
    where p.id = generation_jobs.project_id
      and p.owner_id = (select auth.uid())
  )
);

create policy "asset_results_select_own"
on public.asset_results for select
to authenticated
using (
  exists (
    select 1
    from public.projects p
    where p.id = asset_results.project_id
      and p.owner_id = (select auth.uid())
  )
);

insert into storage.buckets (id, name, public)
values
  ('reference-images', 'reference-images', false),
  ('generated-images', 'generated-images', false),
  ('generated-models', 'generated-models', false)
on conflict (id) do update
set public = excluded.public;

create policy "mohsen_storage_select_own"
on storage.objects for select
to authenticated
using (
  bucket_id in ('reference-images', 'generated-images', 'generated-models')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "mohsen_storage_insert_own"
on storage.objects for insert
to authenticated
with check (
  bucket_id in ('reference-images', 'generated-images', 'generated-models')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "mohsen_storage_update_own"
on storage.objects for update
to authenticated
using (
  bucket_id in ('reference-images', 'generated-images', 'generated-models')
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id in ('reference-images', 'generated-images', 'generated-models')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "mohsen_storage_delete_own"
on storage.objects for delete
to authenticated
using (
  bucket_id in ('reference-images', 'generated-images', 'generated-models')
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

insert into public.asset_templates (
  id,
  owner_id,
  name,
  description,
  is_builtin
) values (
  '00000000-0000-0000-0000-000000000001',
  null,
  'Character Parts',
  'Generate consistent character-part reference images from one source.',
  true
);

insert into public.template_parts (
  id,
  template_id,
  key,
  label,
  prompt_fragment,
  sort_order,
  enabled_by_default
) values
  (
    '00000000-0000-0000-0001-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'head',
    'Head',
    'Generate the complete head clearly from the front, preserving face, hair, headwear, wounds, and bandages.',
    0,
    true
  ),
  (
    '00000000-0000-0000-0001-000000000002',
    '00000000-0000-0000-0000-000000000001',
    'right_hand',
    'Right Hand',
    'Generate the complete right hand clearly, preserving skin, damage, gloves, jewelry, and proportions.',
    1,
    true
  ),
  (
    '00000000-0000-0000-0001-000000000003',
    '00000000-0000-0000-0000-000000000001',
    'left_hand',
    'Left Hand',
    'Generate the complete left hand clearly, preserving skin, damage, gloves, jewelry, and proportions.',
    2,
    true
  ),
  (
    '00000000-0000-0000-0001-000000000004',
    '00000000-0000-0000-0000-000000000001',
    'right_foot',
    'Right Foot',
    'Generate the complete right foot clearly, including the exact footwear or visible foot design.',
    3,
    true
  ),
  (
    '00000000-0000-0000-0001-000000000005',
    '00000000-0000-0000-0000-000000000001',
    'left_foot',
    'Left Foot',
    'Generate the complete left foot clearly, including the exact footwear or visible foot design.',
    4,
    true
  ),
  (
    '00000000-0000-0000-0001-000000000006',
    '00000000-0000-0000-0000-000000000001',
    'clothing',
    'Clothing',
    'Generate the character clothing as a clear reference, preserving material, wear, stains, tears, and colors.',
    5,
    true
  ),
  (
    '00000000-0000-0000-0001-000000000007',
    '00000000-0000-0000-0000-000000000001',
    'accessories',
    'Accessories',
    'Generate the character accessories as a clear reference, preserving their exact shapes, materials, colors, and placement language.',
    6,
    true
  );
