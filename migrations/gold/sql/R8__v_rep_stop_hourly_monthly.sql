-- =====================================================================
-- V_REP_STOP_HOURLY_MONTHLY - punktualnosc przyjazdow wg godziny/stacji.
--
-- Grain: month x route x station x hour x train_type (zwiniety day_type).
-- Zrodlo: f_train_stop_monthly. Progi UTK: on-time <=5, delayed >=6.
-- Odpowiada na: ktora godzina na ktorej stacji/trasie ma najwiecej opoznien.
-- =====================================================================
CREATE OR REPLACE VIEW gold.v_rep_stop_hourly_monthly AS
WITH agg AS (
    select m.month,
           m.route_id,
           m.station_id,
           m.hour_id,
           m.train_type_id,
           sum(m.arrivals_count)          as arrivals_count,
           sum(m.arrivals_on_time)        as arrivals_on_time,
           sum(m.arrivals_delayed)        as arrivals_delayed,
           sum(m.sum_arrival_delay_min)   as sum_arrival_delay_min,
           sum(m.sum_delayed_delay_min)   as sum_delayed_delay_min,
           max(m.max_arrival_delay_min)   as max_arrival_delay_min,
           sum(m.cancelled_count)         as cancelled_count
    from   f_train_stop_monthly m
    group  by m.month, m.route_id, m.station_id, m.hour_id, m.train_type_id
)
select
    -- etykiety wymiarow
    a.month,
    fs.station_name || ' -> ' || ts.station_name as route_name,
    ss.station_name                               as station_name,
    dh.hour_label,                                 -- np. '07:00-07:59'
    tt.category_name,
    tt.carrier_name,
    -- klucze
    a.route_id,
    a.station_id,
    a.hour_id,
    a.train_type_id,
    -- SUROWE MIARY
    a.arrivals_count,
    a.arrivals_on_time,
    a.arrivals_delayed,
    a.sum_arrival_delay_min,
    a.sum_delayed_delay_min,
    a.max_arrival_delay_min,
    a.cancelled_count,
    -- WYLICZENIA (mianownik przez NULLIF)
    round( a.arrivals_on_time / nullif(a.arrivals_count,0) * 100, 2)                        as on_time_pct,
    round( a.arrivals_delayed / nullif(a.arrivals_count,0) * 100, 2)                        as delayed_pct,
    round( a.sum_arrival_delay_min / nullif(a.arrivals_count,0), 2)                         as avg_arrival_delay_min,
    round( a.sum_delayed_delay_min / nullif(a.arrivals_delayed,0), 2)                       as avg_delayed_delay_min,
    round( a.cancelled_count / nullif(a.arrivals_count + a.cancelled_count,0) * 100, 2)     as cancelled_pct
from   agg a
join   d_route      dr on dr.id = a.route_id
join   d_station    fs on fs.id = dr.from_station_id
join   d_station    ts on ts.id = dr.to_station_id
join   d_station    ss on ss.id = a.station_id
join   d_hour       dh on dh.id = a.hour_id
join   d_train_type tt on tt.id = a.train_type_id;

grant select on gold.v_rep_stop_hourly_monthly to DEV_APP;