create extension if not exists pgcrypto;

create table if not exists public.clips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null,
  storage_key text not null,
  duration_s int not null,
  created_at timestamptz not null default now()
);

create table if not exists public.analysis (
  id uuid primary key default gen_random_uuid(),
  clip_id uuid not null references public.clips(id) on delete cascade,
  status text not null check (status in ('pending','processing','success','failed')),
  shot_type text null check (shot_type in ('lay_up','in_paint','mid_range','three_pointer','free_throw')),
  result text null check (result in ('make','miss')),
  confidence double precision null,
  tips_text text null,
  error_msg text null,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now()
);

create index if not exists idx_analysis_clip_id on public.analysis(clip_id);
create index if not exists idx_analysis_status on public.analysis(status);
create index if not exists idx_clips_created_at on public.clips(created_at);

-- User overrides table for scalable field corrections
create table if not exists public.analysis_overrides (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.analysis(id) on delete cascade,
  field_name text not null check (field_name in ('shot_type', 'result')),
  original_value text,
  override_value text not null,
  created_at timestamptz not null default now(),
  
  -- Ensure one active override per field per analysis
  unique(analysis_id, field_name)
);

create index if not exists idx_analysis_overrides_analysis_id on public.analysis_overrides(analysis_id);
create index if not exists idx_analysis_overrides_field on public.analysis_overrides(field_name);

-- Enable Row Level Security
alter table public.clips enable row level security;
alter table public.analysis enable row level security;
alter table public.analysis_overrides enable row level security;

-- Drop existing policies if they exist
drop policy if exists "Allow anonymous inserts on clips" on public.clips;
drop policy if exists "Allow anonymous reads on clips" on public.clips;
drop policy if exists "Allow anonymous inserts on analysis" on public.analysis;
drop policy if exists "Allow anonymous reads on analysis" on public.analysis;
drop policy if exists "Allow anonymous updates on analysis" on public.analysis;
drop policy if exists "Allow anonymous inserts on analysis_overrides" on public.analysis_overrides;
drop policy if exists "Allow anonymous reads on analysis_overrides" on public.analysis_overrides;
drop policy if exists "Allow anonymous updates on analysis_overrides" on public.analysis_overrides;

-- Allow anonymous users to insert clips
create policy "Allow anonymous inserts on clips"
  on public.clips for insert
  with check (true);

-- Allow anonymous users to read clips
create policy "Allow anonymous reads on clips"
  on public.clips for select
  using (true);

-- Allow anonymous users to insert analysis
create policy "Allow anonymous inserts on analysis"
  on public.analysis for insert
  with check (true);

-- Allow anonymous users to read analysis
create policy "Allow anonymous reads on analysis"
  on public.analysis for select
  using (true);

-- Allow anonymous users to update analysis (for status updates)
create policy "Allow anonymous updates on analysis"
  on public.analysis for update
  using (true)
  with check (true);

-- Allow anonymous users to insert analysis overrides
create policy "Allow anonymous inserts on analysis_overrides"
  on public.analysis_overrides for insert
  with check (true);

-- Allow anonymous users to read analysis overrides
create policy "Allow anonymous reads on analysis_overrides"
  on public.analysis_overrides for select
  using (true);

-- Allow anonymous users to update analysis overrides (upsert functionality)
create policy "Allow anonymous updates on analysis_overrides"
  on public.analysis_overrides for update
  using (true)
  with check (true);
