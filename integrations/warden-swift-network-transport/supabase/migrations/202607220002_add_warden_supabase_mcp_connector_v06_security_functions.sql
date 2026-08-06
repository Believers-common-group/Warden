create or replace function warden.activate_tenant(p_external_tenant_id text,p_api_key text) returns uuid
language plpgsql security definer set search_path=pg_catalog,public,warden,extensions as $$
declare v_tenant_id uuid;
begin
  if p_api_key is null or length(p_api_key)<24 then raise exception 'API key must contain at least 24 characters'; end if;
  select id into v_tenant_id from public.integration_tenants where external_tenant_id=p_external_tenant_id;
  if v_tenant_id is null then raise exception 'Unknown integration tenant: %',p_external_tenant_id; end if;
  insert into warden.tenant_credentials(tenant_id,external_tenant_id,status,api_key_hash)
  values(v_tenant_id,p_external_tenant_id,'active',encode(extensions.digest(p_api_key,'sha256'),'hex'))
  on conflict(tenant_id) do update set external_tenant_id=excluded.external_tenant_id,status='active',api_key_hash=excluded.api_key_hash,updated_at=now();
  insert into warden.ledger_heads(tenant_id) values(v_tenant_id) on conflict(tenant_id) do nothing;
  return v_tenant_id;
end $$;

create or replace function warden.enrol_hmac_device(p_external_tenant_id text,p_external_device_id text,p_project_id text,p_key_id text,p_hmac_secret text) returns uuid
language plpgsql security definer set search_path=pg_catalog,public,warden,vault as $$
declare v_tenant_id uuid; v_device_id uuid; v_secret_id uuid;
begin
  if p_hmac_secret is null or length(p_hmac_secret)<24 then raise exception 'Device HMAC secret must contain at least 24 characters'; end if;
  select tenant_id into v_tenant_id from warden.tenant_credentials where external_tenant_id=p_external_tenant_id and status='active';
  if v_tenant_id is null then raise exception 'Tenant is not active: %',p_external_tenant_id; end if;
  select id into v_secret_id from vault.secrets where name='warden_device_'||p_external_tenant_id||'_'||p_external_device_id;
  if v_secret_id is null then
    v_secret_id:=vault.create_secret(p_hmac_secret,'warden_device_'||p_external_tenant_id||'_'||p_external_device_id,'Warden device HMAC verification secret.',null);
  else perform vault.update_secret(v_secret_id,p_hmac_secret,null,null,null); end if;
  insert into warden.devices(tenant_id,external_device_id,project_id,status,signature_algorithm,key_id,verification_secret_id)
  values(v_tenant_id,p_external_device_id,p_project_id,'active','hmac-sha256',p_key_id,v_secret_id)
  on conflict(tenant_id,external_device_id) do update set project_id=excluded.project_id,status='active',signature_algorithm=excluded.signature_algorithm,key_id=excluded.key_id,verification_secret_id=excluded.verification_secret_id,verification_key_b64=null,updated_at=now()
  returning id into v_device_id;
  return v_device_id;
end $$;

create or replace function warden.enrol_ed25519_device(p_external_tenant_id text,p_external_device_id text,p_project_id text,p_key_id text,p_public_key_b64 text) returns uuid
language plpgsql security definer set search_path=pg_catalog,public,warden as $$
declare v_tenant_id uuid; v_device_id uuid;
begin
  select tenant_id into v_tenant_id from warden.tenant_credentials where external_tenant_id=p_external_tenant_id and status='active';
  if v_tenant_id is null then raise exception 'Tenant is not active: %',p_external_tenant_id; end if;
  insert into warden.devices(tenant_id,external_device_id,project_id,status,signature_algorithm,key_id,verification_key_b64)
  values(v_tenant_id,p_external_device_id,p_project_id,'active','ed25519-sha256-digest',p_key_id,p_public_key_b64)
  on conflict(tenant_id,external_device_id) do update set project_id=excluded.project_id,status='active',signature_algorithm=excluded.signature_algorithm,key_id=excluded.key_id,verification_key_b64=excluded.verification_key_b64,verification_secret_id=null,updated_at=now()
  returning id into v_device_id;
  return v_device_id;
end $$;

create or replace function public.warden_validate_tenant_api_key(p_external_tenant_id text,p_api_key text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,warden,extensions as $$
declare v_row warden.tenant_credentials%rowtype; v_hash text;
begin
  select * into v_row from warden.tenant_credentials where external_tenant_id=p_external_tenant_id;
  if not found then return jsonb_build_object('ok',false,'code','UNKNOWN_TENANT'); end if;
  if v_row.status<>'active' then return jsonb_build_object('ok',false,'code','TENANT_NOT_ACTIVE'); end if;
  v_hash:=encode(extensions.digest(coalesce(p_api_key,''),'sha256'),'hex');
  if not warden.constant_time_equal(decode(v_hash,'hex'),decode(v_row.api_key_hash,'hex')) then return jsonb_build_object('ok',false,'code','INVALID_API_KEY'); end if;
  return jsonb_build_object('ok',true,'tenantID',v_row.tenant_id,'externalTenantID',v_row.external_tenant_id);
end $$;

create or replace function public.warden_get_device(p_external_tenant_id text,p_external_device_id text) returns jsonb
language sql security definer set search_path=pg_catalog,public,warden as $$
select coalesce((select jsonb_build_object('ok',d.status='active','code',case when d.status='active' then 'OK' else 'DEVICE_NOT_ACTIVE' end,'deviceUUID',d.id,'tenantID',d.tenant_id,'externalDeviceID',d.external_device_id,'projectID',d.project_id,'algorithm',d.signature_algorithm,'keyID',d.key_id,'verificationKeyB64',d.verification_key_b64)
from warden.devices d join warden.tenant_credentials t on t.tenant_id=d.tenant_id where t.external_tenant_id=p_external_tenant_id and d.external_device_id=p_external_device_id),jsonb_build_object('ok',false,'code','UNKNOWN_DEVICE'));
$$;

create or replace function public.warden_verify_device_hmac_batch(p_external_tenant_id text,p_external_device_id text,p_events jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,warden,vault,extensions as $$
declare v_device warden.devices%rowtype; v_secret text; v_event jsonb; v_expected bytea; v_supplied bytea;
begin
  select d.* into v_device from warden.devices d join warden.tenant_credentials t on t.tenant_id=d.tenant_id where t.external_tenant_id=p_external_tenant_id and d.external_device_id=p_external_device_id and d.status='active';
  if not found then return jsonb_build_object('ok',false,'code','UNKNOWN_DEVICE'); end if;
  if v_device.signature_algorithm<>'hmac-sha256' then return jsonb_build_object('ok',false,'code','WRONG_SIGNATURE_ALGORITHM'); end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where id=v_device.verification_secret_id;
  if v_secret is null then return jsonb_build_object('ok',false,'code','DEVICE_SECRET_UNAVAILABLE'); end if;
  for v_event in select value from jsonb_array_elements(p_events) loop
    if coalesce(v_event#>>'{signature,keyID}','')<>v_device.key_id then return jsonb_build_object('ok',false,'code','KEY_ID_MISMATCH','eventID',v_event->>'id'); end if;
    v_expected:=extensions.hmac(decode(v_event->>'eventHash','hex'),convert_to(v_secret,'utf8'),'sha256');
    begin v_supplied:=decode(coalesce(v_event#>>'{signature,value}',''),'base64'); exception when others then return jsonb_build_object('ok',false,'code','INVALID_EVENT_SIGNATURE_ENCODING','eventID',v_event->>'id'); end;
    if not warden.constant_time_equal(v_expected,v_supplied) then return jsonb_build_object('ok',false,'code','INVALID_EVENT_SIGNATURE','eventID',v_event->>'id'); end if;
  end loop;
  return jsonb_build_object('ok',true);
end $$;

create or replace function public.warden_sign_receipts(p_canonical_claims text[]) returns text[]
language plpgsql security definer set search_path=pg_catalog,vault,extensions as $$
declare v_secret text; v_claim text; v_result text[]:='{}';
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name='warden_receipt_hmac_v1';
  if v_secret is null then raise exception 'Receipt signing key unavailable'; end if;
  foreach v_claim in array p_canonical_claims loop
    v_result:=array_append(v_result,encode(extensions.hmac(convert_to(v_claim,'utf8'),convert_to(v_secret,'utf8'),'sha256'),'base64'));
  end loop;
  return v_result;
end $$;
