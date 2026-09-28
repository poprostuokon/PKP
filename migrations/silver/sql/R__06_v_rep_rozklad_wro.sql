-- =============================================================================
-- silver.v_rep_rozklad_wro
-- -----------------------------------------------------------------------------
-- Widok raportowy APEX (strona "Rozkład jazdy"): połączenia bezpośrednie ze
-- stacji Wrocław Główny - jeden wiersz na kurs × stację z postojem za Wrocławiem.
-- Czasy z offsetem dnia, perony/tory (bez BUS), pociąg z wiersza Wrocławia,
-- relacja kursu, typ postoju i czas przejazdu. Tylko aktywne plany, od dziś
-- wg dnia odjazdu z Wrocławia. Surowe dane - formatowanie po stronie APEX.
-- =============================================================================

CREATE OR REPLACE VIEW silver.V_REP_ROZKLAD_WRO as
with kurs as (   -- kursy aktywne; od wczoraj, bo kurs z wczoraj moze byc we Wroclawiu po polnocy
    select sh.operating_date, sh.schedule_id, sh.order_id, sh.train_order_id,
           sh.carrier_code    as przewoznik,
           sh.category_code   as kategoria_hdr,
           sh.national_number as nr_pociagu_hdr,
           sh.name            as nazwa_pociagu
    from silver.schedule_header sh
    where sh.is_active = 1
      and sh.operating_date >= trunc(maintenance.pkg_tool.f_now_warsaw) - 1
),
sdx as (   -- przystanki z czasami w sekundach od operating_date (z offsetem dnia)
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
wro as (   -- Wroclaw Glowny: musi byc odjazd i nie "tylko dla wysiadajacych" (dstty_id = 2)
    select x.schedule_id, x.order_id,
           x.order_number       as wro_order,
           x.dep_sec            as wro_dep_sec,
           x.departure_platform as wro_peron_raw,
           x.departure_track    as wro_tor_raw,
           x.departure_category as wro_kategoria,
           x.departure_train_no as wro_nr_pociagu
    from sdx x
    where x.dsta_id = 60103
      and x.dep_sec is not null
      and nvl(x.dstty_id,0) <> 2
),
ep as (    -- pierwsza / ostatnia stacja kursu (order_number moze byc ujemny)
    select schedule_id, order_id,
           min(order_number) as min_on,
           max(order_number) as max_on
    from silver.schedule_details
    group by schedule_id, order_id
)
select
    k.operating_date,
    k.schedule_id,
    k.order_id,
    k.train_order_id,
    -- pociag (wartosci z odjazdu we Wroclawiu, fallback na naglowek)
    k.przewoznik,
    cr.name                                 as przewoznik_nazwa,
    nvl(w.wro_kategoria,  k.kategoria_hdr)  as kategoria,
    cc.name                                 as kategoria_nazwa,
    nvl(w.wro_nr_pociagu, k.nr_pociagu_hdr) as nr_pociagu,
    k.nazwa_pociagu,
    -- relacja calego kursu
    st_od.name                              as relacja_od,
    st_do.name                              as relacja_do,
    -- Wroclaw
    trunc(k.operating_date + w.wro_dep_sec/86400)              as dzien_odjazdu,
    k.operating_date + numtodsinterval(w.wro_dep_sec,'SECOND') as wro_odjazd,
    case when regexp_like(w.wro_peron_raw,'^\d+[a-z]?$','i') then w.wro_peron_raw end as wro_peron,
    case when regexp_like(w.wro_tor_raw,  '^\d+[a-z]?$','i') then w.wro_tor_raw   end as wro_tor,
    -- stacja docelowa
    s.order_number                          as stacja_kolejnosc,
    st.id                                   as stacja_id,
    st.name                                 as stacja_nazwa,
    k.operating_date + numtodsinterval(s.arr_sec,'SECOND')     as stacja_przyjazd,
    case when s.dep_sec is not null
         then k.operating_date + numtodsinterval(s.dep_sec,'SECOND') end as stacja_odjazd,
    case when regexp_like(nvl(s.arrival_platform, s.departure_platform),'^\d+[a-z]?$','i')
         then nvl(s.arrival_platform, s.departure_platform) end as stacja_peron,
    case when regexp_like(nvl(s.arrival_track, s.departure_track),'^\d+[a-z]?$','i')
         then nvl(s.arrival_track, s.departure_track) end       as stacja_tor,
    s.dstty_id                                                   as stacja_typ_postoju_id,
    stt.description                                              as stacja_typ_postoju_opis,
    case when s.dep_sec is null then 1 else 0 end                as czy_stacja_koncowa,
    -- czas podrozy
        round((s.arr_sec - w.wro_dep_sec)/60)                        as czas_przejazdu_min,
    trunc(round((s.arr_sec - w.wro_dep_sec)/60) / 60) || 'h:'
      || lpad(mod(round((s.arr_sec - w.wro_dep_sec)/60), 60), 2, '0') || 'min' as czas_przejazdu
from kurs k
join wro w
     on  w.schedule_id = k.schedule_id
     and w.order_id    = k.order_id
join sdx s
     on  s.schedule_id  = k.schedule_id
     and s.order_id     = k.order_id
     and s.order_number > w.wro_order        -- tylko stacje ZA Wrocławiem
     and s.arr_sec is not null               -- pociag sie zatrzymuje
join silver.def_station st
     on  st.id = s.dsta_id
join ep
     on  ep.schedule_id = k.schedule_id
     and ep.order_id    = k.order_id
left join silver.schedule_details sd_od
     on  sd_od.schedule_id  = k.schedule_id
     and sd_od.order_id     = k.order_id
     and sd_od.order_number = ep.min_on
left join silver.def_station st_od
     on  st_od.id = sd_od.dsta_id
left join silver.schedule_details sd_do
     on  sd_do.schedule_id  = k.schedule_id
     and sd_do.order_id     = k.order_id
     and sd_do.order_number = ep.max_on
left join silver.def_station st_do
     on  st_do.id = sd_do.dsta_id
left join silver.def_stop_type stt
     on  stt.id = s.dstty_id
outer apply (   -- kategoria handlowa: klucz code + carrier_code, przy przeladowaniach najnowsza
    select c.name
      from silver.def_commercial_category c
     where c.code         = nvl(w.wro_kategoria, k.kategoria_hdr)
       and c.carrier_code = k.przewoznik
     order by c.loaded_at desc
     fetch first 1 row only
) cc
outer apply (   -- przewoznik: wersja obowiazujaca w dniu kursu, przy remisie najnowsza
    select cr.name
      from silver.def_carrier cr
     where cr.code = k.przewoznik
       and k.operating_date between cr.valid_from and cr.valid_to
     order by cr.valid_from desc, cr.loaded_at desc
     fetch first 1 row only
) cr
where k.operating_date + w.wro_dep_sec/86400 >= trunc(maintenance.pkg_tool.f_now_warsaw)
;

grant select on silver.V_REP_ROZKLAD_WRO to DEV_APP;
