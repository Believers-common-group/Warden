create or replace function public.warden_commit_batch(
    p_batch_id text,
    p_external_tenant_id text,
    p_external_device_id text,
    p_events jsonb
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, warden, extensions
as $$
declare
    v_tenant_id uuid; v_device warden.devices%rowtype; v_head warden.ledger_heads%rowtype;
    v_existing jsonb; v_event jsonb; v_existing_event warden.events%rowtype;
    v_policy warden.event_policies%rowtype; v_sequence bigint; v_event_sequence bigint;
    v_previous_event_hash text; v_entry_hash text; v_receipt_id text;
    v_recorded_at timestamptz; v_recorded_ms bigint;
    v_accepted jsonb := '[]'::jsonb; v_rejected jsonb := '[]'::jsonb; v_ack jsonb;
begin
    select acknowledgement into v_existing from warden.batch_receipts where batch_id=p_batch_id;
    if found then return v_existing; end if;
    select t.tenant_id into v_tenant_id from warden.tenant_credentials t where t.external_tenant_id=p_external_tenant_id and t.status='active';
    if v_tenant_id is null then raise exception 'Tenant not active'; end if;
    select * into v_device from warden.devices where tenant_id=v_tenant_id and external_device_id=p_external_device_id for update;
    if not found or v_device.status<>'active' then raise exception 'Device not active'; end if;
    insert into warden.ledger_heads(tenant_id) values(v_tenant_id) on conflict(tenant_id) do nothing;
    select * into v_head from warden.ledger_heads where tenant_id=v_tenant_id for update;
    v_sequence:=v_head.last_sequence;

    for v_event in select value from jsonb_array_elements(p_events) loop
      select * into v_existing_event from warden.events where event_id=v_event->>'id';
      if found then
        if v_existing_event.event_hash<>v_event->>'eventHash' then
          v_rejected:=v_rejected||jsonb_build_array(jsonb_build_object('eventID',v_event->>'id','code','EVENT_ID_CONFLICT','message','The event ID already exists with a different hash.','retryable',false,'retryAfterSeconds',null));
        else
          v_accepted:=v_accepted||jsonb_build_array(jsonb_build_object('eventID',v_existing_event.event_id,'receiptID',v_existing_event.receipt_id,'recordedAt',floor(extract(epoch from v_existing_event.recorded_at)*1000)::bigint,'tenantID',p_external_tenant_id,'projectID',v_existing_event.project_id,'eventHash',v_existing_event.event_hash,'ledgerSequence',v_existing_event.ledger_sequence,'ledgerEntryHash',v_existing_event.ledger_entry_hash,'policyDecisionID',(select policy_ref from warden.event_policies where id=v_existing_event.policy_id)));
        end if;
        continue;
      end if;

      select * into v_policy from warden.event_policies p
      where p.tenant_id=v_tenant_id and p.status='active'
        and p.event_type in ('*',coalesce(v_event->>'type',''))
        and p.purpose in ('*',coalesce(v_event->>'purpose',''))
        and p.authority_basis in ('*',coalesce(v_event#>>'{authority,basis}',''))
        and p.retention_class in ('*',coalesce(v_event->>'retentionClass',''))
      order by ((p.event_type<>'*')::int+(p.purpose<>'*')::int+(p.authority_basis<>'*')::int+(p.retention_class<>'*')::int) desc,p.priority desc limit 1;
      if not found then
        v_rejected:=v_rejected||jsonb_build_array(jsonb_build_object('eventID',v_event->>'id','code','POLICY_NOT_CONFIGURED','message','No active Warden policy matches this event.','retryable',false,'retryAfterSeconds',null)); continue;
      end if;
      if v_policy.decision<>'allow' then
        v_rejected:=v_rejected||jsonb_build_array(jsonb_build_object('eventID',v_event->>'id','code','POLICY_DENIED','message','The authoritative Warden policy denied this event.','retryable',false,'retryAfterSeconds',null)); continue;
      end if;
      if v_policy.require_authority_reference and nullif(v_event#>>'{authority,reference}','') is null then
        v_rejected:=v_rejected||jsonb_build_array(jsonb_build_object('eventID',v_event->>'id','code','AUTHORITY_REFERENCE_REQUIRED','message','The matched policy requires an authority reference.','retryable',false,'retryAfterSeconds',null)); continue;
      end if;
      v_event_sequence:=(v_event->>'sequence')::bigint;
      if v_event_sequence<>v_device.last_sequence+1 then
        v_rejected:=v_rejected||jsonb_build_array(jsonb_build_object('eventID',v_event->>'id','code','DEVICE_SEQUENCE_CONFLICT','message','The device sequence is not contiguous.','retryable',false,'retryAfterSeconds',null)); continue;
      end if;
      v_previous_event_hash:=nullif(v_event->>'previousEventHash','');
      if coalesce(v_previous_event_hash,'')<>coalesce(v_device.last_event_hash,'') then
        v_rejected:=v_rejected||jsonb_build_array(jsonb_build_object('eventID',v_event->>'id','code','DEVICE_HASH_CHAIN_CONFLICT','message','The previous event hash does not match the device head.','retryable',false,'retryAfterSeconds',null)); continue;
      end if;

      v_sequence:=v_sequence+1;
      v_receipt_id:='rcpt-'||lower(replace(gen_random_uuid()::text,'-',''));
      v_recorded_at:=clock_timestamp();
      v_recorded_ms:=floor(extract(epoch from v_recorded_at)*1000)::bigint;
      v_entry_hash:=encode(extensions.digest(concat_ws(E'\n',p_external_tenant_id,v_sequence::text,v_event->>'id',v_event->>'eventHash',coalesce(v_head.last_entry_hash,''),v_policy.policy_ref),'sha256'),'hex');
      insert into warden.events(event_id,tenant_id,device_id,project_id,event_hash,event_json,policy_id,receipt_id,recorded_at,ledger_sequence,previous_ledger_hash,ledger_entry_hash)
      values(v_event->>'id',v_tenant_id,v_device.id,v_event->>'projectID',v_event->>'eventHash',v_event,v_policy.id,v_receipt_id,v_recorded_at,v_sequence,v_head.last_entry_hash,v_entry_hash);
      v_device.last_sequence:=v_event_sequence; v_device.last_event_hash:=v_event->>'eventHash';
      update warden.devices set last_sequence=v_device.last_sequence,last_event_hash=v_device.last_event_hash,updated_at=now() where id=v_device.id;
      v_head.last_sequence:=v_sequence; v_head.last_entry_hash:=v_entry_hash;
      update warden.ledger_heads set last_sequence=v_head.last_sequence,last_entry_hash=v_head.last_entry_hash,updated_at=now() where tenant_id=v_tenant_id;
      v_accepted:=v_accepted||jsonb_build_array(jsonb_build_object('eventID',v_event->>'id','receiptID',v_receipt_id,'recordedAt',v_recorded_ms,'tenantID',p_external_tenant_id,'projectID',v_event->>'projectID','eventHash',v_event->>'eventHash','ledgerSequence',v_sequence,'ledgerEntryHash',v_entry_hash,'policyDecisionID',v_policy.policy_ref));
    end loop;
    v_ack:=jsonb_build_object('batchID',p_batch_id,'accepted',v_accepted,'rejected',v_rejected);
    insert into warden.batch_receipts(batch_id,tenant_id,device_id,acknowledgement) values(p_batch_id,v_tenant_id,v_device.id,v_ack);
    return v_ack;
end $$;

create or replace function public.warden_verify_typeform_signature(p_raw_body text,p_signature text) returns boolean
language plpgsql security definer set search_path=pg_catalog,vault,extensions as $$
declare v_secret text; v_expected bytea; v_supplied bytea;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name='typeform_mcp_webhook_v1';
  if v_secret is null or p_signature is null or left(p_signature,7)<>'sha256=' then return false; end if;
  begin v_supplied:=decode(substr(p_signature,8),'base64'); exception when others then return false; end;
  v_expected:=extensions.hmac(convert_to(p_raw_body,'utf8'),convert_to(v_secret,'utf8'),'sha256');
  return warden.constant_time_equal(v_expected,v_supplied);
end $$;
