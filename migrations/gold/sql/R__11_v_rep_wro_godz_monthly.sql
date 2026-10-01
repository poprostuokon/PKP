-- =============================================================================
-- gold.v_rep_wro_godz_monthly
-- -----------------------------------------------------------------------------
-- Punktualnosc przyjazdow i odjazdow na stacji Wroclaw Glowny (60103) wg
-- miesiaca i planowej godziny. Grain: miesiac x kierunek (P/O) x godzina.
-- Zrodla: f_train_stop_monthly (P - przyjazdy), f_train_dep_monthly (O - odjazdy).
-- Surowe liczniki i sumy (progi UTK: na czas <= 5 min, spoznione >= 6 min);
-- procenty i srednie liczone przy odczycie.
-- =============================================================================

create or replace view gold.v_rep_wro_godz_monthly as
with z as (
    select month, 'P' as kierunek, hour_id,
           arrivals_count        as n,
           arrivals_on_time      as n_ok,
           arrivals_delayed      as n_late,
           cancelled_count       as n_odw,
           sum_arrival_delay_min as sum_op
      from gold.f_train_stop_monthly
     where station_id = 60103
    union all
    select month, 'O', hour_id,
           departures_count,
           departures_on_time,
           departures_delayed,
           cancelled_count,
           sum_departure_delay_min
      from gold.f_train_dep_monthly
     where station_id = 60103
)
select z.month,
       substr(to_char(z.month), 1, 4) || '-' || substr(to_char(z.month), 5, 2) as month_txt,
       z.kierunek,
       z.hour_id,
       h.hour_label,
       sum(z.n)      as n,
       sum(z.n_ok)   as n_ok,
       sum(z.n_late) as n_late,
       sum(z.n_odw)  as n_odw,
       sum(z.sum_op) as sum_op
  from z
  join gold.d_hour h on h.id = z.hour_id
 group by z.month, z.kierunek, z.hour_id, h.hour_label;

grant select on gold.v_rep_wro_godz_monthly to DEV_APP;