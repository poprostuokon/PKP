-- =====================================================================
-- V_REP_DISRUPTION_CAUSES_MONTHLY - ranking przyczyn utrudnien w miesiacu.
--
-- Grain: month x route x station x train_type x cause (zwiniete hour + day_type).
-- Zrodlo: f_train_disruption_monthly. Miara: liczba wystapien (dotkniete przystanki).
-- share_pct = udzial przyczyny w calosci utrudnien (trasa x stacja x miesiac),
--             liczony oknem SUM() OVER.
-- =====================================================================
CREATE OR REPLACE VIEW gold.v_rep_disruption_causes_monthly AS
WITH agg AS (
    select m.month,
           m.route_id,
           m.station_id,
           m.train_type_id,
           m.cause_id,
           sum(m.occurrences_count) as occurrences_count
    from   f_train_disruption_monthly m
    group  by m.month, m.route_id, m.station_id, m.train_type_id, m.cause_id
)
select
    -- etykiety wymiarow
    a.month,
    fs.station_name || ' -> ' || ts.station_name as route_name,
    ss.station_name                               as station_name,
    tt.category_name,
    tt.carrier_name,
    dc.cause_name,
    -- klucze
    a.route_id,
    a.station_id,
    a.train_type_id,
    a.cause_id,
    -- SUROWA MIARA
    a.occurrences_count,
    -- kontekst do udzialu: wszystkie utrudnienia trasa x stacja x miesiac
    sum(a.occurrences_count) over (partition by a.month, a.route_id, a.station_id) as occurrences_total,
    -- WYLICZENIE: udzial przyczyny [%]
    round( a.occurrences_count
           / nullif(sum(a.occurrences_count) over (partition by a.month, a.route_id, a.station_id), 0)
           * 100, 2)                                                              as share_pct
from   agg a
join   d_route            dr on dr.id = a.route_id
join   d_station          fs on fs.id = dr.from_station_id
join   d_station          ts on ts.id = dr.to_station_id
join   d_station          ss on ss.id = a.station_id
join   d_train_type       tt on tt.id = a.train_type_id
join   d_disruption_cause dc on dc.id = a.cause_id;

grant select on gold.v_rep_disruption_causes_monthly to DEV_APP;