-- =============================================================================
-- silver.v_rep_trasa_wro
-- -----------------------------------------------------------------------------
-- Widok raportowy APEX (okno "Szczegóły połączenia"): przebieg trasy kursu od
-- Wrocławia Głównego (włącznie) do stacji końcowej - jeden wiersz na przystanek
-- z postojem. Planowe czasy przyjazdu/odjazdu z offsetem dnia, perony/tory (bez
-- BUS), kategoria i numer pociągu per stacja (wykrywanie zmian po stronie APEX)
-- oraz typ postoju. Obcięcie do celu i formatowanie robione w APEX.
-- =============================================================================

CREATE OR REPLACE VIEW silver.V_REP_TRASA_WRO as
with kurs as (   -- te same kursy co v_rep_rozklad_wro
    select sh.operating_date, sh.schedule_id, sh.order_id, sh.train_order_id,
           sh.carrier_code as przewoznik,
           sh.name         as nazwa_pociagu
    from silver.schedule_header sh
    where sh.is_active = 1
      and sh.operating_date >= trunc(maintenance.pkg_tool.f_now_warsaw) - 1
),
sdx as (   -- przystanki z czasami w sekundach od operating_date
    select sd.*,
           case when sd.arrival_time is not null then
                nvl(sd.arrival_day,0)*86400
              + to_number(substr(sd.arrival_time,1,2))*3600
              + to_number(substr(sd.arrival_time,4,2))*60
              + to_number(substr(sd.arrival_time,7,2))
           end as arr_sec,
           case when sd.departure_time is not null then
                nvl(sd.departure_day,0)*86400
              + to_number(substr(sd.departure_time,1,2))*3600
              + to_number(substr(sd.departure_time,4,2))*60
              + to_number(substr(sd.departure_time,7,2))
           end as dep_sec
    from silver.schedule_details sd
),
wro as (   -- Wroclaw Glowny: odjazd, nie "tylko dla wysiadajacych"
    select x.schedule_id, x.order_id, x.order_number as wro_order
    from sdx x
    where x.dsta_id = 60103
      and x.dep_sec is not null
      and nvl(x.dstty_id,0) <> 2
)
select
    k.operating_date,
    k.schedule_id,
    k.order_id,
    k.train_order_id,
    k.przewoznik,
    k.nazwa_pociagu,
    -- stacja
    s.order_number                                   as stacja_kolejnosc,
    st.id                                            as stacja_id,
    st.name                                          as stacja_nazwa,
    case when s.order_number = w.wro_order then 1 else 0 end as czy_wroclaw,
    case when s.dep_sec is null then 1 else 0 end    as czy_stacja_koncowa,
    -- czasy
    case when s.arr_sec is not null
         then k.operating_date + numtodsinterval(s.arr_sec,'SECOND') end as przyjazd,
    case when s.dep_sec is not null
         then k.operating_date + numtodsinterval(s.dep_sec,'SECOND') end as odjazd,
    -- peron / tor (bez BUS i smieci)
    case when regexp_like(nvl(s.arrival_platform, s.departure_platform),'^\d+[a-z]?$','i')
         then nvl(s.arrival_platform, s.departure_platform) end as peron,
    case when regexp_like(nvl(s.arrival_track, s.departure_track),'^\d+[a-z]?$','i')
         then nvl(s.arrival_track, s.departure_track) end       as tor,
    -- pociag na tej stacji (odjazd, a na stacji koncowej przyjazd)
    nvl(s.departure_category, s.arrival_category)    as kategoria,
    cc.name                                          as kategoria_nazwa,
    nvl(s.departure_train_no, s.arrival_train_no)    as nr_pociagu,
    -- typ postoju
    s.dstty_id                                       as typ_postoju_id,
    stt.description                                  as typ_postoju_opis
from kurs k
join wro w
     on  w.schedule_id = k.schedule_id
     and w.order_id    = k.order_id
join sdx s
     on  s.schedule_id  = k.schedule_id
     and s.order_id     = k.order_id
     and s.order_number >= w.wro_order                         -- od Wroclawia wlacznie
     and (s.arr_sec is not null or s.order_number = w.wro_order) -- tylko postoje
join silver.def_station st
     on  st.id = s.dsta_id
left join silver.def_stop_type stt
     on  stt.id = s.dstty_id
outer apply (
    select c.name
      from silver.def_commercial_category c
     where c.code         = nvl(s.departure_category, s.arrival_category)
       and c.carrier_code = k.przewoznik
     order by c.loaded_at desc
     fetch first 1 row only
) cc
;

grant select on silver.V_REP_TRASA_WRO to DEV_APP;