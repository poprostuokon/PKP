-- =============================================================================
-- gold.v_rep_wro_dzien_tyg_monthly
-- -----------------------------------------------------------------------------
-- Punktualnosc przyjazdow i odjazdow na stacji Wroclaw Glowny (60103) wg
-- miesiaca i dnia tygodnia. Grain: miesiac x kierunek (P/O) x dzien tygodnia
-- (1 = poniedzialek ... 7 = niedziela, niezaleznie od NLS).
-- Zrodla: f_train_stop_daily (P), f_train_dep_daily (O) + d_date.
-- Surowe liczniki i sumy; liczba dni = ile dat danego dnia tygodnia mialo dane.
-- =============================================================================

create or replace view gold.v_rep_wro_dzien_tyg_monthly as
with z as (
    select date_id, 'P' as kierunek,
           arrivals_count        as n,
           arrivals_on_time      as n_ok,
           arrivals_delayed      as n_late,
           cancelled_count       as n_odw,
           sum_arrival_delay_min as sum_op
      from gold.f_train_stop_daily
     where station_id = 60103
    union all
    select date_id, 'O',
           departures_count,
           departures_on_time,
           departures_delayed,
           cancelled_count,
           sum_departure_delay_min
      from gold.f_train_dep_daily
     where station_id = 60103
)
select d.year * 100 + d.month                                   as month,
       to_char(d.full_date, 'YYYY-MM')                          as month_txt,
       z.kierunek,
       trunc(d.full_date) - trunc(d.full_date, 'IW') + 1        as dzien_tyg,
       sum(z.n)                                                 as n,
       sum(z.n_ok)                                              as n_ok,
       sum(z.n_late)                                            as n_late,
       sum(z.n_odw)                                             as n_odw,
       sum(z.sum_op)                                            as sum_op,
       count(distinct z.date_id)                                as liczba_dni
  from z
  join gold.d_date d on d.id = z.date_id
 group by d.year * 100 + d.month,
          to_char(d.full_date, 'YYYY-MM'),
          z.kierunek,
          trunc(d.full_date) - trunc(d.full_date, 'IW') + 1;

grant select on gold.v_rep_wro_dzien_tyg_monthly to DEV_APP;