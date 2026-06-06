-- =====================================================================
-- Noor Dentofacial Clinic — 0009 Complete session (+ auto-bill)
-- =====================================================================
-- Lets the assigned DOCTOR (or admin/receptionist) mark a visit COMPLETED
-- and generates the bill in the same step. Runs SECURITY DEFINER so the
-- doctor — who normally can't insert bills — can finalize their session.
-- Requires migration 0007 (providers.default_share_pct).
-- =====================================================================

create or replace function public.complete_session(p_appt uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appt     public.appointments;
  v_type     public.appointment_types;
  v_provider public.providers;
  v_total    numeric;
  v_pct      numeric;
  v_bill_id  uuid;
begin
  select * into v_appt from public.appointments where id = p_appt;
  if not found then raise exception 'Appointment not found'; end if;

  -- Authorize: admin, receptionist, or the doctor assigned to this visit.
  if not (
    public.has_role(array['ADMIN','RECEPTIONIST']::user_role[])
    or (public.has_role(array['DOCTOR']::user_role[]) and v_appt.provider_id = public.current_provider_id())
  ) then
    raise exception 'Not allowed to complete this session';
  end if;

  update public.appointments set status = 'COMPLETED' where id = p_appt;

  -- One bill per appointment.
  select id into v_bill_id from public.bills where appointment_id = p_appt limit 1;
  if v_bill_id is not null then return v_bill_id; end if;

  select * into v_type     from public.appointment_types where id = v_appt.appointment_type_id;
  select * into v_provider from public.providers         where id = v_appt.provider_id;

  v_total := coalesce(v_type.consultation_fee, 0) + coalesce(v_type.test_fee, 0);
  v_pct   := coalesce(nullif(v_provider.default_share_pct, 0), v_type.default_doctor_pct, 0);

  insert into public.bills (invoice_no, patient_id, appointment_id, provider_id,
                            consultation_fee, test_fee, discount, doctor_share)
  values (
    'INV-' || to_char(now(), 'YYMMDDHH24MISS'),
    v_appt.patient_id, p_appt, v_appt.provider_id,
    coalesce(v_type.consultation_fee, 0), coalesce(v_type.test_fee, 0), 0,
    round(v_total * v_pct / 100, 2)
  )
  returning id into v_bill_id;

  return v_bill_id;
end;
$$;

grant execute on function public.complete_session(uuid) to authenticated;
