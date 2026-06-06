-- =====================================================================
-- Noor Dentofacial Clinic — 0005 Business Logic
-- =====================================================================
-- Derived billing math, payment rollups, stock adjustment, queue
-- numbering, slot-reservation expiry, and the scoped Doctor Earnings
-- aggregation (description.md §6.6 / §6.9a).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Billing: keep total + share split consistent.
-- total = consultation + test - discount.
-- If shares weren't supplied, clinic_share absorbs the remainder.
-- ---------------------------------------------------------------------
create or replace function public.compute_bill_amounts()
returns trigger
language plpgsql
as $$
begin
  new.total_amount := coalesce(new.consultation_fee,0) + coalesce(new.test_fee,0) - coalesce(new.discount,0);
  if new.total_amount < 0 then new.total_amount := 0; end if;

  -- clamp doctor share to total, clinic share is the remainder
  if new.doctor_share is null then new.doctor_share := 0; end if;
  if new.doctor_share > new.total_amount then new.doctor_share := new.total_amount; end if;
  new.clinic_share := new.total_amount - new.doctor_share;

  -- derive status from amount_paid unless explicitly cancelled
  if new.status <> 'CANCELLED' then
    if new.amount_paid <= 0 then
      new.status := 'PENDING';
    elsif new.amount_paid < new.total_amount then
      new.status := 'PARTIAL';
    else
      new.status := 'PAID';
    end if;
  end if;
  return new;
end;
$$;

create trigger bills_compute_amounts
  before insert or update on public.bills
  for each row execute function public.compute_bill_amounts();

-- ---------------------------------------------------------------------
-- Payment rollup: a new payment bumps the bill's amount_paid (which
-- re-triggers status via compute_bill_amounts on the UPDATE).
-- ---------------------------------------------------------------------
create or replace function public.apply_bill_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bills
     set amount_paid = amount_paid + new.amount
   where id = new.bill_id;
  return new;
end;
$$;

create trigger bill_payments_rollup
  after insert on public.bill_payments
  for each row execute function public.apply_bill_payment();

-- ---------------------------------------------------------------------
-- Inventory: a stock movement mutates on-hand quantity.
-- ---------------------------------------------------------------------
create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.inventory_items
     set quantity = case new.type
                      when 'ADD'    then quantity + new.quantity
                      when 'DEDUCT' then quantity - new.quantity
                      when 'ADJUST' then new.quantity          -- absolute set
                    end
   where id = new.item_id;
  return new;
end;
$$;

create trigger stock_movements_apply
  after insert on public.stock_movements
  for each row execute function public.apply_stock_movement();

-- ---------------------------------------------------------------------
-- Queue numbering: assign the next number for the appointment's day
-- when it transitions to CHECKED_IN. Idempotent (won't renumber).
-- ---------------------------------------------------------------------
create or replace function public.assign_queue_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  next_no int;
begin
  if new.status = 'CHECKED_IN'
     and (old.status is distinct from 'CHECKED_IN')
     and new.queue_number is null then
    select coalesce(max(queue_number), 0) + 1 into next_no
      from public.appointments
     where date(scheduled_for) = date(new.scheduled_for);
    new.queue_number := next_no;
  end if;
  return new;
end;
$$;

create trigger appointments_assign_queue
  before update on public.appointments
  for each row execute function public.assign_queue_number();

-- ---------------------------------------------------------------------
-- Slot reservations: expire stale holds and free the slot.
-- Call from pg_cron (see bottom) — mirrors the web node-cron cleanup.
-- ---------------------------------------------------------------------
create or replace function public.expire_slot_reservations()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  affected int;
begin
  with expired as (
    update public.slot_reservations
       set status = 'EXPIRED'
     where status = 'HELD' and expires_at < now()
     returning time_slot_id
  )
  update public.time_slots t
     set is_available = true
    from expired e
   where t.id = e.time_slot_id;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

-- Hold helper: atomically mark a slot unavailable + create a HELD row.
create or replace function public.hold_slot(p_time_slot_id uuid, p_patient_id uuid default null)
returns public.slot_reservations
language plpgsql
security definer
set search_path = public
as $$
declare
  res public.slot_reservations;
begin
  update public.time_slots
     set is_available = false
   where id = p_time_slot_id and is_available = true;
  if not found then
    raise exception 'Slot is no longer available';
  end if;
  insert into public.slot_reservations (time_slot_id, held_by, patient_id)
  values (p_time_slot_id, auth.uid(), p_patient_id)
  returning * into res;
  return res;
end;
$$;

-- ---------------------------------------------------------------------
-- Doctor Earnings (§6.9a): scoped aggregation of the doctor share.
-- A doctor can ONLY query their own figure; admin may pass a provider.
-- paid_only=true counts settled money; false counts paid + pending.
-- ---------------------------------------------------------------------
create or replace function public.get_doctor_earnings(
  p_provider_id uuid default null,
  p_from        timestamptz default null,
  p_to          timestamptz default null,
  p_paid_only   boolean default false
)
returns table (
  provider_id   uuid,
  total_share   numeric,
  paid_share    numeric,
  pending_share numeric,
  bill_count    bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  target uuid;
begin
  -- Resolve scope: admins may inspect any provider; everyone else is
  -- forced to their own provider id regardless of what they pass.
  if public.has_role(array['ADMIN']::user_role[]) then
    target := coalesce(p_provider_id, public.current_provider_id());
  else
    target := public.current_provider_id();
  end if;

  if target is null then
    return;  -- caller is not a provider and gave no id
  end if;

  return query
  select
    b.provider_id,
    sum(b.doctor_share)                                                   as total_share,
    sum(case when b.status = 'PAID' then b.doctor_share else 0 end)       as paid_share,
    sum(case when b.status <> 'PAID' then b.doctor_share else 0 end)      as pending_share,
    count(*)                                                              as bill_count
  from public.bills b
  where b.provider_id = target
    and b.status <> 'CANCELLED'
    and (p_from is null or b.created_at >= p_from)
    and (p_to   is null or b.created_at <  p_to)
    and (not p_paid_only or b.status = 'PAID')
  group by b.provider_id;
end;
$$;

grant execute on function public.get_doctor_earnings(uuid, timestamptz, timestamptz, boolean) to authenticated;
grant execute on function public.hold_slot(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Scheduled cleanup via pg_cron (available on Supabase). Safe-guarded:
-- only schedules if the extension is present.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule(
      'expire-slot-reservations',
      '* * * * *',                       -- every minute
      $cron$ select public.expire_slot_reservations(); $cron$
    );
  end if;
exception when others then
  raise notice 'pg_cron not configured: %', sqlerrm;
end $$;
