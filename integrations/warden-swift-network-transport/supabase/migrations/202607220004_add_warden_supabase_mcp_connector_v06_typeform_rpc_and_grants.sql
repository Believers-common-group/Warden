create or replace function public.warden_record_typeform_mcp_submission(
    p_raw_payload jsonb,
    p_normalized_payload jsonb,
    p_signature text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public, warden, vsr_registry, extensions
as $$
declare
    v_event_id text := p_raw_payload->>'event_id';
    v_form_id text := p_raw_payload #>> '{form_response,form_id}';
    v_response_token text := p_raw_payload #>> '{form_response,token}';
    v_licence_id uuid; v_application_id uuid; v_application_ref text;
    v_status text; v_prev_hash text; v_event_hash text;
begin
    if nullif(v_event_id,'') is null or nullif(v_form_id,'') is null or nullif(v_response_token,'') is null then
      raise exception 'Typeform payload is missing event_id, form_id, or response token';
    end if;
    insert into warden.typeform_webhook_events(event_id,form_id,response_token,signature,raw_payload,normalized_payload)
    values(v_event_id,v_form_id,v_response_token,p_signature,p_raw_payload,p_normalized_payload)
    on conflict(event_id) do nothing;
    select id,application_ref into v_application_id,v_application_ref from warden.mcp_connector_applications where typeform_event_id=v_event_id;
    if found then return jsonb_build_object('ok',true,'duplicate',true,'applicationID',v_application_id,'applicationRef',v_application_ref); end if;
    select id into v_licence_id from vsr_registry.licences where licence_ref=p_normalized_payload->>'vsr_licence_ref' limit 1;
    v_status:=case when v_licence_id is null then 'needs_licence_validation' else 'submitted' end;
    insert into warden.mcp_connector_applications(
      typeform_event_id,form_id,response_token,external_tenant_id,organization_name,applicant_name,applicant_email,
      vsr_licence_ref,licence_id,requested_licence_tier,connector_name,provider_name,repository_url,manifest_url,
      transport_modes,deployment_model,target_vsr_licences,requested_operations,data_classes,auth_methods,capabilities,
      submission_payload,status
    ) values (
      v_event_id,v_form_id,v_response_token,nullif(p_normalized_payload->>'tenant_id',''),
      p_normalized_payload->>'organization_name',p_normalized_payload->>'applicant_name',p_normalized_payload->>'applicant_email',
      p_normalized_payload->>'vsr_licence_ref',v_licence_id,p_normalized_payload->>'requested_licence_tier',
      p_normalized_payload->>'connector_name',p_normalized_payload->>'provider_name',nullif(p_normalized_payload->>'repository_url',''),
      nullif(p_normalized_payload->>'manifest_url',''),coalesce(array(select jsonb_array_elements_text(p_normalized_payload->'transport_modes')),'{}'),
      nullif(p_normalized_payload->>'deployment_model',''),coalesce(array(select jsonb_array_elements_text(p_normalized_payload->'target_vsr_licences')),'{}'),
      coalesce(array(select jsonb_array_elements_text(p_normalized_payload->'requested_operations')),'{}'),
      coalesce(array(select jsonb_array_elements_text(p_normalized_payload->'data_classes')),'{}'),
      coalesce(array(select jsonb_array_elements_text(p_normalized_payload->'auth_methods')),'{}'),
      coalesce(p_normalized_payload->'capabilities','{}'::jsonb),p_normalized_payload,v_status
    ) returning id,application_ref into v_application_id,v_application_ref;
    select event_hash into v_prev_hash from warden.mcp_application_events where application_id=v_application_id order by recorded_at desc,id desc limit 1;
    v_event_hash:=encode(extensions.digest(concat_ws(E'\n',v_application_id::text,'application.submitted',coalesce(v_prev_hash,''),p_normalized_payload::text),'sha256'),'hex');
    insert into warden.mcp_application_events(application_id,event_type,actor_ref,payload,previous_hash,event_hash)
    values(v_application_id,'application.submitted','typeform:'||v_form_id,jsonb_build_object('status',v_status,'licenceID',v_licence_id),v_prev_hash,v_event_hash);
    update warden.typeform_webhook_events set processing_status='processed',processed_at=now() where event_id=v_event_id;
    return jsonb_build_object('ok',true,'duplicate',false,'applicationID',v_application_id,'applicationRef',v_application_ref,'status',v_status);
end $$;

revoke all on function public.warden_validate_tenant_api_key(text,text) from public,anon,authenticated;
revoke all on function public.warden_get_device(text,text) from public,anon,authenticated;
revoke all on function public.warden_verify_device_hmac_batch(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.warden_sign_receipts(text[]) from public,anon,authenticated;
revoke all on function public.warden_commit_batch(text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.warden_verify_typeform_signature(text,text) from public,anon,authenticated;
revoke all on function public.warden_record_typeform_mcp_submission(jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.warden_validate_tenant_api_key(text,text) to service_role;
grant execute on function public.warden_get_device(text,text) to service_role;
grant execute on function public.warden_verify_device_hmac_batch(text,text,jsonb) to service_role;
grant execute on function public.warden_sign_receipts(text[]) to service_role;
grant execute on function public.warden_commit_batch(text,text,text,jsonb) to service_role;
grant execute on function public.warden_verify_typeform_signature(text,text) to service_role;
grant execute on function public.warden_record_typeform_mcp_submission(jsonb,jsonb,text) to service_role;
revoke all on all tables in schema warden from public,anon,authenticated;
grant select,insert,update,delete on all tables in schema warden to service_role;
revoke all on function warden.constant_time_equal(bytea,bytea) from public,anon,authenticated;
revoke all on function warden.activate_tenant(text,text) from public,anon,authenticated;
revoke all on function warden.enrol_hmac_device(text,text,text,text,text) from public,anon,authenticated;
revoke all on function warden.enrol_ed25519_device(text,text,text,text,text) from public,anon,authenticated;
grant execute on function warden.activate_tenant(text,text) to service_role;
grant execute on function warden.enrol_hmac_device(text,text,text,text,text) to service_role;
grant execute on function warden.enrol_ed25519_device(text,text,text,text,text) to service_role;

alter function warden.constant_time_equal(bytea,bytea) set search_path=pg_catalog;
create index if not exists idx_warden_batch_receipts_tenant_id on warden.batch_receipts(tenant_id);
create index if not exists idx_warden_batch_receipts_device_id on warden.batch_receipts(device_id);
create index if not exists idx_warden_devices_shell_device_id on warden.devices(shell_device_id) where shell_device_id is not null;
create index if not exists idx_warden_events_device_id on warden.events(device_id);
create index if not exists idx_warden_events_policy_id on warden.events(policy_id);
create index if not exists idx_warden_mcp_application_events_application_id on warden.mcp_application_events(application_id,recorded_at desc);
create index if not exists idx_warden_mcp_connector_applications_licence_id on warden.mcp_connector_applications(licence_id) where licence_id is not null;
create index if not exists idx_warden_mcp_bindings_licence_id on warden.mcp_connector_licence_bindings(licence_id);
create index if not exists idx_warden_mcp_bindings_connector_instance_id on warden.mcp_connector_licence_bindings(connector_instance_id) where connector_instance_id is not null;
