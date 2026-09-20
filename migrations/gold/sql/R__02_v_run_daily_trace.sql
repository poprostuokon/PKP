-- =====================================================================
-- V_RUN_DAILY_TRACE - widok diagnostyczny do f_train_run_daily.
--
-- Odwraca mapowanie z load_f_train_run_daily: jeden wiersz = jeden kurs z
-- silver operations, z policzonymi kluczami GOLD (route_id, train_type_id,
-- status_id) i opoznieniem terminalnym. Filtrujesz po tych samych id co w
-- fakcie i widzisz, jakie kursy sie pod nie zgrupowaly.
--
-- Uzycie:
--   SELECT * FROM gold.v_run_daily_trace
--    WHERE operating_date = DATE '2026-09-01'
--      AND route_id = :r AND train_type_id = :t AND status_id = :s
--    ORDER BY terminal_delay;
--
-- Weryfikacja miar faktu dla tej komorki:
--   runs_count             = COUNT(*)
--   sum_terminal_delay_min = SUM(terminal_delay)
--   delayed_count          = COUNT(*) WHERE is_delayed='Y'
--   in_fact='N'            = kurs ODRZUCONY z faktu (brak route/type/status)
-- =====================================================================

CREATE OR REPLACE VIEW gold.v_run_daily_trace AS
WITH ep AS (          -- endpointy rozkladu per (schedule_id, order_id)
    select schedule_id, order_id,
           min(order_number) as min_on,
           max(order_number) as max_on
    from   schedule_details
    group by schedule_id, order_id
),
route_pair AS (       -- from/to stacja per (schedule_id, order_id)
    select ep.schedule_id,
           ep.order_id,
           f.dsta_id as from_station_id,
           t.dsta_id as to_station_id
    from   ep
    join   schedule_details f
           on f.schedule_id = ep.schedule_id and f.order_id = ep.order_id and f.order_number = ep.min_on
    join   schedule_details t
           on t.schedule_id = ep.schedule_id and t.order_id = ep.order_id and t.order_number = ep.max_on
),
term AS (             -- opoznienie terminalne = przystanek o max actual_sequence
    select ophe_id,
           arrival_delay_min as terminal_delay
    from   operation_details
    qualify row_number() over (partition by ophe_id order by actual_sequence desc) = 1
)
select
    -- klucze GOLD (po nich filtrujesz, jak w fakcie)
    oh.operating_date,
    to_number(to_char(oh.operating_date,'YYYYMMDD')) as date_id,
    dr.id                    as route_id,
    coalesce(ttm.id, ttc.id) as train_type_id,
    dts.id                   as status_id,
    -- identyfikatory zrodlowe (silver operations / schedule)
    oh.id             as ophe_id,
    oh.schedule_id,
    oh.order_id,
    oh.train_order_id,
    oh.train_status,
    sh.category_code,
    sh.carrier_code,
    rp.from_station_id,
    rp.to_station_id,
    -- miary wchodzace do agregatu
    tm.terminal_delay,
    case when tm.terminal_delay is null then null
         when tm.terminal_delay >= 6   then 'Y'
         else 'N' end                                 as is_delayed,
    -- czy kurs wszedl do faktu (wszystkie klucze zmapowane)
    case when dr.id is not null
          and coalesce(ttm.id, ttc.id) is not null
          and dts.id is not null
         then 'Y' else 'N' end                        as in_fact
from operation_header oh
left join schedule_header sh
       on sh.operating_date = oh.operating_date and sh.schedule_id    = oh.schedule_id
      and sh.order_id       = oh.order_id       and sh.train_order_id = oh.train_order_id
left join route_pair rp
       on rp.schedule_id = oh.schedule_id and rp.order_id = oh.order_id
left join d_route dr
       on dr.from_station_id = rp.from_station_id and dr.to_station_id = rp.to_station_id
left join term tm
       on tm.ophe_id = oh.id
left join d_train_type ttm
       on ttm.category_code = sh.category_code and ttm.carrier_code = sh.carrier_code
      and oh.operating_date between ttm.valid_from and ttm.valid_to
left join d_train_type ttc
       on ttc.category_code = sh.category_code and ttc.carrier_code = sh.carrier_code
      and ttc.valid_to = DATE '2999-12-31'
left join d_train_status dts
       on dts.status_code = oh.train_status
-- tylko doby, ktore fakt faktycznie zaladowal (widok = trace faktu, nie caly silver)
where to_number(to_char(oh.operating_date,'YYYYMMDD')) in (
          select date_id from f_train_run_daily
);

grant select on gold.v_run_daily_trace to DEV_APP;