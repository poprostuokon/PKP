-- =============================================================================
-- silver.v_rep_wykonane_utrudnienia
-- -----------------------------------------------------------------------------
-- Widok pomocniczy dla v_rep_wykonane_trasa (strona 6): utrudnienia zakonczonych
-- kursow D-1..D-7 przez Wroclaw Glowny (60103). Jeden wiersz = utrudnienie
-- w kursie, z odcinkiem stacja od -> do (po dsta_id, bo numeracja sequence
-- z disruption_details nie zgadza sie z planem). Dopasowanie do kursu po
-- data + schedule_id + (order_id lub train_order_id). Opis: slownik przyczyn
-- (po kodzie lub message) > komunikat > kod; szablony {stacja_poczatkowa}/
-- {stacja_koncowa} podmienione na nazwy. Duplikaty (ta sama tresc na tym samym
-- odcinku) zwiniete do najnowszego utrudnienia.
-- =============================================================================

CREATE OR REPLACE VIEW silver.V_REP_WYKONANE_UTRUDNIENIA as
with prm as (    -- "dzis" liczone raz
    select /*+ materialize */ trunc(maintenance.pkg_tool.f_now_warsaw) as dzis
    from dual
),
kurs as (        -- te same kursy co v_rep_wykonane_kurs (plan przez Wroclaw Glowny)
    select oh.id as ophe_id, oh.operating_date, oh.schedule_id, oh.order_id, oh.train_order_id
    from prm
    join silver.operation_header oh
         on oh.operating_date between prm.dzis - 7 and prm.dzis - 1
    where exists (select 1
                    from silver.schedule_details w
                   where w.schedule_id = oh.schedule_id
                     and w.order_id    = oh.order_id
                     and w.dsta_id     = 60103)
),
u as (           -- utrudnienie w kursie: stacje od-do (numeracja utrudnien tylko do kolejnosci)
    select k.ophe_id, dd.dihe_id,
           min(dd.sequence_number)                                             as dis_seq_od,
           max(dd.sequence_number)                                             as dis_seq_do,
           min(dd.dsta_id) keep (dense_rank first order by dd.sequence_number) as dsta_od,
           max(dd.dsta_id) keep (dense_rank last  order by dd.sequence_number) as dsta_do,
           count(*)                                                            as liczba_przystankow
    from kurs k
    join silver.disruption_details dd
         on  dd.operating_date = k.operating_date
         and dd.schedule_id    = k.schedule_id
         and (dd.order_id = k.order_id or dd.train_order_id = k.train_order_id)
    group by k.ophe_id, dd.dihe_id
),
t as (           -- tekst: slownik (po kodzie lub po message) > komunikat > kod; podmiana nazw stacji
    select u.*,
           st_od.name                                                          as stacja_od,
           st_do.name                                                          as stacja_do,
           replace(replace(
               coalesce(
                   dc_kod.description,                                         -- disruption_type_code pasuje do slownika
                   dc_msg.description,                                         -- message to sam kod (np. utr_72)
                   dh.message,                                                 -- zwykly komunikat
                   dh.disruption_type_code                                     -- ostatecznie sam kod
               ),
               '{stacja_poczatkowa}', st_od.name),
               '{stacja_koncowa}',    st_do.name)                              as opis
    from u
    join silver.disruption_header dh             on dh.id = u.dihe_id
    left join silver.def_disruption_cause dc_kod on dc_kod.code = dh.disruption_type_code
    left join silver.def_disruption_cause dc_msg on dc_msg.code = trim(dh.message)
    left join silver.def_station st_od           on st_od.id = u.dsta_od
    left join silver.def_station st_do           on st_do.id = u.dsta_do
)
select ophe_id, dihe_id,
       dsta_od, stacja_od, dsta_do, stacja_do,
       dis_seq_od, dis_seq_do, liczba_przystankow, opis
from (
    select t.*,
           row_number() over (
               partition by t.ophe_id, t.dsta_od, t.dsta_do, t.opis   -- ta sama tresc na tym samym odcinku = jedno utrudnienie
               order by t.dihe_id desc
           ) as rn
    from t
)
where rn = 1
;

grant select on silver.V_REP_WYKONANE_UTRUDNIENIA to DEV_APP;