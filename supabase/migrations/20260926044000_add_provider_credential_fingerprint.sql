alter table public.generation_jobs
  add column if not exists provider_credential_fingerprint text;

comment on column public.generation_jobs.provider_credential_fingerprint is
  'SHA-256 fingerprint of the request-scoped Tripo API key that created the provider task. Never stores raw key material.';
