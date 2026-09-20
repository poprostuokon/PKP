-- =====================================================================
-- V_STOP_DAILY_TRACE - widok diagnostyczny do f_train_stop_daily.
--
-- Jeden wiersz = jeden przystanek z silver operations wziety do przeliczen,
-- z policzonymi kluczami GOLD (route_id, train_type_id, station_id, hour_id)
-- i efektywnym opoznieniem (confirmed + null = 0). Filtrujesz po tych samych
-- id co w fakcie i widzisz, jakie przystanki sie pod nie zgrupowaly.
--
-- Uzycie:
--   SELECT * FROM gold.v_stop_daily_trace
--    WHERE operating_date = DATE '2026-08-25'
--      AND route_id = :r AND train_type_id = :t AND station_id = :st AND hour_id = :h
--    ORDER BY eff_delay;
--
-- Weryfikacja miar faktu dla tej komorki:
--   arrivals_count        = COUNT(*) WHERE is_arrival='Y'
--   arrivals_on_time      = ... AND eff_delay <= 5
--   arrivals_delayed      = ... AND eff_delay >= 6
--   sum_arrival_delay_min = SUM(eff_delay)
--   cancelled_count       = COUNT(*) WHERE is_cancelled = 1
--   in_fact='N'           = przystanek ODRZUCONY z faktu (brak route/type)
-- =====================================================================

CREATE OR REPLACE VIEW gold.v_stop_daily_trace AS
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
    oh.operating_date,
    to_number(to_char(oh.operating_date,'YYYYMMDD')) as date_id,
    dr.id                    as route_id,
    coalesce(ttm.id, ttc.id) as train_type_id,
    od.dsta_id               as station_id,
    to_number(substr(sd.arrival_time,1,2)) as hour_id,
    -- identyfikatory zrodlowe (silver)
    oh.id             as ophe_id,
    oh.schedule_id,
    oh.order_id,
    oh.train_order_id,
    sh.category_code,
    sh.carrier_code,
    od.planned_sequence,
    od.actual_sequence,
    sd.arrival_time   as planned_arrival_time,
    od.actual_arrival,
    -- surowe + efektywne opoznienie (confirmed + null = 0)
    od.is_confirmed,
    od.is_cancelled,
    od.arrival_delay_min,
    case when od.is_confirmed and not od.is_cancelled then nvl(od.arrival_delay_min,0) end as eff_delay,
    case when od.is_confirmed and not od.is_cancelled then 'Y' else 'N' end               as is_arrival,
    -- czy przystanek wszedl do faktu (route + type zmapowane)
    case when dr.id is not null and coalesce(ttm.id, ttc.id) is not null
         then 'Y' else 'N' end                                                            as in_fact
from operation_header oh
join operation_details od
     on od.ophe_id = oh.id
join schedule_details sd
     on sd.schedule_id = oh.schedule_id and sd.order_id = oh.order_id
    and sd.order_number = od.planned_sequence
left join schedule_header sh
       on sh.operating_date = oh.operating_date and sh.schedule_id    = oh.schedule_id
      and sh.order_id       = oh.order_id       and sh.train_order_id = oh.train_order_id
left join route_pair rp
       on rp.schedule_id = oh.schedule_id and rp.order_id = oh.order_id
left join d_route dr
       on dr.from_station_id = rp.from_station_id and dr.to_station_id = rp.to_station_id
left join d_train_type ttm
       on ttm.category_code = sh.category_code and ttm.carrier_code = sh.carrier_code
      and oh.operating_date between ttm.valid_from and ttm.valid_to
left join d_train_type ttc
       on ttc.category_code = sh.category_code and ttc.carrier_code = sh.carrier_code
      and ttc.valid_to = DATE '2999-12-31'
where sd.arrival_time is not null                       -- pomija origin (start bez przyjazdu)
  and to_number(to_char(oh.operating_date,'YYYYMMDD')) in (
          select date_id from f_train_stop_daily
      );

grant select on gold.v_stop_daily_trace to DEV_APP;