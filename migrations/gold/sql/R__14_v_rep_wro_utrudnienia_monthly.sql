-- =============================================================================
-- gold.v_rep_wro_utrudnienia_monthly
-- -----------------------------------------------------------------------------
-- Utrudnienia na stacji Wroclaw Glowny (60103) wg miesiaca, dnia tygodnia
-- i przyczyny. Grain: miesiac x dzien tygodnia (1 = pn ... 7 = nd) x przyczyna.
-- Zrodlo: f_train_disruption_daily (miara: wystapienia = dotkniete postoje)
-- + d_date / d_disruption_cause. Typ dnia: WD - roboczy, WE - weekend.
-- =============================================================================

create or replace view gold.v_rep_wro_utrudnienia_monthly as
select d.year * 100 + d.month                                   as month,
       to_char(d.full_date, 'YYYY-MM')                          as month_txt,
       trunc(d.full_date) - trunc(d.full_date, 'IW') + 1        as dzien_tyg,
       case when d.is_weekend = 'T' then 'WE' else 'WD' end     as day_type,
       f.cause_id,
       c.cause_code,
       regexp_replace(c.cause_name,
                      'Na odcinku od stacji \{[^}]*\} do stacji \{[^}]*\}',
                      'Na części trasy')                        as przyczyna,
       sum(f.occurrences_count)                                 as wystapienia
  from gold.f_train_disruption_daily f
  join gold.d_date d             on d.id = f.date_id
  join gold.d_disruption_cause c on c.id = f.cause_id
 where f.station_id = 60103
 group by d.year * 100 + d.month,
          to_char(d.full_date, 'YYYY-MM'),
          trunc(d.full_date) - trunc(d.full_date, 'IW') + 1,
          case when d.is_weekend = 'T' then 'WE' else 'WD' end,
          f.cause_id, c.cause_code,
          regexp_replace(c.cause_name,
                         'Na odcinku od stacji \{[^}]*\} do stacji \{[^}]*\}',
                         'Na części trasy');

grant select on gold.v_rep_wro_utrudnienia_monthly to DEV_APP;