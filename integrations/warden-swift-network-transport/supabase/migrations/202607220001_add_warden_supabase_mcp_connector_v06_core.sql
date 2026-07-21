create schema if not exists warden;
revoke all on schema warden from public, anon, authenticated;
grant usage on schema warden to service_role;

create or replace function warden.constant_time_equal(p_left bytea, p_right bytea)
returns boolean language plpgsql immutable strict as $$
declare v_difference integer := 0; v_index integer;
begin
  if length(p_left) <> length(p_right) then return false; end if;
  if length(p_left) = 0 then return true; end if;
  for v_index in 0 .. length(p_left) - 1 loop
    v_difference := v_difference | (get_byte(p_left, v_index) # get_byte(p_right, v_index));
  end loop;
  return v_difference = 0;
end; $$;

create table if not exists warden.tenant_credentials (
  tenant_id uuid primary key references public.integration_tenants(id) on delete cascade,
  external_tenant_id text not null unique,
  status text not null default 'pending' check (status in ('pending','active','suspended','revoked')),
  api_key_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status <> 'active') or api_key_hash is not null)
);

create table if not exists warden.devices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.integration_tenants(id) on delete cascade,
  external_device_id text not null,
  project_id text not null,
  shell_device_id uuid references riveros.shell_devices(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','active','suspended','revoked')),
  signature_algorithm text not null default 'hmac-sha256' check (signature_algorithm in ('hmac-sha256','ed25519-sha256-digest')),
  key_id text not null,
  verification_key_b64 text,
  verification_secret_id uuid,
  last_sequence bigint not null default 0 check (last_sequence >= 0),
  last_event_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, external_device_id),
  check ((signature_algorithm = 'hmac-sha256' and verification_secret_id is not null)
    or (signature_algorithm = 'ed25519-sha256-digest' and verification_key_b64 is not null)
    or status = 'pending')
);

create table if not exists warden.event_policies (
  id uuid primary key default gen_random_uuid(), policy_ref text not null unique,
  tenant_id uuid not null references public.integration_tenants(id) on delete cascade,
  status text not null default 'active' check (status in ('active','disabled')),
  event_type text not null default '*', purpose text not null default '*',
  authority_basis text not null default '*', retention_class text not null default '*',
  decision text not null check (decision in ('allow','deny')),
  require_authority_reference boolean not null default true,
  priority integer not null default 100,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists warden.ledger_heads (
  tenant_id uuid primary key references public.integration_tenants(id) on delete cascade,
  last_sequence bigint not null default 0, last_entry_hash text,
  updated_at timestamptz not null default now()
);

create table if not exists warden.events (
  event_id text primary key,
  tenant_id uuid not null references public.integration_tenants(id) on delete restrict,
  device_id uuid not null references warden.devices(id) on delete restrict,
  project_id text not null, event_hash text not null, event_json jsonb not null,
  policy_id uuid not null references warden.event_policies(id) on delete restrict,
  receipt_id text not null unique, recorded_at timestamptz not null default now(),
  ledger_sequence bigint not null, previous_ledger_hash text, ledger_entry_hash text not null,
  unique (tenant_id, ledger_sequence)
);

create table if not exists warden.batch_receipts (
  batch_id text primary key,
  tenant_id uuid not null references public.integration_tenants(id) on delete restrict,
  device_id uuid not null references warden.devices(id) on delete restrict,
  acknowledgement jsonb not null, created_at timestamptz not null default now()
);

create table if not exists warden.typeform_webhook_events (
  event_id text primary key, form_id text not null, response_token text not null unique,
  signature text not null, raw_payload jsonb not null, normalized_payload jsonb not null,
  processing_status text not null default 'received' check (processing_status in ('received','processed','rejected','error')),
  processing_error text, received_at timestamptz not null default now(), processed_at timestamptz
);

create table if not exists warden.mcp_connector_applications (
  id uuid primary key default gen_random_uuid(),
  application_ref text not null unique default ('MCPAPP-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 20))),
  typeform_event_id text not null unique references warden.typeform_webhook_events(event_id) on delete restrict,
  form_id text not null, response_token text not null unique, external_tenant_id text,
  organization_name text not null, applicant_name text not null, applicant_email text not null,
  vsr_licence_ref text not null, licence_id uuid references vsr_registry.licences(id) on delete set null,
  requested_licence_tier text not null, connector_name text not null, provider_name text not null,
  repository_url text, manifest_url text, transport_modes text[] not null default '{}',
  deployment_model text, target_vsr_licences text[] not null default '{}',
  requested_operations text[] not null default '{}', data_classes text[] not null default '{}',
  auth_methods text[] not null default '{}', capabilities jsonb not null default '{}'::jsonb,
  submission_payload jsonb not null,
  status text not null default 'submitted' check (status in ('submitted','needs_licence_validation','under_review','changes_requested','approved','rejected','withdrawn')),
  submitted_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists warden.mcp_application_events (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references warden.mcp_connector_applications(id) on delete cascade,
  event_type text not null, actor_ref text, payload jsonb not null default '{}'::jsonb,
  previous_hash text, event_hash text not null, recorded_at timestamptz not null default now()
);

create table if not exists warden.mcp_connector_licence_bindings (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references warden.mcp_connector_applications(id) on delete restrict,
  licence_id uuid not null references vsr_registry.licences(id) on delete restrict,
  connector_instance_id uuid references public.connector_instances(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','active','suspended','revoked','expired')),
  conditions jsonb not null default '{}'::jsonb, activated_at timestamptz, expires_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create index if not exists idx_warden_events_tenant_device on warden.events(tenant_id, device_id, ledger_sequence);
create index if not exists idx_warden_policy_match on warden.event_policies(tenant_id, status, priority desc);
create index if not exists idx_mcp_connector_applications_status on warden.mcp_connector_applications(status, submitted_at desc);
create index if not exists idx_mcp_connector_applications_licence on warden.mcp_connector_applications(vsr_licence_ref);

insert into public.connector_provider_catalog (
  provider_key, kind, display_name, description, supported_auth_types,
  capabilities, configuration_schema, credential_fields, connector_mode, status
) values (
  'mcp_connector_license', 'other', 'VSR MCP Plug-in Connector Licence',
  'Governed MCP server or client connector registered against an existing VSR licence and evaluated by Warden.',
  array['oauth2','api_key','jwt','mtls','none'],
  array['tools','resources','prompts','streamable_http','stdio','riveros_evidence'],
  jsonb_build_object('required', jsonb_build_array('manifest_url','transport_modes','target_vsr_licences')),
  array['client_id','client_secret','api_key','private_key'], 'hybrid', 'available'
) on conflict (provider_key) do update set
  display_name=excluded.display_name, description=excluded.description,
  supported_auth_types=excluded.supported_auth_types, capabilities=excluded.capabilities,
  configuration_schema=excluded.configuration_schema, credential_fields=excluded.credential_fields,
  connector_mode=excluded.connector_mode, status=excluded.status, updated_at=timezone('utc', now());

insert into warden.tenant_credentials (tenant_id, external_tenant_id, status)
select id, external_tenant_id, 'pending' from public.integration_tenants
where external_tenant_id='vsr-voi-recovery-pilot' on conflict (tenant_id) do nothing;

insert into warden.ledger_heads (tenant_id) select id from public.integration_tenants on conflict (tenant_id) do nothing;

do $$ begin
  if not exists (select 1 from vault.secrets where name='warden_receipt_hmac_v1') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32),'base64'),'warden_receipt_hmac_v1','Pilot HMAC key for RiverOS/Supabase Warden receipt claims.',null);
  end if;
  if not exists (select 1 from vault.secrets where name='typeform_mcp_webhook_v1') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32),'base64'),'typeform_mcp_webhook_v1','HMAC secret for the VSR MCP connector licence Typeform webhook.',null);
  end if;
end $$;
