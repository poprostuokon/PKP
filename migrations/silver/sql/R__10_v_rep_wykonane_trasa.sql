-- =============================================================================
-- silver.v_rep_wykonane_trasa
-- -----------------------------------------------------------------------------
-- Widok raportowy APEX (strona 6, Ajax POBIERZ_TRASE): przebieg zakonczonych
-- kursow D-1..D-7 przez Wroclaw Glowny (60103). Jeden wiersz = kurs x postoj
-- na calej trasie (start -> koniec). Plan vs rzeczywistosc przyjazdu/odjazdu,
-- opoznienia, odwolane postoje, brak pomiaru (stacje poza siecia PKP PLK),
-- peron/tor (tylko cyfry + litera), pociag na stacji (kategoria/numer),
-- typ postoju oraz flagi i opisy utrudnien z v_rep_wykonane_utrudnienia.
-- Filtrowac prostym select po ophe_id (agregat JSON nad widokiem = wolny plan).
-- Tylko surowe dane, bez formatowania. Czasy actual_* sa juz lokalne.
-- =============================================================================

CREATE OR REPLACE FORCE VIEW silver.V_REP_WYKONANE_TRASA as
with prm as (    -- "dzis" liczone raz
    select /*+ materialize */ trunc(maintenance.pkg_tool.f_now_warsaw) as dzis
    from dual
),
kurs as (        -- te same kursy co v_rep_wykonane_kurs
    select /*+ materialize */
           oh.id              as ophe_id,
           oh.operating_date,
           oh.schedule_id,
           oh.order_id,
           oh.train_order_id,
           oh.train_status,
           sh.carrier_code    as przewoznik,
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
sd as (          -- przystanki planu (tylko plany z kurs) + pierwsza/ostatnia stacja
    select /*+ materialize */
           s.*,
           min(s.order_number) over (partition by s.schedule_id, s.order_id) as start_seq,
           max(s.order_number) over (partition by s.schedule_id, s.order_id) as koniec_seq
    from silver.schedule_details s
    join (select distinct schedule_id, order_id from kurs) kk
         on  kk.schedule_id = s.schedule_id
         and kk.order_id    = s.order_id
),
od as (          -- wykonanie: jeden wpis na planned_sequence (najpozniejsza actual_sequence)
    select *
    from (
        select d.*,
               row_number() over (partition by d.ophe_id, d.planned_sequence
                                  order by d.actual_sequence desc) as rn
        from silver.operation_details d
        join kurs k on k.ophe_id = d.ophe_id
    )
    where rn = 1
),
cat as (         -- slownik kategorii: jedna (najnowsza) wersja na code + carrier
    select code, carrier_code, name
    from (
        select c.code, c.carrier_code, c.name,
               row_number() over (partition by c.code, c.carrier_code
                                  order by c.loaded_at desc) as rn
        from silver.def_commercial_category c
    )
    where rn = 1
),
ut_pos as (      -- mapowanie stacji od/do utrudnienia na pozycje w planie kursu (JEDEN join)
    select u.ophe_id, u.dihe_id, u.stacja_od, u.stacja_do, u.opis,
           min(case when p.dsta_id = u.dsta_od then p.order_number end) as pos_od,
           max(case when p.dsta_id = u.dsta_do then p.order_number end) as pos_do
    from silver.v_rep_wykonane_utrudnienia u
    join kurs k
         on  k.ophe_id = u.ophe_id
    join sd p
         on  p.schedule_id = k.schedule_id
         and p.order_id    = k.order_id
         and p.dsta_id in (u.dsta_od, u.dsta_do)
    group by u.ophe_id, u.dihe_id, u.stacja_od, u.stacja_do, u.opis
),
ut as (          -- utrudnienia z zakresem pozycji (obie stacje musza byc na trasie)
    select ophe_id, stacja_od, stacja_do, opis,
           least(pos_od, pos_do)    as seq_od,
           greatest(pos_od, pos_do) as seq_do
    from ut_pos
    where pos_od is not null and pos_do is not null
),
ut_flag as (     -- flagi per przystanek: rozwiniecie zakresow na przystanki, liczone RAZ
    select ut.ophe_id, p.order_number,
           1                                                            as czy_stacja_utrudniona,
           max(case when p.order_number < ut.seq_do then 1 else 0 end)  as czy_odcinek_utrudniony
    from ut
    join kurs k
         on  k.ophe_id = ut.ophe_id
    join sd p
         on  p.schedule_id  = k.schedule_id
         and p.order_id     = k.order_id
         and p.order_number between ut.seq_od and ut.seq_do
    group by ut.ophe_id, p.order_number
),
ut_start as (    -- utrudnienia zaczynajace sie na danej pozycji (do opisu przy stacji)
    select ophe_id, seq_od,
           count(*)                                                     as liczba_utrudnien_start,
           listagg(opis || ' [' || stacja_od || ' → ' || stacja_do || ']', chr(10))
               within group (order by seq_do, opis)                     as utrudnienia_start_txt
    from ut
    group by ophe_id, seq_od
)
select
    -- klucz kursu
    k.operating_date,
    k.ophe_id,
    k.schedule_id,
    k.order_id,
    k.train_order_id,
    k.train_status,
    k.przewoznik,
    k.nazwa_pociagu,
    -- stacja
    s.order_number                                               as stacja_kolejnosc,
    s.dsta_id                                                    as stacja_id,
    st.name                                                      as stacja_nazwa,
    case when s.dsta_id = 60103             then 1 else 0 end    as czy_wroclaw,
    case when s.order_number = s.start_seq  then 1 else 0 end    as czy_start,
    case when s.order_number = s.koniec_seq then 1 else 0 end    as czy_koniec,
    -- plan
    case when s.arrival_time is not null then
         k.operating_date + nvl(s.arrival_day,0)
           + (to_date(s.arrival_time,'HH24:MI:SS') - trunc(to_date(s.arrival_time,'HH24:MI:SS'))) end   as plan_przyjazd,
    case when s.departure_time is not null then
         k.operating_date + nvl(s.departure_day,0)
           + (to_date(s.departure_time,'HH24:MI:SS') - trunc(to_date(s.departure_time,'HH24:MI:SS'))) end as plan_odjazd,
    -- wykonanie (czasy w operation_details sa juz lokalne)
    cast(o.actual_arrival   as date)                              as rz_przyjazd,
    cast(o.actual_departure as date)                              as rz_odjazd,
    o.arrival_delay_min                                           as opoznienie_przyjazd_min,
    o.departure_delay_min                                         as opoznienie_odjazd_min,
    case when o.is_confirmed then 1 else 0 end                    as czy_potwierdzony,
    case when o.is_cancelled then 1 else 0 end                    as czy_odwolany,
    case when o.ophe_id is null then 1 else 0 end                 as czy_brak_pomiaru,
    -- peron / tor (bez BUS i smieci)
    case when regexp_like(nvl(s.arrival_platform, s.departure_platform),'^\d+[a-z]?$','i')
         then nvl(s.arrival_platform, s.departure_platform) end  as peron,
    case when regexp_like(nvl(s.arrival_track, s.departure_track),'^\d+[a-z]?$','i')
         then nvl(s.arrival_track, s.departure_track) end        as tor,
    -- pociag na tej stacji (odjazd, a na stacji koncowej przyjazd)
    nvl(s.departure_category, s.arrival_category)                as kategoria,
    c.name                                                       as kategoria_nazwa,
    nvl(s.departure_train_no, s.arrival_train_no)                as nr_pociagu,
    -- typ postoju
    s.dstty_id                                                   as typ_postoju_id,
    stt.description                                              as typ_postoju_opis,
    -- utrudnienia
    nvl(f.czy_stacja_utrudniona, 0)                              as czy_stacja_utrudniona,
    nvl(f.czy_odcinek_utrudniony, 0)                             as czy_odcinek_utrudniony,   -- odcinek od tej stacji do nastepnej
    nvl(us.liczba_utrudnien_start, 0)                            as liczba_utrudnien_start,
    us.utrudnienia_start_txt                                     as utrudnienia_start_txt     -- opisy rozdzielone chr(10)
from kurs k
join sd s
     on  s.schedule_id = k.schedule_id
     and s.order_id    = k.order_id
     and (s.arrival_time is not null or s.order_number = s.start_seq)   -- tylko postoje
left join od o
     on  o.ophe_id          = k.ophe_id
     and o.planned_sequence = s.order_number
left join silver.def_station st
     on  st.id = s.dsta_id
left join silver.def_stop_type stt
     on  stt.id = s.dstty_id
left join cat c
     on  c.code         = nvl(s.departure_category, s.arrival_category)
     and c.carrier_code = k.przewoznik
left join ut_flag f
     on  f.ophe_id      = k.ophe_id
     and f.order_number = s.order_number
left join ut_start us
     on  us.ophe_id = k.ophe_id
     and us.seq_od  = s.order_number
;

grant select on silver.V_REP_WYKONANE_TRASA to DEV_APP;