-- =============================================================================
-- gold.v_rep_wro_kierunki_monthly
-- -----------------------------------------------------------------------------
-- Kierunki pociagow na stacji Wroclaw Glowny (60103) wg miesiaca.
-- P (przyjazdy): stacja poczatkowa trasy - skad przyjezdzaja.
-- O (odjazdy):   stacja koncowa trasy    - dokad odjezdzaja.
-- Grain: miesiac x kierunek (P/O) x stacja. Zrodla: f_train_stop_monthly,
-- f_train_dep_monthly + d_route / d_station. Surowe liczniki i sumy.
-- =============================================================================

create or replace view gold.v_rep_wro_kierunki_monthly as
with z as (
    select f.month, 'P' as kierunek, r.from_station_id as stacja_id,
           f.arrivals_count        as n,
           f.arrivals_on_time      as n_ok,
           f.cancelled_count       as n_odw,
           f.sum_arrival_delay_min as sum_op
      from gold.f_train_stop_monthly f
      join gold.d_route r on r.id = f.route_id
     where f.station_id = 60103
    union all
    select f.month, 'O', r.to_station_id,
           f.departures_count,
           f.departures_on_time,
           f.cancelled_count,
           f.sum_departure_delay_min
      from gold.f_train_dep_monthly f
      join gold.d_route r on r.id = f.route_id
     where f.station_id = 60103
)
select z.month,
       substr(to_char(z.month), 1, 4) || '-' || substr(to_char(z.month), 5, 2) as month_txt,
       z.kierunek,
       z.stacja_id,
       s.station_name                as stacja,
       sum(z.n)                      as n,
       sum(z.n_ok)                   as n_ok,
       sum(z.n_odw)                  as n_odw,
       sum(z.sum_op)                 as sum_op
  from z
  join gold.d_station s on s.id = z.stacja_id
 group by z.month, z.kierunek, z.stacja_id, s.station_name;

grant select on gold.v_rep_wro_kierunki_monthly to DEV_APP;