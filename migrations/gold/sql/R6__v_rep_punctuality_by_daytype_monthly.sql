-- =====================================================================
-- V_REP_PUNCTUALITY_BY_DAYTYPE_MONTHLY - punktualnosc w rozbiciu WD/WE.
--
-- Grain: month x route x train_type x DAY_TYPE (WD/WE).
-- Zrodlo: f_train_run_monthly. Logika identyczna jak v_rep_punctuality_monthly,
--         roznica: day_type NIE jest zwijany - zostaje wymiarem raportu.
-- =====================================================================
CREATE OR REPLACE VIEW gold.v_rep_punctuality_by_daytype_monthly AS
WITH agg AS (
    select m.month,
           m.route_id,
           m.train_type_id,
           m.day_type,
           -- surowe miary punktualnosci
           sum(m.runs_count)                                                as runs_total,
           sum(case when m.delayed_count is not null then m.runs_count end) as runs_completed,
           sum(case when m.delayed_count is null     then m.runs_count end) as cancelled_count,
           sum(m.delayed_count)                                             as delayed_count,
           sum(m.sum_terminal_delay_min)                                    as sum_terminal_delay_min,
           sum(m.sum_delayed_delay_min)                                     as sum_delayed_delay_min,
           max(m.max_terminal_delay_min)                                    as max_terminal_delay_min,
           -- surowe miary czasu przejazdu
           sum(m.travel_runs_count)                                         as travel_runs_count,
           sum(m.sum_planned_travel_min)                                    as sum_planned_travel_min,
           sum(m.sum_actual_travel_min)                                     as sum_actual_travel_min,
           min(m.min_actual_travel_min)                                     as min_actual_travel_min,
           max(m.max_actual_travel_min)                                     as max_actual_travel_min
    from   f_train_run_monthly m
    group  by m.month, m.route_id, m.train_type_id, m.day_type
)
select
    -- etykiety wymiarow
    a.month,
    a.day_type,                                            -- 'WD' dni robocze / 'WE' weekend
    fs.station_name || ' -> ' || ts.station_name as route_name,
    tt.category_name,
    tt.carrier_name,
    -- klucze
    a.route_id,
    a.train_type_id,
    -- SUROWE MIARY punktualnosci
    a.runs_total,
    a.runs_completed,
    a.cancelled_count,
    a.delayed_count,
    (a.runs_completed - a.delayed_count)          as on_time_count,
    a.sum_terminal_delay_min,
    a.sum_delayed_delay_min,
    a.max_terminal_delay_min,
    -- SUROWE MIARY czasu przejazdu [min]
    a.travel_runs_count,
    a.sum_planned_travel_min,
    a.sum_actual_travel_min,
    a.min_actual_travel_min,
    a.max_actual_travel_min,
    -- WYLICZENIA punktualnosci
    round( (a.runs_completed - a.delayed_count) / nullif(a.runs_completed,0) * 100, 2) as on_time_pct,
    round(  a.delayed_count                     / nullif(a.runs_completed,0) * 100, 2) as delayed_pct,
    round(  a.cancelled_count                   / nullif(a.runs_total,0)     * 100, 2) as cancelled_pct,
    round(  a.sum_terminal_delay_min            / nullif(a.runs_completed,0),      2) as avg_terminal_delay_min,
    round(  a.sum_delayed_delay_min             / nullif(a.delayed_count,0),       2) as avg_delayed_delay_min,
    -- WYLICZENIA czasu przejazdu [min]
    round(  a.sum_planned_travel_min            / nullif(a.travel_runs_count,0),   2) as avg_planned_travel_min,
    round(  a.sum_actual_travel_min             / nullif(a.travel_runs_count,0),   2) as avg_actual_travel_min
from   agg a
join   d_route      dr on dr.id = a.route_id
join   d_station    fs on fs.id = dr.from_station_id
join   d_station    ts on ts.id = dr.to_station_id
join   d_train_type tt on tt.id = a.train_type_id;

grant select on gold.v_rep_punctuality_by_daytype_monthly to DEV_APP;