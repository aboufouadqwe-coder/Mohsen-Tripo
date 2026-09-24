create index if not exists projects_owner_id_idx
  on public.projects(owner_id);

create index if not exists projects_template_id_idx
  on public.projects(template_id)
  where template_id is not null;

create index if not exists asset_templates_owner_id_idx
  on public.asset_templates(owner_id)
  where owner_id is not null;
