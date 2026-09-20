-- =====================================================================
-- V_REP_STATUS_SHARE_MONTHLY - udzial statusow kursow w miesiacu.
--
-- Grain: month x route x train_type x STATUS (zwiniety day_type).
-- Zrodlo: f_train_run_monthly.
-- share_pct = udzial danego statusu w calosci kursow (trasa x typ x miesiac),
--             liczony oknem SUM() OVER - bez self-joina.
-- Surowe miary zachowane (runs_count danego statusu + opoznienia).
-- =====================================================================
CREATE OR REPLACE VIEW gold.v_rep_status_share_monthly AS
WITH agg AS (
    select m.month,
           m.route_id,
           m.train_type_id,
           m.status_id,
           sum(m.runs_count)              as runs_count,
           sum(m.delayed_count)           as delayed_count,
           sum(m.sum_terminal_delay_min)  as sum_terminal_delay_min,
           sum(m.sum_delayed_delay_min)   as sum_delayed_delay_min,
           max(m.max_terminal_delay_min)  as max_terminal_delay_min
    from   f_train_run_monthly m
    group  by m.month, m.route_id, m.train_type_id, m.status_id
)
select
    -- etykiety wymiarow
    a.month,
    fs.station_name || ' -> ' || ts.station_name as route_name,
    tt.category_name,
    tt.carrier_name,
    st.status_name,
    -- klucze
    a.route_id,
    a.train_type_id,
    a.status_id,
    -- SUROWE MIARY (dla danego statusu)
    a.runs_count,
    a.delayed_count,
    a.sum_terminal_delay_min,
    a.sum_delayed_delay_min,
    a.max_terminal_delay_min,
    -- kontekst do udzialu: wszystkie kursy trasa x typ x miesiac
    sum(a.runs_count) over (partition by a.month, a.route_id, a.train_type_id) as runs_total_month,
    -- WYLICZENIE: udzial statusu w calosci [%]
    round( a.runs_count
           / nullif(sum(a.runs_count) over (partition by a.month, a.route_id, a.train_type_id), 0)
           * 100, 2)                                                          as share_pct
from   agg a
join   d_route        dr on dr.id = a.route_id
join   d_station      fs on fs.id = dr.from_station_id
join   d_station      ts on ts.id = dr.to_station_id
join   d_train_type   tt on tt.id = a.train_type_id
join   d_train_status st on st.id = a.status_id;

grant select on gold.v_rep_status_share_monthly to DEV_APP;