-- =============================================================================
-- silver.v_rep_utrudnienia_wro
-- -----------------------------------------------------------------------------
-- Utrudnienia kursow D-1..D-7 na stacji Wroclaw Glowny (60103) - jeden wiersz
-- na kurs i przyczyne. Dane kursu (dzien, pociag, relacja, opoznienia, status)
-- z silver.v_rep_stacja_wro, utrudnienie z disruption_header / def_disruption_cause.
-- Powiazanie utrudnienia z kursem: dzien + schedule_id + (order_id lub
-- train_order_id) + stacja 60103.
-- Przyczyna: kod ze slownika (z disruption_type_code albo z message, gdy API
-- przysyla tam kod, np. 'utr_40') -> opis ze slownika (szablon "Na odcinku od
-- stacji {..} do stacji {..}" zamieniony na "Na czesci trasy"); w innym
-- przypadku tekst komunikatu z API; bez kodu i komunikatu -> 'Nieokreslona'.
-- Komunikat: oryginalny tekst z API (najnowszy dla kursu i przyczyny), pusty
-- gdy message jest kodem ze slownika.
-- Kilka utrudnien tego samego kursu z ta sama przyczyna = jeden wiersz.
-- Surowe dane i reguly, bez formatowania.
-- =============================================================================

create or replace view silver.v_rep_utrudnienia_wro as
with ut as (     -- utrudnienia na stacji 60103 z przyczyna wg reguly
    select s.data_kursu, s.data_wro, s.ophe_id,
           s.przewoznik, s.kategoria, s.nr_pociagu, s.nazwa_pociagu,
           s.stacja_pocz, s.stacja_konc,
           s.czy_start, s.czy_koniec, s.czy_przelot,
           s.plan_przyjazd, s.plan_odjazd,
           s.op_przyjazd_min, s.op_odjazd_min,
           s.czy_odwolany,
           coalesce(c_kod.code, c_msg.code)                         as przyczyna_kod,
           case
               when coalesce(c_kod.code, c_msg.code) is not null then
                    regexp_replace(coalesce(c_kod.description, c_msg.description),
                                   'Na odcinku od stacji \{[^}]*\} do stacji \{[^}]*\}',
                                   'Na części trasy')
               when dh.message is not null then dh.message
               else 'Nieokreślona'
           end                                                      as przyczyna,
           case when c_msg.code is null then dh.message end         as komunikat,
           dh.snapshot_ts
      from silver.v_rep_stacja_wro s
      join silver.disruption_details dd
           on  dd.operating_date = s.data_kursu
           and dd.schedule_id    = s.schedule_id
           and (dd.order_id = s.order_id or dd.train_order_id = s.train_order_id)
           and dd.dsta_id        = 60103
      join silver.disruption_header dh
           on dh.id = dd.dihe_id
      left join silver.def_disruption_cause c_kod        -- kod w disruption_type_code
           on c_kod.code = dh.disruption_type_code
      left join silver.def_disruption_cause c_msg        -- kod przyslany w message
           on c_msg.code = trim(dh.message)
)
select data_kursu, data_wro, ophe_id,
       przewoznik, kategoria, nr_pociagu, nazwa_pociagu,
       stacja_pocz, stacja_konc,
       czy_start, czy_koniec, czy_przelot,
       plan_przyjazd, plan_odjazd,
       op_przyjazd_min, op_odjazd_min,
       czy_odwolany,
       przyczyna_kod,
       przyczyna,
       max(komunikat) keep (dense_rank last order by snapshot_ts) as komunikat,
       min(snapshot_ts)                                           as pierwsze_zgl
  from ut
 group by data_kursu, data_wro, ophe_id,
          przewoznik, kategoria, nr_pociagu, nazwa_pociagu,
          stacja_pocz, stacja_konc,
          czy_start, czy_koniec, czy_przelot,
          plan_przyjazd, plan_odjazd,
          op_przyjazd_min, op_odjazd_min,
          czy_odwolany,
          przyczyna_kod,
          przyczyna
;

grant select on silver.v_rep_utrudnienia_wro to DEV_APP;