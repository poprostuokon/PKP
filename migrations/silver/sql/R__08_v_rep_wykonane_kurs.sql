-- =============================================================================
-- silver.v_rep_wykonane_kurs
-- -----------------------------------------------------------------------------
-- Widok raportowy APEX (strona 5 lista, strona 6 naglowek): zakonczone kursy
-- D-1..D-7, ktorych plan zawiera Wroclaw Glowny (60103). Jeden wiersz = kurs.
-- Relacja start -> koniec wg planu, plan vs rzeczywistosc na starcie, koncu
-- i we Wroclawiu, status (odwolany/skrocony/odwolane stacje), przewoznik
-- i kategoria ze slownikow wg daty kursu. Tylko surowe dane, bez formatowania.
-- Czasy actual_* z operation_details sa juz lokalne (bez AT TIME ZONE).
-- =============================================================================

CREATE OR REPLACE VIEW silver.V_REP_WYKONANE_KURS as
with prm as (    -- "dzis" liczone raz
    select /*+ materialize */ trunc(maintenance.pkg_tool.f_now_warsaw) as dzis
    from dual
),
kurs as (        -- zakonczone kursy D-1..D-7, ktorych plan zawiera Wroclaw Glowny
    select /*+ materialize */
           oh.id              as ophe_id,
           oh.operating_date,
           oh.schedule_id,
           oh.order_id,
           oh.train_order_id,
           oh.train_status,
           sh.carrier_code    as przewoznik,
           sh.category_code   as kategoria,
           sh.national_number as nr_pociagu,
           sh.name            as nazwa_pociagu
    from prm
    join silver.operation_header oh
         on oh.operating_date between prm.dzis - 7 and prm.dzis - 1
    join silver.schedule_header sh
         on  sh.operating_date = oh.operating_date
         and sh.schedule_id    = oh.schedule_id
         and sh.order_id       = oh.order_id
         and sh.train_order_id = oh.train_order_id
    where exists (select 1
                    from silver.schedule_details w
                   where w.schedule_id = oh.schedule_id
                     and w.order_id    = oh.order_id
                     and w.dsta_id     = 60103)
),
plan as (        -- plan: poczatek, koniec i Wroclaw (po order_number), jeden skan
    select sd.schedule_id, sd.order_id,
           min(sd.order_number)                                                    as start_seq,
           max(sd.order_number)                                                    as koniec_seq,
           min(sd.dsta_id)        keep (dense_rank first order by sd.order_number) as start_dsta,
           max(sd.dsta_id)        keep (dense_rank last  order by sd.order_number) as koniec_dsta,
           min(sd.departure_time) keep (dense_rank first order by sd.order_number) as start_dep_time,
           min(sd.departure_day)  keep (dense_rank first order by sd.order_number) as start_dep_day,
           max(sd.arrival_time)   keep (dense_rank last  order by sd.order_number) as koniec_arr_time,
           max(sd.arrival_day)    keep (dense_rank last  order by sd.order_number) as koniec_arr_day,
           max(case when sd.dsta_id = 60103 then sd.order_number   end)            as wro_seq,
           max(case when sd.dsta_id = 60103 then sd.arrival_time   end)            as wro_arr_time,
           max(case when sd.dsta_id = 60103 then sd.arrival_day    end)            as wro_arr_day,
           max(case when sd.dsta_id = 60103 then sd.departure_time end)            as wro_dep_time,
           max(case when sd.dsta_id = 60103 then sd.departure_day  end)            as wro_dep_day
    from silver.schedule_details sd
    join (select distinct schedule_id, order_id from kurs) kk
         on  kk.schedule_id = sd.schedule_id
         and kk.order_id    = sd.order_id
    group by sd.schedule_id, sd.order_id
),
op as (          -- wykonanie: JEDEN przebieg po operation_details
    select k.ophe_id,
           -- start (rzeczywista kolejnosc)
           max(od.actual_departure)    keep (dense_rank first order by od.actual_sequence) as start_odj_ts,
           max(od.departure_delay_min) keep (dense_rank first order by od.actual_sequence) as op_start_min,
           -- ostatnia faktycznie osiagnieta (potwierdzona, nieodwolana)
           max(case when od.is_confirmed and not od.is_cancelled then 1 else 0 end)       as ol_jest,
           max(od.dsta_id)           keep (dense_rank last order by
                 case when od.is_confirmed and not od.is_cancelled then 1 else 0 end, od.actual_sequence) as ol_dsta,
           max(od.actual_arrival)    keep (dense_rank last order by
                 case when od.is_confirmed and not od.is_cancelled then 1 else 0 end, od.actual_sequence) as ol_arr_ts,
           max(od.arrival_delay_min) keep (dense_rank last order by
                 case when od.is_confirmed and not od.is_cancelled then 1 else 0 end, od.actual_sequence) as ol_delay,
           -- stacja koncowa wg planu (przy duplikacie planned_sequence najpozniejszy wpis)
           max(case when od.planned_sequence = p.koniec_seq then 1 else 0 end)            as ok_jest,
           max(case when od.is_confirmed and not od.is_cancelled then 1 else 0 end)
                                     keep (dense_rank last order by
                 case when od.planned_sequence = p.koniec_seq then 1 else 0 end, od.actual_sequence) as ok_dojechal,
           max(od.actual_arrival)    keep (dense_rank last order by
                 case when od.planned_sequence = p.koniec_seq then 1 else 0 end, od.actual_sequence) as ok_arr_ts,
           max(od.arrival_delay_min) keep (dense_rank last order by
                 case when od.planned_sequence = p.koniec_seq then 1 else 0 end, od.actual_sequence) as ok_delay,
           -- Wroclaw wg planu
           max(case when od.planned_sequence = p.wro_seq then 1 else 0 end)               as ow_jest,
           max(od.actual_arrival)      keep (dense_rank last order by
                 case when od.planned_sequence = p.wro_seq then 1 else 0 end, od.actual_sequence) as ow_arr_ts,
           max(od.actual_departure)    keep (dense_rank last order by
                 case when od.planned_sequence = p.wro_seq then 1 else 0 end, od.actual_sequence) as ow_dep_ts,
           max(od.arrival_delay_min)   keep (dense_rank last order by
                 case when od.planned_sequence = p.wro_seq then 1 else 0 end, od.actual_sequence) as ow_arr_delay,
           max(od.departure_delay_min) keep (dense_rank last order by
                 case when od.planned_sequence = p.wro_seq then 1 else 0 end, od.actual_sequence) as ow_dep_delay,
           max(case when od.is_cancelled then 1 else 0 end)
                                       keep (dense_rank last order by
                 case when od.planned_sequence = p.wro_seq then 1 else 0 end, od.actual_sequence) as ow_odwolany,
           -- odwolane stacje (bez duplikatow)
           count(distinct case when od.is_cancelled then od.planned_sequence end)          as liczba_odwolanych
    from kurs k
    join plan p
         on  p.schedule_id = k.schedule_id
         and p.order_id    = k.order_id
    join silver.operation_details od
         on  od.ophe_id = k.ophe_id
    group by k.ophe_id
),
pt as (          -- planowe czasy jako DATE (godzina 'HH24:MI:SS' + offset dnia)
    select p.*,
           nvl(p.start_dep_day,0)  + (to_date(p.start_dep_time, 'HH24:MI:SS') - trunc(to_date(p.start_dep_time, 'HH24:MI:SS'))) as start_dep_d,
           nvl(p.koniec_arr_day,0) + (to_date(p.koniec_arr_time,'HH24:MI:SS') - trunc(to_date(p.koniec_arr_time,'HH24:MI:SS'))) as koniec_arr_d,
           case when p.wro_arr_time is not null then
                nvl(p.wro_arr_day,0) + (to_date(p.wro_arr_time,'HH24:MI:SS') - trunc(to_date(p.wro_arr_time,'HH24:MI:SS'))) end as wro_arr_d,
           case when p.wro_dep_time is not null then
                nvl(p.wro_dep_day,0) + (to_date(p.wro_dep_time,'HH24:MI:SS') - trunc(to_date(p.wro_dep_time,'HH24:MI:SS'))) end as wro_dep_d
    from plan p
)
select
    -- klucz kursu
    k.operating_date,
    k.ophe_id,
    k.schedule_id,
    k.order_id,
    k.train_order_id,
    -- status
    k.train_status,
    case when k.train_status = 'X' then 1 else 0 end                          as czy_odwolany,
    case when k.train_status = 'C'                  then 1
         when o.ok_jest = 1 and o.ok_dojechal = 1   then 1
         else 0 end                                                           as czy_dojechal,
    case when k.train_status = 'C' and nvl(o.ok_jest,0) = 0
         then 1 else 0 end                                                    as czy_koniec_poza_pomiarem,
    nvl(o.liczba_odwolanych, 0)                                               as liczba_stacji_odwolanych,
    -- pociag (wartosci startowe z naglowka rozkladu)
    k.przewoznik,
    cr.name                                                                   as przewoznik_nazwa,
    k.kategoria,
    cc.name                                                                   as kategoria_nazwa,
    k.nr_pociagu,
    k.nazwa_pociagu,
    -- relacja wg planu
    p.start_dsta                                                              as relacja_od_id,
    st_od.name                                                                as relacja_od,
    p.koniec_dsta                                                             as relacja_do_id,
    st_do.name                                                                as relacja_do,
    case when p.wro_seq = p.start_seq  then 'START'
         when p.wro_seq = p.koniec_seq then 'KONIEC'
         else 'PRZEJAZD' end                                                  as rola_wroclawia,
    -- start: plan / rzeczywistosc
    k.operating_date + p.start_dep_d                                          as plan_odjazd_start,
    cast(o.start_odj_ts as date)                                              as rz_odjazd_start,
    o.op_start_min                                                            as opoznienie_start_min,
    -- koniec wg planu: plan / rzeczywistosc
    -- (C bez pomiaru na koncu, np. stacja zagraniczna -> ostatnia potwierdzona stacja)
    k.operating_date + p.koniec_arr_d                                         as plan_przyjazd_koniec,
    case when o.ok_jest = 1 and o.ok_dojechal = 1
         then cast(o.ok_arr_ts as date)
         when k.train_status = 'C' and o.ol_jest = 1
         then cast(o.ol_arr_ts as date) end                                   as rz_przyjazd_koniec,
    case when o.ok_jest = 1 and o.ok_dojechal = 1 then o.ok_delay
         when k.train_status = 'C' and o.ol_jest = 1 then o.ol_delay end      as opoznienie_koniec_min,
    -- ostatnia faktycznie osiagnieta stacja
    case when o.ol_jest = 1 then o.ol_dsta end                                as ostatnia_stacja_id,
    case when o.ol_jest = 1 then st_ol.name end                               as ostatnia_stacja_nazwa,
    case when o.ol_jest = 1 then cast(o.ol_arr_ts as date) end                as rz_przyjazd_ostatnia,
    case when o.ol_jest = 1 then o.ol_delay end                               as opoznienie_ostatnia_min,
    -- Wroclaw: plan / rzeczywistosc
    k.operating_date + p.wro_arr_d                                            as plan_wro_przyjazd,
    k.operating_date + p.wro_dep_d                                            as plan_wro_odjazd,
    case when o.ow_jest = 1 then cast(o.ow_arr_ts as date) end                as rz_wro_przyjazd,
    case when o.ow_jest = 1 then cast(o.ow_dep_ts as date) end                as rz_wro_odjazd,
    case when o.ow_jest = 1 then o.ow_arr_delay end                           as opoznienie_wro_przyjazd_min,
    case when o.ow_jest = 1 then o.ow_dep_delay end                           as opoznienie_wro_odjazd_min,
    case when o.ow_jest = 1 then o.ow_odwolany else 0 end                     as czy_wro_odwolany,
    -- czas przejazdu planowy (cala relacja)
    round((p.koniec_arr_d - p.start_dep_d) * 1440)                            as plan_czas_przejazdu_min
from kurs k
join pt p
     on  p.schedule_id = k.schedule_id
     and p.order_id    = k.order_id
left join op o
     on  o.ophe_id = k.ophe_id
left join silver.def_station st_od on st_od.id = p.start_dsta
left join silver.def_station st_do on st_do.id = p.koniec_dsta
left join silver.def_station st_ol on st_ol.id = o.ol_dsta
outer apply (
    select c.name
      from silver.def_commercial_category c
     where c.code         = k.kategoria
       and c.carrier_code = k.przewoznik
     order by c.loaded_at desc
     fetch first 1 row only
) cc
outer apply (
    select cr.name
      from silver.def_carrier cr
     where cr.code = k.przewoznik
       and k.operating_date between cr.valid_from and cr.valid_to
     order by cr.valid_from desc, cr.loaded_at desc
     fetch first 1 row only
) cr
;

grant select on silver.V_REP_WYKONANE_KURS to DEV_APP;