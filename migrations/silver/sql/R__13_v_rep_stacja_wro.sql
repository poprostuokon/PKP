-- =============================================================================
-- silver.v_rep_stacja_wro
-- -----------------------------------------------------------------------------
-- Postoje na stacji Wroclaw Glowny (60103) w dniach D-7..D-1 (wg dnia postoju,
-- nocne kursy przypisane do dnia, w ktorym stoja we Wroclawiu) - jeden wiersz
-- na kurs. Plan i rzeczywistosc przyjazdu i odjazdu we Wroclawiu, opoznienia,
-- rola stacji (start / koniec / przelot), relacja wg planu, odwolanie,
-- utrudnienie na stacji. Surowe dane i reguly, bez formatowania.
-- Czasy actual_* z operation_details sa juz lokalne (bez AT TIME ZONE).
-- Opoznienie przyjazdu tylko przy rzeczywistym przyjezdzie, odjazdu tylko przy
-- rzeczywistym odjezdzie.
-- API czasem powtarza ten sam przystanek planu pod kolejnym actual_sequence -
-- bierzemy pierwszy wpis.
-- Nazwy przewoznika i kategorii przez podzapytania skalarne (cache po kluczu).
-- =============================================================================

create or replace view silver.v_rep_stacja_wro as
with prm as (    -- "dzis" liczone raz
    select /*+ materialize */ trunc(maintenance.pkg_tool.f_now_warsaw) as dzis
    from dual
),
kurs as (        -- kursy D-8..D-1 (D-8: nocne kursy stajace we Wroclawiu w D-7), ktorych plan zawiera Wroclaw Glowny
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
         on oh.operating_date between prm.dzis - 8 and prm.dzis - 1
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
wro as (         -- plan we Wroclawiu + granice planu (min/max z indeksu)
    select k.ophe_id,
           sd.order_number                                        as wro_seq,
           case when sd.arrival_time is not null then
                k.operating_date
              + nvl(sd.arrival_day,0)
              + numtodsinterval(to_number(substr(sd.arrival_time,1,2))*3600
                              + to_number(substr(sd.arrival_time,4,2))*60
                              + to_number(substr(sd.arrival_time,7,2)),'SECOND')
           end                                                    as plan_przyjazd,
           case when sd.departure_time is not null then
                k.operating_date
              + nvl(sd.departure_day,0)
              + numtodsinterval(to_number(substr(sd.departure_time,1,2))*3600
                              + to_number(substr(sd.departure_time,4,2))*60
                              + to_number(substr(sd.departure_time,7,2)),'SECOND')
           end                                                    as plan_odjazd,
           (select min(s1.order_number) from silver.schedule_details s1
             where s1.schedule_id = k.schedule_id and s1.order_id = k.order_id) as start_seq,
           (select max(s2.order_number) from silver.schedule_details s2
             where s2.schedule_id = k.schedule_id and s2.order_id = k.order_id) as koniec_seq
    from kurs k
    join silver.schedule_details sd
         on  sd.schedule_id = k.schedule_id
         and sd.order_id    = k.order_id
         and sd.dsta_id     = 60103
)
select
    -- klucz kursu
    k.operating_date                                                   as data_kursu,
    trunc(coalesce(w.plan_przyjazd, w.plan_odjazd))                    as data_wro,
    k.ophe_id,
    k.schedule_id,
    k.order_id,
    k.train_order_id,
    -- pociag
    k.przewoznik,
    (select max(cr.name) keep (dense_rank last order by cr.valid_from, cr.loaded_at)
       from silver.def_carrier cr
      where cr.code = k.przewoznik
        and k.operating_date between cr.valid_from and cr.valid_to)   as przewoznik_nazwa,
    k.kategoria,
    (select max(c.name) keep (dense_rank last order by c.loaded_at)
       from silver.def_commercial_category c
      where c.code         = k.kategoria
        and c.carrier_code = k.przewoznik)                             as kategoria_nazwa,
    k.nr_pociagu,
    k.nazwa_pociagu,
    -- relacja wg planu
    sd_od.dsta_id                                                      as stacja_pocz_id,
    st_od.name                                                         as stacja_pocz,
    sd_do.dsta_id                                                      as stacja_konc_id,
    st_do.name                                                         as stacja_konc,
    -- rola Wroclawia
    case when w.wro_seq = w.start_seq  then 1 else 0 end               as czy_start,
    case when w.wro_seq = w.koniec_seq then 1 else 0 end               as czy_koniec,
    case when w.wro_seq not in (w.start_seq, w.koniec_seq)
         then 1 else 0 end                                             as czy_przelot,
    -- przyjazd
    w.plan_przyjazd,
    cast(ow.actual_arrival as date)                                    as rz_przyjazd,
    case when ow.actual_arrival is not null
         then coalesce(ow.arrival_delay_min,
                       round((cast(ow.actual_arrival as date) - w.plan_przyjazd) * 1440))
    end                                                                as op_przyjazd_min,
    -- odjazd
    w.plan_odjazd,
    cast(ow.actual_departure as date)                                  as rz_odjazd,
    case when ow.actual_departure is not null
         then coalesce(ow.departure_delay_min,
                       round((cast(ow.actual_departure as date) - w.plan_odjazd) * 1440))
    end                                                                as op_odjazd_min,
    -- status
    k.train_status,
    case when k.train_status = 'X' or ow.is_cancelled
         then 1 else 0 end                                             as czy_odwolany,
    case when ow.is_confirmed then 1 else 0 end                        as czy_potwierdzony,
    -- utrudnienie na stacji Wroclaw Glowny
    case when exists (select 1
                        from silver.disruption_details dd
                       where dd.operating_date = k.operating_date
                         and dd.schedule_id    = k.schedule_id
                         and (dd.order_id = k.order_id or dd.train_order_id = k.train_order_id)
                         and dd.dsta_id        = 60103)
         then 1 else 0 end                                             as czy_utrudnienie
from kurs k
join wro w
     on w.ophe_id = k.ophe_id
left join silver.operation_details ow            -- wykonanie we Wroclawiu (pierwszy wpis)
     on  ow.ophe_id          = k.ophe_id
     and ow.planned_sequence = w.wro_seq
     and not exists (select 1
                       from silver.operation_details o2
                      where o2.ophe_id          = ow.ophe_id
                        and o2.planned_sequence = ow.planned_sequence
                        and o2.actual_sequence  < ow.actual_sequence)
left join silver.schedule_details sd_od          -- stacja poczatkowa planu
     on  sd_od.schedule_id  = k.schedule_id
     and sd_od.order_id     = k.order_id
     and sd_od.order_number = w.start_seq
left join silver.schedule_details sd_do          -- stacja koncowa planu
     on  sd_do.schedule_id  = k.schedule_id
     and sd_do.order_id     = k.order_id
     and sd_do.order_number = w.koniec_seq
left join silver.def_station st_od on st_od.id = sd_od.dsta_id
left join silver.def_station st_do on st_do.id = sd_do.dsta_id
cross join prm
where trunc(coalesce(w.plan_przyjazd, w.plan_odjazd)) between prm.dzis - 7 and prm.dzis - 1
;

grant select on silver.v_rep_stacja_wro to DEV_APP;