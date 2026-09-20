-- =====================================================================
-- V_DISRUPTION_DAILY_TRACE - widok diagnostyczny do f_train_disruption_daily.
--
-- Jeden wiersz = jeden dotkniety przystanek (disruption_details) z policzonymi
-- kluczami GOLD (route_id, station_id, train_type_id, hour_id, cause_id) i
-- informacja, SKAD wziety zostal cause (TYPE czy MESSAGE). Filtrujesz po tych
-- samych id co w fakcie.
--
-- Uzycie:
--   SELECT * FROM gold.v_disruption_daily_trace
--    WHERE operating_date = DATE '2026-08-28'
--      AND route_id = :r AND station_id = :st AND train_type_id = :t
--      AND hour_id = :h AND cause_id = :c;
--
--   occurrences_count = COUNT(*)
--   in_fact='N'       = przystanek ODRZUCONY z faktu (brak route/type/hour/cause)
--   cause_source      = TYPE / MESSAGE / NULL (skad rozwiazano kod utrudnienia)
-- =====================================================================

CREATE OR REPLACE VIEW gold.v_disruption_daily_trace AS
WITH ep AS (          -- endpointy rozkladu per (schedule_id, order_id)
    select schedule_id, order_id,
           min(order_number) as min_on,
           max(order_number) as max_on
    from   schedule_details
    group by schedule_id, order_id
),
route_pair AS (       -- from/to stacja per (schedule_id, order_id)
    select ep.schedule_id, ep.order_id, f.dsta_id as from_station_id, t.dsta_id as to_station_id
    from   ep
    join   schedule_details f on f.schedule_id=ep.schedule_id and f.order_id=ep.order_id and f.order_number=ep.min_on
    join   schedule_details t on t.schedule_id=ep.schedule_id and t.order_id=ep.order_id and t.order_number=ep.max_on
)
select
    -- klucze GOLD (po nich filtrujesz, jak w fakcie)
    dd.operating_date,
    to_number(to_char(dd.operating_date,'YYYYMMDD')) as date_id,
    dr.id                    as route_id,
    dd.dsta_id               as station_id,
    coalesce(ttm.id, ttc.id) as train_type_id,
    to_number(substr(coalesce(sd.arrival_time, sd.departure_time),1,2)) as hour_id,
    coalesce(dc_t.id, dc_m.id) as cause_id,
    -- skad rozwiazano cause
    case when dc_t.id is not null then 'TYPE'
         when dc_m.id is not null then 'MESSAGE'
         else null end        as cause_source,
    -- identyfikatory zrodlowe (silver)
    dd.dihe_id,
    dd.schedule_id,
    dd.order_id,
    dd.train_order_id,
    dd.sequence_number,
    sh.category_code,
    sh.carrier_code,
    dh.disruption_type_code,
    dh.message,
    -- czy przystanek wszedl do faktu
    case when dr.id is not null
          and coalesce(ttm.id, ttc.id)  is not null
          and coalesce(dc_t.id, dc_m.id) is not null
          and (sd.arrival_time is not null or sd.departure_time is not null)
         then 'Y' else 'N' end as in_fact
from disruption_details dd
left join schedule_header sh
       on sh.operating_date = dd.operating_date and sh.schedule_id    = dd.schedule_id
      and sh.order_id       = dd.order_id       and sh.train_order_id = dd.train_order_id
left join disruption_header dh on dh.id = dd.dihe_id
left join schedule_details sd
       on sd.schedule_id = dd.schedule_id and sd.order_id = dd.order_id
      and sd.order_number = dd.sequence_number
left join route_pair rp on rp.schedule_id = dd.schedule_id and rp.order_id = dd.order_id
left join d_route dr on dr.from_station_id = rp.from_station_id and dr.to_station_id = rp.to_station_id
left join d_train_type ttm
       on ttm.category_code = sh.category_code and ttm.carrier_code = sh.carrier_code
      and dd.operating_date between ttm.valid_from and ttm.valid_to
left join d_train_type ttc
       on ttc.category_code = sh.category_code and ttc.carrier_code = sh.carrier_code
      and ttc.valid_to = DATE '2999-12-31'
left join d_disruption_cause dc_t on dc_t.cause_code = dh.disruption_type_code
left join d_disruption_cause dc_m on dc_m.cause_code = dh.message
where to_number(to_char(dd.operating_date,'YYYYMMDD')) in (
          select date_id from f_train_disruption_daily
      );

grant select on gold.v_disruption_daily_trace to DEV_APP;
