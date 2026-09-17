# Smriti — Backend & Web App Build Guide

**Target:** Supabase (Postgres + Auth + Storage + Edge Functions) · React web app
**Region:** `ap-south-1` (Mumbai) — set at project creation, cannot be changed
**Audience:** Full-stack engineer, or an AI coding agent executing top to bottom

This document is self-contained. It defines every table, policy, function, endpoint, and route. Two companion specs exist and are referenced but not duplicated: the **Elder App Spec** (Flutter/Drift, defines what the tablet sends) and the **ML Spec** (defines the analysis job and derived views).

---

## 0. System overview

```
┌────────────────────┐              ┌────────────────────┐
│  ELDER TABLET      │              │  CAREGIVER WEB     │
│  Flutter + SQLite  │              │  React + Vite      │
│                    │              │                    │
│  WRITES: events,   │              │  WRITES: people,   │
│   sessions,        │              │   medications,     │
│   reminder_events, │              │   routine, config  │
│   memos,           │              │                    │
│   escalations      │              │  READS: everything │
│  READS: content    │              │                    │
└─────────┬──────────┘              └─────────┬──────────┘
          │ upsert(onConflict:id)             │ PostgREST + Realtime
          └───────────────┬───────────────────┘
                          ▼
        ┌─────────────────────────────────────────┐
        │  SUPABASE POSTGRES                      │
        │                                         │
        │  RLS: patient_members drives all access │
        │  Triggers: content_version auto-bump    │
        │  Views: derived report signals          │
        │  pg_cron: watchdog · analysis · decay   │
        └────────┬──────────────────────┬─────────┘
                 │                      │
     ┌───────────▼──────────┐  ┌────────▼─────────┐
     │  EDGE FUNCTIONS      │  │  ANALYSIS JOB    │
     │  pairing (2)         │  │  Python, nightly │
     │  escalation-worker   │  │  (ML engineer)   │
     │  twilio-webhook      │  └──────────────────┘
     │  watchdog            │
     │  ocr-prescription    │
     │  generate-report     │
     └──────────┬───────────┘
                │
      ┌─────────▼─────────┐
      │  Twilio  ·  Vapi  │
      └───────────────────┘
```

### The two invariants

**1. Single-writer ownership.** Every table has exactly one writer. Web writes content. Tablet writes events. Server writes derived data. This is why there is no conflict-resolution code anywhere in this system.

**2. Idempotency by primary key.** Every row the tablet sends carries a client-generated UUID as its PK, and every upload uses `ON CONFLICT DO NOTHING`. Re-uploading after a failed local flag write is a no-op.

### Ownership matrix

| Table | Writer | Readers |
|---|---|---|
| `patients`, `patient_members` | web (caregiver) | all |
| `people`, `medications`, `routine_items`, `escalation_config` | **web only** | web, tablet |
| `events`, `sessions`, `reminder_events`, `memos` | **tablet only** | web, analysis |
| `escalations` | tablet creates, server updates | server |
| `flags`, `ability_mirror`, `bandit_state` | **server only** | web |
| `reports`, `audit_log` | server only | web |

---

## 1. Project setup

### 1.1 Repo structure

```
smriti/
├── supabase/
│   ├── config.toml
│   ├── migrations/
│   │   ├── 0001_extensions.sql
│   │   ├── 0002_core.sql
│   │   ├── 0003_content.sql
│   │   ├── 0004_events.sql
│   │   ├── 0005_derived.sql
│   │   ├── 0006_rls_helpers.sql
│   │   ├── 0007_rls_policies.sql
│   │   ├── 0008_rpcs.sql
│   │   ├── 0009_triggers.sql
│   │   ├── 0010_views.sql
│   │   ├── 0011_storage.sql
│   │   └── 0012_cron.sql
│   ├── seed.sql
│   └── functions/
│       ├── _shared/
│       │   ├── supabase.ts
│       │   ├── cors.ts
│       │   ├── twilio.ts
│       │   └── types.ts
│       ├── redeem-pairing-token/
│       ├── pair-device-authenticated/
│       ├── create-pairing-token/
│       ├── escalation-worker/
│       ├── twilio-webhook/
│       ├── watchdog/
│       ├── ocr-prescription/
│       └── generate-report/
├── web/
│   ├── src/
│   └── package.json
├── packages/shared/          # types + zod schemas, imported by web AND functions
└── analysis/                 # ML engineer's Python
```

### 1.2 Environment

```bash
# web/.env.local
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=

# supabase secrets (never in files)
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=...
supabase secrets set TWILIO_ACCOUNT_SID=...
supabase secrets set TWILIO_AUTH_TOKEN=...
supabase secrets set TWILIO_PHONE_NUMBER=...
supabase secrets set VAPI_API_KEY=...
supabase secrets set VAPI_ASSISTANT_ID=...
supabase secrets set VAPI_PHONE_NUMBER_ID=...
supabase secrets set ANTHROPIC_API_KEY=...
supabase secrets set INTERNAL_CRON_SECRET=...
```

> **Never expose the service-role key to the browser.** The previous project's critical defect was using a browser-visible key for all writes with no RLS. Anon key in the browser is fine — but only because RLS is on.

### 1.3 Local development

```bash
supabase init
supabase start              # full Postgres + Auth + Storage in Docker
supabase db reset           # replay all migrations from scratch
supabase functions serve
```

---

## 2. Schema

### 0001_extensions.sql

```sql
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
create extension if not exists pg_cron;
create extension if not exists pg_net;
```

### 0002_core.sql

```sql
-- ─────────────── PATIENTS ───────────────
create table patients (
  id                  uuid primary key default gen_random_uuid(),
  display_name        text not null,
  age                 int  not null check (age between 30 and 120),
  education_years     int  not null default 8 check (education_years between 0 and 25),
  lang_code           text not null default 'en',
  script              text not null default 'latin',
  timezone            text not null default 'Asia/Kolkata',

  -- content sync
  content_version     int  not null default 1,
  lang_pack_version   int  not null default 1,

  -- device binding (one patient, one active device)
  device_user_id      uuid,
  device_last_seen_at timestamptz,
  device_pending_events int default 0,
  device_app_version  text,
  clock_skew_ms       bigint default 0,

  consent_given_at    timestamptz,
  active_flag_count   int not null default 0,

  created_by          uuid references auth.users(id),
  created_at          timestamptz not null default now(),
  archived_at         timestamptz
);

-- ─────────────── MEMBERSHIP (the access model) ───────────────
create table patient_members (
  patient_id uuid not null references patients(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null check (role in ('caregiver','family_viewer','health_worker')),
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (patient_id, user_id)
);

-- critical for RLS performance: every policy check hits this index
create index patient_members_user_idx on patient_members (user_id, patient_id);

-- ─────────────── PAIRING ───────────────
create table pairing_tokens (
  token       text primary key,             -- 8 chars, unambiguous alphabet
  patient_id  uuid not null references patients(id) on delete cascade,
  created_by  uuid not null references auth.users(id),
  expires_at  timestamptz not null,
  consumed    boolean not null default false,
  consumed_at timestamptz,
  attempts    int not null default 0,
  created_at  timestamptz not null default now()
);
create index on pairing_tokens (patient_id, expires_at);

-- ─────────────── AUDIT ───────────────
create table audit_log (
  id         bigserial primary key,
  patient_id uuid references patients(id) on delete cascade,
  actor      uuid,
  action     text not null,
  detail     jsonb,
  created_at timestamptz not null default now()
);
create index on audit_log (patient_id, created_at desc);
```

### 0003_content.sql

All four tables are web-owned. A trigger auto-bumps `patients.content_version` on any change — the web app never manages versioning manually.

```sql
create table people (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references patients(id) on delete cascade,
  name           text not null,
  relationship   text not null,
  photo_path     text not null,             -- storage path, NOT a URL
  voice_path     text,
  memory_prompt  text,
  is_deceased    boolean not null default false,
  sort_order     int not null default 0,
  created_at     timestamptz not null default now()
);
create index on people (patient_id, sort_order);

create table medications (
  id               uuid primary key default gen_random_uuid(),
  patient_id       uuid not null references patients(id) on delete cascade,
  name             text not null,
  dose             text not null,
  pill_photo_path  text,
  voice_path       text,

  -- minutes from midnight, integers. NEVER a time type.
  -- (the previous project used `time` + string comparison and broke nightly at 23:55)
  window_start_min int not null check (window_start_min between 0 and 1439),
  window_end_min   int not null check (window_end_min   between 0 and 1439),
  chosen_time_min  int not null check (chosen_time_min  between 0 and 1439),

  days_of_week     text not null default '1,2,3,4,5,6,7',
  active           boolean not null default true,
  created_at       timestamptz not null default now(),

  constraint chosen_within_window check (
    chosen_time_min >= window_start_min and chosen_time_min <= window_end_min
  )
);
create index on medications (patient_id) where active;

create table routine_items (
  id          uuid primary key default gen_random_uuid(),
  patient_id  uuid not null references patients(id) on delete cascade,
  time_min    int not null check (time_min between 0 and 1439),
  label_key   text not null,
  icon_asset  text not null,
  created_at  timestamptz not null default now()
);
create index on routine_items (patient_id, time_min);

create table escalation_config (
  patient_id      uuid primary key references patients(id) on delete cascade,
  steps           jsonb not null default
    '[{"step":0,"minutes":0,"channel":"in_app"},
      {"step":1,"minutes":15,"channel":"in_app"},
      {"step":2,"minutes":30,"channel":"call"},
      {"step":3,"minutes":50,"channel":"call"},
      {"step":4,"minutes":75,"channel":"sms_primary"},
      {"step":5,"minutes":180,"channel":"sms_secondary"}]'::jsonb,
  primary_name    text not null,
  primary_phone   text not null,            -- E.164
  secondary_name  text,
  secondary_phone text,
  updated_at      timestamptz not null default now()
);
```

> **`chosen_within_window` is a database-level guarantee that the bandit cannot move a dose outside medically permitted timing.** Point at it when asked about clinical safety.

### 0004_events.sql

Tablet-owned, append-only, enforced by RLS. Columns mirror the Drift schema exactly.

```sql
create table sessions (
  id             uuid primary key,                 -- CLIENT-generated
  patient_id     uuid not null references patients(id) on delete cascade,
  started_at     bigint not null,                  -- device epoch ms
  ended_at       bigint,
  game_ids       text not null,
  completed      boolean not null default false,
  abandoned_at_ms bigint,
  demo_replays   int not null default 0,
  server_received_at timestamptz not null default now()
);
create index on sessions (patient_id, started_at desc);

create table events (
  id              uuid primary key,                -- CLIENT-generated
  patient_id      uuid not null references patients(id) on delete cascade,
  session_id      uuid not null,
  game_id         text not null,
  domain          text not null
                  check (domain in ('memory','attention','executive','visuospatial','language')),

  item_id         text not null,                   -- per-item trajectories & savings
  item_difficulty real not null,
  theta_before    real not null,
  correct         boolean not null,

  initiation_ms   int not null,                    -- executive initiation
  movement_ms     int not null,                    -- motor speed
  response_time_ms int not null,

  chosen_id       text,
  error_class     text,                            -- semantic|random|perseverative|
                                                   -- repeat_selection|omission|mirror|
                                                   -- rotation|detail|sequence_error|
                                                   -- item_error|miss|false_alarm
  trial_index     int not null,
  trial_context   text,                            -- post_switch|first_exposure|
                                                   -- repeat_exposure|delayed_recall
  hint_level      int not null default 0,
  metrics         jsonb,

  ts              bigint not null,
  hour_of_day     int not null,
  tz_offset_min   int not null,
  server_received_at timestamptz not null default now()
);

-- indexes the report page depends on
create index events_patient_ts        on events (patient_id, ts desc);
create index events_patient_domain_ts on events (patient_id, domain, ts desc);
create index events_patient_item      on events (patient_id, item_id);
create index events_session_trial     on events (session_id, trial_index);
create index events_patient_game      on events (patient_id, game_id, session_id);
create index events_metrics_gin       on events using gin (metrics jsonb_path_ops);
create index events_delayed_recall    on events (patient_id, item_id)
                                      where trial_context = 'delayed_recall';

create table reminder_events (
  id             uuid primary key,                 -- client OR server generated
  patient_id     uuid not null references patients(id) on delete cascade,
  medication_id  uuid not null,
  scheduled_at   bigint not null,
  fired_at       bigint,
  responded_at   bigint,
  outcome        text check (outcome in ('confirmed','declined','no_response')),
  channel        text not null check (channel in ('in_app','call','sms','watchdog')),
  ladder_step    int not null,
  server_received_at timestamptz not null default now()
);
create index on reminder_events (patient_id, scheduled_at desc);
create index on reminder_events (patient_id, medication_id, scheduled_at);

create table memos (
  id           uuid primary key,
  patient_id   uuid not null references patients(id) on delete cascade,
  storage_path text not null,
  duration_ms  int not null,
  recorded_at  bigint not null,
  context_tag  text,
  transcript   text,
  read_at      timestamptz,
  server_received_at timestamptz not null default now()
);
create index on memos (patient_id, recorded_at desc);

create table escalations (
  id                text primary key,              -- "{reminderEventId}_{step}"
  patient_id        uuid not null references patients(id) on delete cascade,
  reminder_event_id uuid,
  medication_id     uuid,
  step              int not null,
  status            text not null default 'requested'
                    check (status in ('requested','executing','completed','cancelled','failed')),
  reason            text,
  twilio_sid        text,
  requested_at      bigint not null,
  executed_at       timestamptz,
  source            text not null default 'device' check (source in ('device','watchdog')),
  created_at        timestamptz not null default now()
);
create index on escalations (status, created_at) where status = 'requested';
create index on escalations (patient_id, created_at desc);
```

### 0005_derived.sql

Server-owned. No client writes.

```sql
create table ability_mirror (
  patient_id  uuid not null references patients(id) on delete cascade,
  domain      text not null,
  theta       real not null,
  n_trials    int  not null,
  rt_mean_log real,
  rt_var      real,
  updated_at  timestamptz not null default now(),
  primary key (patient_id, domain)
);

create table flags (
  id                  uuid primary key default gen_random_uuid(),
  patient_id          uuid not null references patients(id) on delete cascade,
  type                text not null
                      check (type in ('decline','engagement_drop','adherence_drop',
                                      'device_offline','pattern_mismatch')),
  domains             text[] not null default '{}',
  severity            text not null check (severity in ('info','moderate','high')),
  changepoint_date    date,
  z_scores            jsonb,
  evidence_session_ids uuid[],
  baseline_window     daterange,
  recent_window       daterange,
  confidence          real,
  status              text not null default 'active'
                      check (status in ('active','acknowledged','resolved')),
  created_at          timestamptz not null default now(),
  acknowledged_by     uuid references auth.users(id),
  acknowledged_at     timestamptz
);
create index on flags (patient_id, status, created_at desc);

create table bandit_state (
  medication_id uuid primary key references medications(id) on delete cascade,
  patient_id    uuid not null references patients(id) on delete cascade,
  posteriors    jsonb not null default '{}'::jsonb,   -- {"morning_weekday__510":{"a":4.2,"b":1.8}}
  last_decay_at timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table reports (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references patients(id) on delete cascade,
  storage_path text not null,
  months       int not null,
  generated_by uuid references auth.users(id),
  created_at   timestamptz not null default now()
);
```

---

## 3. RLS

> **Every table gets RLS enabled in the same migration that creates it.** Supabase does not do this for you. This was the previous project's critical defect C4.

### 0006_rls_helpers.sql

```sql
-- SECURITY DEFINER bypasses RLS on patient_members, which is what prevents
-- infinite recursion when patient_members' own policy needs a membership check.
create or replace function public.patient_role(p uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from patient_members
  where patient_id = p and user_id = (select auth.uid())
  limit 1;
$$;

create or replace function public.is_member(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from patient_members
    where patient_id = p and user_id = (select auth.uid())
  );
$$;

create or replace function public.is_caregiver(p uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from patient_members
    where patient_id = p and user_id = (select auth.uid()) and role = 'caregiver'
  );
$$;

-- the tablet's identity: app_metadata is signed into the JWT and
-- cannot be modified by the client
create or replace function public.is_device(p uuid)
returns boolean language sql stable as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'patient_id')::uuid = p
    and coalesce((auth.jwt() -> 'app_metadata' ->> 'is_device')::boolean, false),
    false
  );
$$;

create or replace function public.can_read(p uuid)
returns boolean language sql stable as $$
  select public.is_member(p) or public.is_device(p);
$$;
```

> **Always wrap `auth.uid()` as `(select auth.uid())` inside policies.** Bare, it evaluates once per row; wrapped, once per statement. On a 6,000-row event scan that's the difference between instant and unusable.

### 0007_rls_policies.sql

```sql
alter table patients          enable row level security;
alter table patient_members   enable row level security;
alter table people            enable row level security;
alter table medications       enable row level security;
alter table routine_items     enable row level security;
alter table escalation_config enable row level security;
alter table events            enable row level security;
alter table sessions          enable row level security;
alter table reminder_events   enable row level security;
alter table memos             enable row level security;
alter table escalations       enable row level security;
alter table flags             enable row level security;
alter table ability_mirror    enable row level security;
alter table bandit_state      enable row level security;
alter table reports           enable row level security;
alter table pairing_tokens    enable row level security;
alter table audit_log         enable row level security;

-- ── patients ──
create policy p_read   on patients for select using (can_read(id));
create policy p_insert on patients for insert with check ((select auth.uid()) is not null);
create policy p_update on patients for update using (is_caregiver(id));

-- ── patient_members — direct check, no helper, avoids recursion ──
create policy pm_read_own on patient_members for select
  using (user_id = (select auth.uid()) or is_caregiver(patient_id));
create policy pm_write on patient_members for insert
  with check (is_caregiver(patient_id) or user_id = (select auth.uid()));
create policy pm_delete on patient_members for delete
  using (is_caregiver(patient_id));

-- ── content: web writes, tablet reads. Never the reverse. ──
create policy c_read_people   on people for select using (can_read(patient_id));
create policy c_write_people  on people for all
  using (is_caregiver(patient_id)) with check (is_caregiver(patient_id));

create policy c_read_meds  on medications for select using (can_read(patient_id));
create policy c_write_meds on medications for all
  using (is_caregiver(patient_id)) with check (is_caregiver(patient_id));

create policy c_read_routine  on routine_items for select using (can_read(patient_id));
create policy c_write_routine on routine_items for all
  using (is_caregiver(patient_id)) with check (is_caregiver(patient_id));

create policy c_read_esc  on escalation_config for select using (can_read(patient_id));
create policy c_write_esc on escalation_config for all
  using (is_caregiver(patient_id)) with check (is_caregiver(patient_id));

-- ── events: device inserts only. Immutable, enforced at the database. ──
create policy e_insert on events for insert with check (is_device(patient_id));
create policy e_read   on events for select using (is_member(patient_id));
create policy e_no_update on events for update using (false);
create policy e_no_delete on events for delete using (false);

create policy s_insert on sessions for insert with check (is_device(patient_id));
create policy s_update on sessions for update using (is_device(patient_id));
create policy s_read   on sessions for select using (is_member(patient_id));
create policy s_no_delete on sessions for delete using (false);

create policy re_insert on reminder_events for insert with check (is_device(patient_id));
create policy re_read   on reminder_events for select using (is_member(patient_id));
create policy re_no_update on reminder_events for update using (false);
create policy re_no_delete on reminder_events for delete using (false);

create policy m_insert on memos for insert with check (is_device(patient_id));
create policy m_read   on memos for select using (is_member(patient_id));
create policy m_update on memos for update using (is_caregiver(patient_id))
  with check (is_caregiver(patient_id));           -- read_at only, enforced in app
create policy m_no_delete on memos for delete using (false);

create policy esc_insert on escalations for insert with check (is_device(patient_id));
create policy esc_read   on escalations for select using (is_caregiver(patient_id));
create policy esc_no_update on escalations for update using (false);  -- service role only

-- ── derived: read-only to everyone; service role bypasses RLS ──
create policy f_read on flags for select using (is_member(patient_id));
create policy f_ack  on flags for update using (is_caregiver(patient_id))
  with check (is_caregiver(patient_id));
create policy f_no_insert on flags for insert with check (false);

create policy am_read on ability_mirror for select using (is_member(patient_id));
create policy am_no_write on ability_mirror for all using (false) with check (false);

create policy bs_no_access on bandit_state for all using (false) with check (false);

create policy r_read on reports for select using (is_member(patient_id));
create policy r_no_write on reports for insert with check (false);

create policy pt_no_access on pairing_tokens for all using (false) with check (false);

create policy al_read on audit_log for select using (is_caregiver(patient_id));
create policy al_no_write on audit_log for insert with check (false);
```

**Role matrix — what the web app must reflect:**

| | caregiver | family_viewer | device |
|---|---|---|---|
| Patient profile | R/W | R | R |
| Content (people, meds) | **R/W** | R | R |
| Events, sessions | R | R | **Insert** |
| Voice memos | R | R | **Insert** |
| Flags | R + acknowledge | R | ✗ |
| Escalations | R | ✗ | Insert |
| Reports | Generate | Download | ✗ |

---

## 4. Triggers

### 0009_triggers.sql

```sql
-- ─── content version auto-bump ───
-- The web app does plain CRUD. Versioning is automatic and cannot be forgotten.
create or replace function bump_content_version()
returns trigger language plpgsql security definer set search_path = public as $$
declare pid uuid;
begin
  pid := coalesce(new.patient_id, old.patient_id);
  update patients set content_version = content_version + 1 where id = pid;
  return coalesce(new, old);
end $$;

create trigger t_bump_people    after insert or update or delete on people
  for each row execute function bump_content_version();
create trigger t_bump_meds      after insert or update or delete on medications
  for each row execute function bump_content_version();
create trigger t_bump_routine   after insert or update or delete on routine_items
  for each row execute function bump_content_version();
create trigger t_bump_esc       after insert or update on escalation_config
  for each row execute function bump_content_version();

-- ─── seed chosen_time_min from window start ───
create or replace function default_chosen_time()
returns trigger language plpgsql as $$
begin
  if new.chosen_time_min is null then
    new.chosen_time_min := new.window_start_min;
  end if;
  return new;
end $$;
create trigger t_default_chosen before insert on medications
  for each row execute function default_chosen_time();

-- ─── ability mirror ───
create or replace function update_ability_mirror()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into ability_mirror (patient_id, domain, theta, n_trials, updated_at)
  values (new.patient_id, new.domain, new.theta_before, 1, now())
  on conflict (patient_id, domain) do update
    set theta = excluded.theta,
        n_trials = ability_mirror.n_trials + 1,
        updated_at = now();
  return new;
end $$;
create trigger t_ability_mirror after insert on events
  for each row execute function update_ability_mirror();

-- ─── flag count denormalization ───
create or replace function sync_flag_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update patients set active_flag_count = (
    select count(*) from flags
    where patient_id = coalesce(new.patient_id, old.patient_id) and status = 'active'
  ) where id = coalesce(new.patient_id, old.patient_id);
  return coalesce(new, old);
end $$;
create trigger t_flag_count after insert or update or delete on flags
  for each row execute function sync_flag_count();
```

> **Never write a trigger on `events` that inserts into `events`.** That is an infinite loop with a real bill attached. `update_ability_mirror` writes only to `ability_mirror`.

---

## 5. RPCs

### 0008_rpcs.sql

```sql
-- ═══ Called by the TABLET on every content pull ═══
create or replace function get_patient_content(p_patient_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare result jsonb;
begin
  if not (is_device(p_patient_id) or is_member(p_patient_id)) then
    raise exception 'access denied';
  end if;

  select jsonb_build_object(
    'version',           p.content_version,
    'lang_code',         p.lang_code,
    'script',            p.script,
    'timezone',          p.timezone,
    'lang_pack_version', p.lang_pack_version,
    'elder_name',        p.display_name,
    'age',               p.age,
    'education_years',   p.education_years,

    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pe.id, 'name', pe.name, 'relationship', pe.relationship,
        'photo_path', pe.photo_path, 'voice_path', pe.voice_path,
        'memory_prompt', pe.memory_prompt, 'is_deceased', pe.is_deceased,
        'sort_order', pe.sort_order) order by pe.sort_order)
      from people pe where pe.patient_id = p.id), '[]'::jsonb),

    'medications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'dose', m.dose,
        'pill_photo_path', m.pill_photo_path, 'voice_path', m.voice_path,
        'window_start_min', m.window_start_min, 'window_end_min', m.window_end_min,
        'chosen_time_min', m.chosen_time_min, 'days_of_week', m.days_of_week,
        'active', m.active))
      from medications m where m.patient_id = p.id and m.active), '[]'::jsonb),

    'routine', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'time_min', r.time_min,
        'label_key', r.label_key, 'icon_asset', r.icon_asset) order by r.time_min)
      from routine_items r where r.patient_id = p.id), '[]'::jsonb),

    'escalation', (
      select jsonb_build_object(
        'steps', ec.steps,
        'primary_name', ec.primary_name, 'primary_phone', ec.primary_phone,
        'secondary_name', ec.secondary_name, 'secondary_phone', ec.secondary_phone)
      from escalation_config ec where ec.patient_id = p.id)
  ) into result
  from patients p where p.id = p_patient_id;

  return result;
end $$;

-- ═══ Called by the TABLET on every successful sync ═══
create or replace function device_heartbeat(
  p_patient_id uuid, p_app_version text,
  p_pending_events int, p_device_time_ms bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare server_ms bigint; skew bigint;
begin
  if not is_device(p_patient_id) then raise exception 'device only'; end if;

  server_ms := (extract(epoch from now()) * 1000)::bigint;
  skew := p_device_time_ms - server_ms;

  update patients set
    device_last_seen_at   = now(),
    device_app_version    = p_app_version,
    device_pending_events = p_pending_events,
    clock_skew_ms         = skew
  where id = p_patient_id;

  return jsonb_build_object('server_time_ms', server_ms, 'clock_skew_ms', skew);
end $$;

-- ═══ Web: create a patient + membership + defaults atomically ═══
create or replace function create_patient(
  p_name text, p_age int, p_education int, p_lang text,
  p_timezone text default 'Asia/Kolkata',
  p_primary_name text default null, p_primary_phone text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid; uid uuid;
begin
  uid := (select auth.uid());
  if uid is null then raise exception 'not authenticated'; end if;

  insert into patients (display_name, age, education_years, lang_code, timezone, created_by)
  values (p_name, p_age, p_education, p_lang, p_timezone, uid)
  returning id into new_id;

  insert into patient_members (patient_id, user_id, role) values (new_id, uid, 'caregiver');

  insert into escalation_config (patient_id, primary_name, primary_phone)
  values (new_id, coalesce(p_primary_name,'Caregiver'), coalesce(p_primary_phone,''));

  return new_id;
end $$;

-- ═══ Web: overview row per patient — powers the multi-patient landing ═══
set check_function_bodies = off;
create or replace function my_patients_overview()
returns table (
  patient_id uuid, display_name text, role text,
  played_today boolean, session_minutes numeric,
  meds_scheduled int, meds_confirmed int,
  active_flags int, unread_memos int,
  device_last_seen_at timestamptz, device_status text
) language sql stable security definer set search_path = public as $$
  with mine as (
    select pm.patient_id, pm.role from patient_members pm
    where pm.user_id = (select auth.uid())
  )
  select
    p.id, p.display_name, mine.role,
    coalesce(dr.played, false),
    coalesce(dr.minutes_played, 0),
    coalesce(dr.scheduled, 0)::int,
    coalesce(dr.confirmed, 0)::int,
    p.active_flag_count,
    (select count(*)::int from memos m
      where m.patient_id = p.id and m.read_at is null),
    p.device_last_seen_at,
    case
      when p.device_last_seen_at is null then 'never'
      when p.device_last_seen_at < now() - interval '72 hours' then 'offline'
      when p.device_last_seen_at < now() - interval '24 hours' then 'stale'
      else 'ok'
    end
  from mine
  join patients p on p.id = mine.patient_id and p.archived_at is null
  left join daily_report dr
    on dr.patient_id = p.id
   and dr.day = (now() at time zone p.timezone)::date;
$$;

set check_function_bodies = on;
-- ═══ Web: invite by phone ═══
create or replace function invite_member(
  p_patient_id uuid, p_phone text, p_role text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare target uuid;
begin
  if not is_caregiver(p_patient_id) then raise exception 'caregiver only'; end if;
  if p_role not in ('family_viewer','caregiver') then raise exception 'bad role'; end if;

  select id into target from auth.users where phone = p_phone;
  if target is null then
    return jsonb_build_object('status','pending','message','no account yet');
  end if;

  insert into patient_members (patient_id, user_id, role, invited_by)
  values (p_patient_id, target, p_role, (select auth.uid()))
  on conflict (patient_id, user_id) do update set role = excluded.role;

  return jsonb_build_object('status','added');
end $$;
```

---

## 6. The report layer

### 0010_views.sql

Computed on read. **They can never drift from source**, which matters when a village syncs four days late — Monday's row is simply correct the next time anyone queries it. A trigger-maintained table would have silently lost that increment.

```sql
-- ─── per patient, per day: play ───
create or replace view daily_play with (security_invoker = true) as
select
  e.patient_id,
  (to_timestamp(e.ts/1000.0) at time zone p.timezone)::date as day,
  count(distinct e.session_id)                     as sessions,
  count(*)                                          as trials,
  round(avg(e.correct::int)::numeric, 3)            as accuracy,
  round(avg(e.response_time_ms))                    as mean_rt_ms,
  round(avg(e.initiation_ms))                       as mean_initiation_ms,
  round(avg(e.movement_ms))                         as mean_movement_ms,
  round(stddev(e.response_time_ms))                 as rt_variability,
  round(avg(e.hint_level)::numeric, 2)              as mean_hint_level,
  count(*) filter (where e.error_class = 'perseverative')    as perseverations,
  count(*) filter (where e.error_class = 'repeat_selection') as repeat_errors,
  count(*) filter (where e.error_class = 'semantic')         as semantic_errors,
  max(e.item_difficulty)                            as peak_difficulty,
  array_agg(distinct e.game_id)                     as games_played
from events e join patients p on p.id = e.patient_id
group by 1,2;

-- ─── per domain ───
create or replace view daily_domain with (security_invoker = true)as
select
  e.patient_id,
  (to_timestamp(e.ts/1000.0) at time zone p.timezone)::date as day,
  e.domain,
  count(*)                                as trials,
  round(avg(e.correct::int)::numeric, 3)  as accuracy,
  round(avg(e.theta_before)::numeric, 3)  as mean_theta,
  round(avg(e.response_time_ms))          as mean_rt_ms,
  round(stddev(e.response_time_ms))       as rt_variability
from events e join patients p on p.id = e.patient_id
group by 1,2,3;

-- ─── sessions ───
create or replace view daily_sessions with (security_invoker = true) as
select
  s.patient_id,
  (to_timestamp(s.started_at/1000.0) at time zone p.timezone)::date as day,
  count(*)                                                     as sessions,
  round(sum(coalesce(s.ended_at, s.started_at) - s.started_at)/60000.0, 1) as minutes_played,
  count(*) filter (where not s.completed)                      as abandoned,
  sum(s.demo_replays)                                          as demo_replays
from sessions s join patients p on p.id = s.patient_id
group by 1,2;

-- ─── adherence ───
create or replace view daily_adherence with (security_invoker = true) as
select
  r.patient_id,
  (to_timestamp(r.scheduled_at/1000.0) at time zone p.timezone)::date as day,
  count(*)                                                  as scheduled,
  count(*) filter (where r.outcome = 'confirmed')           as confirmed,
  count(*) filter (where r.outcome='confirmed' and r.channel='in_app') as via_tablet,
  count(*) filter (where r.outcome='confirmed' and r.channel='call')   as via_call,
  count(*) filter (where r.outcome = 'no_response')         as missed
from reminder_events r join patients p on p.id = r.patient_id
group by 1,2;

-- ─── THE view the dashboard reads ───
create or replace view daily_report with (security_invoker = true) as
select
  coalesce(pl.patient_id, ad.patient_id) as patient_id,
  coalesce(pl.day, ad.day)               as day,
  (pl.trials is not null)                as played,
  se.minutes_played, se.sessions, se.abandoned, se.demo_replays,
  pl.trials, pl.accuracy, pl.mean_rt_ms, pl.mean_initiation_ms,
  pl.mean_movement_ms, pl.rt_variability, pl.mean_hint_level,
  pl.perseverations, pl.repeat_errors, pl.semantic_errors,
  pl.peak_difficulty, pl.games_played,
  ad.scheduled, ad.confirmed, ad.via_tablet, ad.via_call, ad.missed
from daily_play pl
full outer join daily_adherence ad using (patient_id, day)
left  join daily_sessions se using (patient_id, day);
```

> The `full outer join` matters: a day where she took her medicines but didn't play still needs a row, and so does the reverse.

**The ML engineer owns the deeper signal views** — post-error slowing, across-session savings, per-person recognition trajectories, delayed-recall savings, sundowning. Those go in `0013_report_views.sql`. Backend creates the indexes above; ML writes the queries.

---

## 7. Storage

### 0011_storage.sql

```sql
insert into storage.buckets (id, name, public) values
  ('patient-media', 'patient-media', false),
  ('patient-memos', 'patient-memos', false),
  ('lang-packs',    'lang-packs',    false),
  ('reports',       'reports',       false)
on conflict do nothing;

-- path convention: {patient_id}/{filename}
create policy media_read on storage.objects for select
  using (bucket_id = 'patient-media'
         and can_read(((storage.foldername(name))[1])::uuid));

create policy media_write on storage.objects for insert
  with check (bucket_id = 'patient-media'
    and is_caregiver(((storage.foldername(name))[1])::uuid)
    and (metadata->>'size')::int < 5242880);

create policy memo_read on storage.objects for select
  using (bucket_id = 'patient-memos'
         and is_member(((storage.foldername(name))[1])::uuid));

create policy memo_write on storage.objects for insert
  with check (bucket_id = 'patient-memos'
    and is_device(((storage.foldername(name))[1])::uuid)
    and (metadata->>'size')::int < 10485760);

create policy lang_read on storage.objects for select
  using (bucket_id = 'lang-packs' and auth.role() = 'authenticated');

create policy report_read on storage.objects for select
  using (bucket_id = 'reports'
         and is_member(((storage.foldername(name))[1])::uuid));
```

**Store paths, never URLs.** URLs expire and leak; the tablet resolves paths with its own credentials.

---

## 8. Edge Functions

### 8.1 `create-pairing-token`

```
POST  { patient_id }                            [caregiver JWT]
→     { token: "SMRTK4PQ", expires_at }
```

```typescript
const ALPHABET = 'ACDEFGHJKLMNPQRSTUVWXYZ2345679'; // no I O 0 1 8 B

function generateCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, b => ALPHABET[b % ALPHABET.length]).join('');
}
```

Verify caregiver membership. TTL 30 minutes — longer than a QR, because a code travels by voice. Insert into `pairing_tokens`. The web app renders it both as text (`SMRT-K4PQ`) and as a QR encoding the same token.

### 8.2 `redeem-pairing-token`

```
POST  { token }                                 [anon]
→     { refresh_token, patient_id, device_user_id, lang_code,
        elder_name, age, education_years }
```

```typescript
// 1. rate limit BEFORE lookup — codes are guessable in principle
const { data: tok } = await admin.from('pairing_tokens')
  .select('*').eq('token', token.toUpperCase().replace(/-/g,'')).single();

if (!tok)                          return err(404, 'invalid');
if (tok.attempts >= 5)             return err(429, 'locked');
if (tok.consumed)                  return err(409, 'already used');
if (new Date(tok.expires_at) < new Date()) return err(410, 'expired');

await admin.from('pairing_tokens')
  .update({ attempts: tok.attempts + 1 }).eq('token', tok.token);

// 2. revoke any existing device for this patient
const { data: patient } = await admin.from('patients')
  .select('*').eq('id', tok.patient_id).single();

if (patient.device_user_id) {
  await admin.auth.admin.deleteUser(patient.device_user_id);
  await admin.from('audit_log').insert({
    patient_id: tok.patient_id, action: 'device_replaced',
    detail: { old: patient.device_user_id },
  });
  await sendSms(escalation.primary_phone,
    `A new tablet was set up for ${patient.display_name} today.`);
}

// 3. create the device auth user
const email = `device.${tok.patient_id}.${crypto.randomUUID()}@smriti.internal`;
const password = crypto.randomUUID() + crypto.randomUUID();

const { data: created } = await admin.auth.admin.createUser({
  email, password, email_confirm: true,
  app_metadata: { is_device: true, patient_id: tok.patient_id },
});

// 4. sign in to obtain a session, return the refresh token
const anon = createClient(SUPABASE_URL, ANON_KEY);
const { data: session } = await anon.auth.signInWithPassword({ email, password });

// 5. bind + consume
await admin.from('patients')
  .update({ device_user_id: created.user.id }).eq('id', tok.patient_id);
await admin.from('pairing_tokens')
  .update({ consumed: true, consumed_at: new Date() }).eq('token', tok.token);

return json({
  refresh_token: session.session.refresh_token,
  patient_id: tok.patient_id,
  device_user_id: created.user.id,
  lang_code: patient.lang_code,
  elder_name: patient.display_name,
  age: patient.age,
  education_years: patient.education_years,
});
```

> `app_metadata` is signed into the JWT and cannot be modified by the client. That is why RLS can trust `is_device()`.

### 8.3 `pair-device-authenticated`

```
POST  { patient_id }                            [caregiver JWT]
→     same payload as 8.2
```

Verify `is_caregiver(patient_id)` server-side, then run the identical device-creation path. **The tablet calls `signOut()` immediately after** — it must never retain caregiver credentials, since it sits unattended in a village home for years.

### 8.4 `escalation-worker`

Triggered by a Database Webhook on `escalations` insert (`status = 'requested'`), and by `pg_cron` as a sweep for anything stuck.

```typescript
// ── 1. RE-CHECK: the elder may have confirmed offline, synced late
const { data: re } = await admin.from('reminder_events')
  .select('outcome').eq('id', esc.reminder_event_id).maybeSingle();

if (re?.outcome === 'confirmed') {
  await markCancelled(esc.id, 'already_confirmed');
  return ok();
}

// ── 2. GATHER: all unconfirmed meds in [now-15, now+30]
//     ONE call per patient, never one call per pill.
const nowMin = minutesOfDayInTz(patient.timezone);
const due = await unconfirmedMedsInWindow(patient.id, nowMin - 15, nowMin + 30);
if (due.length === 0) { await markCancelled(esc.id, 'nothing_due'); return ok(); }

// ── 3. EXECUTE
switch (esc.step) {
  case 2: case 3: await placeCall(patient, due, esc); break;
  case 4: await sendSms(cfg.primary_phone,   smsBody(patient, due, cfg.lang)); break;
  case 5: await sendSms(cfg.secondary_phone, smsBody(patient, due, cfg.lang)); break;
}

// ── 4. NEXT STEP: schedule via pg_cron-checked delay row
if (esc.step < 5) await queueNextStep(esc, cfg.steps);
```

**Window arithmetic must be modulo 1440.** The previous project compared `time` values as formatted strings and broke nightly at 23:55 (defect H2). Integers and `mod` make that impossible.

```typescript
function inWindow(t: number, lo: number, hi: number): boolean {
  lo = ((lo % 1440) + 1440) % 1440;
  hi = ((hi % 1440) + 1440) % 1440;
  return lo <= hi ? (t >= lo && t <= hi) : (t >= lo || t <= hi);
}
```

**Twilio call:**

```typescript
const tier = LANG_TIER[patient.lang_code] ?? 'dtmf';
const medAudio = await signedUrl('patient-media', due[0].voice_path, 3600);
const promptUrl = await signedUrl('lang-packs',
  `${patient.lang_code}/press_any_key.mp3`, 3600);

const twiml = tier === 'conversational'
  ? `<Response>
       <Play>${medAudio}</Play>
       <Connect><Stream url="${VAPI_WS}?p=${patient.id}&amp;e=${esc.id}"/></Connect>
     </Response>`
  : `<Response>
       <Play>${medAudio}</Play>
       <Gather numDigits="1" timeout="8"
               action="${FN_URL}/twilio-webhook?p=${patient.id}&amp;e=${esc.id}">
         <Play>${promptUrl}</Play>
       </Gather>
       <Redirect>${FN_URL}/twilio-webhook?p=${patient.id}&amp;e=${esc.id}&amp;noanswer=1</Redirect>
     </Response>`;
```

| Language | Tier | Mechanism |
|---|---|---|
| Hindi | conversational | Vapi agent |
| Assamese | conversational | Vapi, DTMF fallback |
| Meiteilon, Khasi, Mizo | dtmf | Recorded audio + "press any key" |

DTMF is language-agnostic and works on a feature phone. Present the tiering as a deliberate design decision, not a limitation.

**Medication list phrasing** uses a per-language conjunction so the voice model receives naturally-phrased text:

```typescript
const CONJ = { hi: ', aur ', as: ', আৰু ', mni: ', অমসুং ', en: ', and ' };
const list = due.map(m => `${m.dose} ${m.name}`).join(CONJ[lang] ?? CONJ.en);
```

**Degraded mode:** if Twilio or Vapi credentials are absent, compute and return the full call plan, mark the escalation `failed` with `reason: 'no_credentials'`, and log it. The previous project returned `200 success:true` while silently placing no calls (defect H4) — surface it in the response body, not just the log.

**Dispatch with `Promise.allSettled`**, never a sequential `await` loop (defect M12).

### 8.5 `twilio-webhook`

```typescript
// ── Signature verification is MANDATORY ──
// (previous project defect C3: anyone could POST and mark meds taken)
const sig = req.headers.get('x-twilio-signature');
if (!validateTwilioSignature(TWILIO_AUTH_TOKEN, sig, fullUrl, formBody)) {
  return new Response('forbidden', { status: 403 });
}
```

Implement HMAC-SHA1 over `url + sorted(params)` per Twilio's spec, using Web Crypto in Deno.

On a keypress or a Vapi `took_medication = true`:

```typescript
await admin.from('reminder_events').insert(due.map(m => ({
  id: crypto.randomUUID(),
  patient_id, medication_id: m.id,
  scheduled_at: m.scheduled_at,
  fired_at: Date.now(), responded_at: Date.now(),
  outcome: 'confirmed', channel: 'call', ladder_step: esc.step,
})));

await admin.from('escalations')
  .update({ status: 'cancelled', reason: 'confirmed_by_call' })
  .eq('patient_id', patient_id).eq('status', 'requested');
```

**Vapi's structured output is keyed by opaque UUIDs, not field names.** This cost the previous team real debugging time:

```typescript
let taken: boolean | null = null;
const outputs = body?.message?.artifact?.structuredOutputs ?? {};
for (const k of Object.keys(outputs)) {
  if (outputs[k]?.name === 'took_medication') taken = outputs[k].result;
}
// legacy shape — Vapi changed this mid-build once already
if (taken === null) taken = body?.message?.analysis?.structuredData?.took_medication ?? null;
if (typeof taken !== 'boolean') return ok();   // never write a non-boolean
```

Log every inbound payload during development.

**Required Vapi assistant configuration (out-of-band, not in this repo):**
- Template variables `{{patient_name}}`, `{{medications_list}}`
- Structured output field named exactly `took_medication`, typed boolean
- Server webhook URL pointing at this function

### 8.6 `watchdog` — the safety net

**This is the function that exists because the tablet can fail silently.** If the tablet is dead, offline for days, or its alarm was killed by an OEM battery manager, no escalation is ever written and the elder receives nothing. The watchdog computes what *should* have fired and checks whether it did.

Runs every 10 minutes via `pg_cron`.

```typescript
const GRACE_MIN = 45;   // longer than the device's own T+30 escalation,
                        // so we never race the device path

for (const patient of activePatients) {
  const nowMin = minutesOfDayInTz(patient.timezone);
  const today  = dateInTz(patient.timezone);
  const dow    = dayOfWeekInTz(patient.timezone);

  for (const med of patient.medications.filter(m => m.active)) {
    if (!med.days_of_week.split(',').includes(String(dow))) continue;

    const overdueBy = mod1440(nowMin - med.chosen_time_min);
    if (overdueBy < GRACE_MIN || overdueBy > 240) continue;

    const scheduledMs = epochForTz(patient.timezone, today, med.chosen_time_min);

    const { count } = await admin.from('reminder_events')
      .select('id', { count: 'exact', head: true })
      .eq('patient_id', patient.id)
      .eq('medication_id', med.id)
      .gte('scheduled_at', scheduledMs - 300_000)
      .lte('scheduled_at', scheduledMs + 300_000);

    if (count && count > 0) continue;     // device handled it

    // deterministic ID — overlapping sweeps CANNOT double-call
    const id = `wd_${patient.id}_${today}_${med.chosen_time_min}`;
    await admin.from('escalations').insert({
      id, patient_id: patient.id, medication_id: med.id,
      step: 2, status: 'requested', source: 'watchdog',
      requested_at: Date.now(),
    }).select().maybeSingle();            // conflict → already handled
  }
}

// ── device health is a SEPARATE alert, not a missed dose ──
for (const p of patients) {
  const hours = hoursSince(p.device_last_seen_at);
  if (hours > 24 && !(await hasActiveFlag(p.id, 'device_offline'))) {
    await raiseFlag(p.id, 'device_offline', hours > 72 ? 'high' : 'moderate');
    await sendSms(cfg.primary_phone,
      `${p.display_name}'s tablet hasn't connected in ${Math.floor(hours)} hours.`);
  }
}
```

### 8.7 `ocr-prescription`

```
POST  { image_base64, patient_id }              [caregiver JWT]
→     { medications: [{ name, dose, frequency, confidence, raw_text }] }
```

Pipeline: Claude vision with structured JSON output → strip markdown fences defensively → normalize frequency notation (BD/TDS/QID/SOS/HS) via **lookup table, not the model** → fuzzy-match every drug name against a bundled Indian drug list → **reject anything scoring below 0.85 as `unrecognized`**.

The drug-database match is the safety mechanism that prevents a hallucinated medication reaching a schedule.

> **The function never writes to `medications`.** It returns candidates. The web UI requires per-row caregiver confirmation before anything is inserted. The previous project's own blueprint calls this "the single most consequential improvement available" (defect M17) — unreviewed LLM output currently drives real phone calls about real medicine. Protect this when the schedule tightens.

### 8.8 `generate-report`

```
POST  { patient_id, months }                    [caregiver JWT]
→     { signed_url, report_id }
```

Server-side rendering, not client-side — the clinician page needs deterministic layout.

**Page 1 (caregiver):** domain trajectories with the person's own ±1 SD band, changepoints marked, adherence, engagement, plain-language summary.

**Page 2 (clinician):** the instrument mapping. This is the page a doctor actually reads.

| Game | Instrument | Reported as |
|---|---|---|
| Market Basket | Word span | Forward 5, backward 3 |
| Trace the Path | TMT A / B | B−A: 34s → 61s |
| Sort the Harvest | Card sorting | Perseverative errors 1.2 → 3.8/session |
| My Day | MMSE orientation | 4/5 |
| Name the Harvest | Category fluency | 15 → 11 items/60s |
| Lamps of the Festival | Corsi span | Forward 5, backward 3 |
| Delayed probe | Savings score | 0.71 → 0.42 |

Footer on both pages: *"This is a record of home-based activity over time. It is not a clinical assessment and does not replace examination."*

---

## 9. Scheduled jobs

### 0012_cron.sql

```sql
-- watchdog: every 10 minutes
select cron.schedule('smriti-watchdog', '*/10 * * * *', $$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/watchdog',
    headers := jsonb_build_object('x-internal-secret',
      current_setting('app.cron_secret', true)),
    body := '{}'::jsonb);
$$);

-- stuck escalations: every 5 minutes
select cron.schedule('smriti-escalation-sweep', '*/5 * * * *', $$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/escalation-worker',
    headers := jsonb_build_object('x-internal-secret',
      current_setting('app.cron_secret', true)),
    body := jsonb_build_object('mode','sweep'));
$$);

-- nightly analysis (ML engineer's job): 02:00 IST = 20:30 UTC
select cron.schedule('smriti-analysis', '30 20 * * *', $$
  select net.http_post(
    url := 'https://<analysis-host>/run',
    headers := jsonb_build_object('x-internal-secret',
      current_setting('app.cron_secret', true)),
    body := '{}'::jsonb);
$$);

-- bandit decay: weekly, Sunday 03:00 IST
select cron.schedule('smriti-bandit-decay', '30 21 * * 0', $$
  update bandit_state
  set posteriors = (
        select jsonb_object_agg(k,
          jsonb_build_object('a', (v->>'a')::numeric * 0.99,
                             'b', (v->>'b')::numeric * 0.99))
        from jsonb_each(posteriors) as t(k,v)),
      last_decay_at = now()
  where last_decay_at < now() - interval '7 days';
$$);

-- keep the project awake (free tier pauses after ~1 week idle)
select cron.schedule('smriti-keepalive', '0 */6 * * *', $$ select 1; $$);
```

> Every internal endpoint checks `x-internal-secret` against `INTERNAL_CRON_SECRET`. The previous project's `trigger-call` was publicly triggerable.

---

## 10. Web app

### 10.1 Stack

React 18 + Vite + TypeScript · Tailwind + shadcn/ui · TanStack Query · Recharts · React Router v6 · react-hook-form + zod · vite-plugin-pwa

### 10.2 Routes

```
/                          → redirect by patient count
/auth                      → phone + OTP
/patients                  → overview (only rendered when >1)
/patients/new              → create + setup wizard
/p/:pid/dashboard          → "is Ma okay today"
/p/:pid/trends             → domain trajectories + flags
/p/:pid/report             → THE DEEP REPORT PAGE (the moat)
/p/:pid/engagement         → calendar heatmap, adherence
/p/:pid/messages           → voice memo inbox
/p/:pid/manage/people
/p/:pid/manage/medicines
/p/:pid/manage/routine
/p/:pid/manage/alerts
/p/:pid/manage/access      → invite family
/p/:pid/manage/device      → pairing, sync status
/p/:pid/care-guide
```

**The patient ID lives in the URL, always.** Not in React state alone. This gives bookmarkable pages and a working back button, but the real reason is safety — see 10.5.

**Adaptive landing.** One patient → straight to their dashboard, no multi-patient chrome at all. More than one → overview. Most caregivers have one patient and should never see the switcher.

### 10.3 Data layer

```typescript
// src/lib/db.ts — the ONLY file importing @supabase/supabase-js
export const patientsOverview = () => supabase.rpc('my_patients_overview');
export const contentPeople    = (pid) => supabase.from('people').select('*').eq('patient_id', pid);
export const dailyReport      = (pid, from) => supabase.from('daily_report')
                                  .select('*').eq('patient_id', pid).gte('day', from);
export const activeFlags      = (pid) => supabase.from('flags')
                                  .select('*').eq('patient_id', pid).eq('status','active');
// NOTE: no export selects from `events` directly.
// The report page reads views. A raw-event query in the web app is a bug.
```

**Realtime — one subscription for all patients:**

```typescript
supabase.channel('caregiver-feed')
  .on('postgres_changes',
      { event: '*', schema: 'public', table: 'patients' },
      p => updateOverview(p.new))
  .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'flags' },
      p => showFlagToast(p.new))
  .subscribe();
```

RLS applies to realtime payloads, so the stream is filtered server-side. **Never filter by patient ID on the client** — a client-side filter bug is a data leak.

```sql
alter publication supabase_realtime add table patients;
alter publication supabase_realtime add table flags;
alter publication supabase_realtime add table memos;
```

### 10.4 The report page — seven sections

1. **Summary** — generated prose. What changed, when, which domains, evidence linked. This is what Bina reads.
2. **Domain trajectories** — five smoothed lines, her own ±1 SD band shaded, changepoints marked.
3. **Speed & consistency** — initiation latency and movement time as separate series, with RT variability alongside. Often the first line to move.
4. **Error profile** — stacked area of error classes as a proportion. Rising perseverations under flat total accuracy is immediately legible.
5. **Support needed** — mean hint level, hint rescue rate, demo replays.
6. **People** — small multiples, one sparkline per family member, sorted by decline. **The most emotionally powerful screen in the product**, and entirely dependent on `item_id` being captured.
7. **Instrument mapping** — the clinician page.

### 10.5 Cross-patient leakage guards

A caregiver managing both parents, and a stale cache renders her father's medication list under her mother's name. In a medication app that is a safety failure, not a cosmetic bug.

```typescript
// 1. EVERY query key carries the patient ID
useQuery({ queryKey: ['trends', pid, days], ... })   // never ['trends']

// 2. clear scoped caches on switch
function switchPatient(next: string) {
  queryClient.removeQueries({ queryKey: ['trends'] });
  queryClient.removeQueries({ queryKey: ['dashboard'] });
  queryClient.removeQueries({ queryKey: ['report'] });
  navigate(`/p/${next}/dashboard`);
}

// 3. persistent identity header — photo + name, every screen, never a dropdown

// 4. assert on render (dev only)
if (import.meta.env.DEV && data?.patient_id !== pid) {
  throw new Error(`patient mismatch: ${data.patient_id} vs ${pid}`);
}
```

### 10.6 Media upload

```typescript
const compressed = kind === 'photo'
  ? await imageCompression(file, { maxSizeMB: 0.2, maxWidthOrHeight: 800 })
  : file;

const path = `${pid}/${crypto.randomUUID()}.${ext(file)}`;
await supabase.storage.from('patient-media').upload(path, compressed);
return path;   // store the PATH — never a URL
```

**Upload and confirm before writing the path into `people` or `medications`.** Writing a path to an incomplete upload means the tablet 404s and aborts its entire content pull.

Compress on the client — Imphal mobile data is not free, and the tablet has to download whatever you upload.

### 10.7 The medicine form

```
Medicine window:  8:00 AM ──────●────── 9:30 AM
"We'll find the time in this window when she responds best.
 We never move a medicine outside the window you set."
```

Then: record the reminder in the caregiver's own voice, and photograph the actual pill.

OCR results render with per-row confidence badges, low-confidence rows in amber, and **Save disabled until every row is individually ticked.**

---

## 11. Build order

| # | Task | Days | Unblocks |
|---|---|---|---|
| 1 | Project, migrations 0001–0007, local stack | 1 | Everything |
| 2 | Shared types + zod package | 0.5 | Web + Functions |
| 3 | Auth (phone OTP), `create_patient`, membership | 1 | Web |
| 4 | Content CRUD + version trigger + `get_patient_content` | 1 | **Tablet team** |
| 5 | Pairing: all three paths, device JWT | 1.5 | **Tablet team** |
| 6 | Setup wizard (people, photos, voice, meds) | 2 | Demo content |
| 7 | **ML: synthetic cohort seeder** | 1 | **Entire dashboard build** |
| 8 | Dashboard + overview + realtime | 1.5 | |
| 9 | Views 0010, indexes, report page §1/2/7 | 2 | The moat |
| 10 | Escalation worker + Twilio + webhook | 2 | Demo phone call |
| 11 | **Watchdog + device health** | 1 | Safety net |
| 12 | Trends, flags, "see the evidence" | 1.5 | |
| 13 | Report sections 3–6 | 1.5 | |
| 14 | Bandit | 1 | |
| 15 | OCR + medicine management | 1.5 | |
| 16 | Report PDF | 1 | Demo close |
| 17 | Multi-patient, access management | 1 | |
| 18 | Seed and **freeze demo project** | 0.5 | |

**Items 4 and 5 are the tablet team's blockers. Do them before anything visual.**

**Item 7 is the highest-leverage task in the whole backend** — realistic 6-month histories for four personas let the entire dashboard and report page be built and demoed without waiting for real gameplay.

---

## 12. Non-negotiables

1. **Every `create table` is followed by `alter table … enable row level security` in the same migration.**
2. **`auth.uid()` is always wrapped as `(select auth.uid())` inside policies.**
3. **No trigger on `events` may write to `events`.**
4. **All device uploads use `on_conflict=id` with duplicates ignored.**
5. **Escalation IDs are `{reminderEventId}_{step}` or `wd_{patient}_{date}_{slot}`. Always deterministic.**
6. **Every webhook verifies its signature before writing anything.**
7. **All time-of-day arithmetic is integer minutes, modulo 1440. Never a `time` type, never string comparison.**
8. **The bandit's chosen time never leaves the caregiver window — enforced by the `chosen_within_window` check constraint.**
9. **OCR never writes to `medications`. It returns candidates for per-row confirmation.**
10. **Media uploads complete and are confirmed before their path is written to content.**
11. **One escalation call per patient covering all due medicines — never one call per pill.**
12. **The web app never queries `events` directly. Views only.**
13. **All Supabase access lives in `src/lib/db.ts`. One file to audit.**
14. **Service-role key never reaches the browser.**
15. **`ap-south-1`, decided on day one, permanent.**