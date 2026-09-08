-- =====================================================================
-- V_REP_PUNCTUALITY_MONTHLY - punktualnosc i ranking tras w miesiacu.
--
-- Grain: month x route x train_type (zwiniete status + day_type).
-- Zrodlo: f_train_run_monthly (opoznienie terminalne, prog UTK on-time<=5).
--
-- Zasada: kursy ODWOLANE wykrywane po braku terminala (delayed_count IS NULL),
--         NIE po kodzie statusu -> zero hardkodu kodu 'Odwolany'.
-- Mianownik punktualnosci = kursy zrealizowane (runs_completed);
--         odwolane raportowane osobno (cancelled_count / cancelled_pct).
-- Surowe miary zachowane; % i srednie liczone tu (nie skladowane).
-- =====================================================================
CREATE OR REPLACE VIEW gold.v_rep_punctuality_monthly AS
WITH agg AS (
    select m.month,
           m.route_id,
           m.train_type_id,
           -- surowe miary (zwiniete po statusie/day_type)
           sum(m.runs_count)                                                     as runs_total,
           sum(case when m.delayed_count is not null then m.runs_count end)      as runs_completed,
           sum(case when m.delayed_count is null     then m.runs_count end)      as cancelled_count,
           sum(m.delayed_count)                                                  as delayed_count,
           sum(m.sum_terminal_delay_min)                                         as sum_terminal_delay_min,
           sum(m.sum_delayed_delay_min)                                          as sum_delayed_delay_min,
           max(m.max_terminal_delay_min)                                         as max_terminal_delay_min
    from   f_train_run_monthly m
    group  by m.month, m.route_id, m.train_type_id
)
select
    -- etykiety wymiarow (gotowe dla Metabase)
    a.month,
    fs.station_name || ' -> ' || ts.station_name as route_name,
    tt.category_name,
    tt.carrier_name,
    -- klucze (do dalszych joinow / filtrow)
    a.route_id,
    a.train_type_id,
    -- SUROWE MIARY (policz po swojemu jak chcesz)
    a.runs_total,
    a.runs_completed,
    a.cancelled_count,
    a.delayed_count,
    (a.runs_completed - a.delayed_count)          as on_time_count,
    a.sum_terminal_delay_min,
    a.sum_delayed_delay_min,
    a.max_terminal_delay_min,
    -- WYLICZENIA (wygoda; mianownik przez NULLIF)
    round( (a.runs_completed - a.delayed_count) / nullif(a.runs_completed,0) * 100, 2) as on_time_pct,
    round(  a.delayed_count                     / nullif(a.runs_completed,0) * 100, 2) as delayed_pct,
    round(  a.cancelled_count                   / nullif(a.runs_total,0)     * 100, 2) as cancelled_pct,
    round(  a.sum_terminal_delay_min            / nullif(a.runs_completed,0),      2) as avg_terminal_delay_min,
    round(  a.sum_delayed_delay_min             / nullif(a.delayed_count,0),       2) as avg_delayed_delay_min
from   agg a
join   d_route      dr on dr.id = a.route_id
join   d_station    fs on fs.id = dr.from_station_id
join   d_station    ts on ts.id = dr.to_station_id
join   d_train_type tt on tt.id = a.train_type_id;

grant select on gold.v_rep_punctuality_monthly to DEV_APP;