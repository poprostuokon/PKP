-- =====================================================================
-- V_REP_RUN_ROUTE - profil opoznienia POJEDYNCZEGO kursu wzdluz trasy.
--
-- Zrodlo: SILVER (operations + rozklad) - dane per kurs zostaja na silver.
-- Grain: kurs (ophe_id) x przystanek. BEZ agregacji.
-- Wykres: os X = stop_seq/station_name, os Y = eff_arrival_delay_min (0 = na czas).
-- Filtrujesz: operating_date -> national_number/ophe_id (konkretny kurs).
-- Zasada: confirmed + null = 0 (potwierdzony bez opoznienia = 0 min).
-- =====================================================================
CREATE OR REPLACE VIEW gold.v_rep_run_route AS
select
    -- identyfikacja kursu (filtry)
    oh.operating_date,
    oh.id                 as ophe_id,
    oh.schedule_id, oh.order_id, oh.train_order_id,
    sh.category_code,
    sh.carrier_code,
    sh.national_number,
    sh.name               as train_name,
    -- relacja origin -> terminal (etykieta kursu; okno po kolejnosci rozkladowej)
    first_value(ds.name) over (partition by oh.id order by od.planned_sequence
                               rows between unbounded preceding and unbounded following)
      || ' -> ' ||
    last_value(ds.name)  over (partition by oh.id order by od.planned_sequence
                               rows between unbounded preceding and unbounded following) as relation,
    -- OS X: przystanek w kolejnosci
    od.planned_sequence   as stop_seq,
    od.actual_sequence,
    od.dsta_id            as station_id,
    ds.name               as station_name,
    -- czasy (do tooltipa)
    sd.arrival_time       as planned_arrival_time,
    sd.departure_time     as planned_departure_time,
    od.actual_arrival,
    od.actual_departure,
    -- status przystanku
    od.is_confirmed,
    od.is_cancelled,
    -- OS Y: opoznienia
    od.arrival_delay_min,                        -- surowe (moze byc NULL / ujemne)
    od.departure_delay_min,
    case when od.is_confirmed and not od.is_cancelled
         then nvl(od.arrival_delay_min, 0) end   as eff_arrival_delay_min,     -- krzywa przyjazdu
    case when od.is_confirmed and not od.is_cancelled
         then nvl(od.departure_delay_min, 0) end as eff_departure_delay_min    -- krzywa odjazdu
from operation_header oh
join operation_details od on od.ophe_id = oh.id
join def_station       ds on ds.id = od.dsta_id
left join schedule_header sh
       on sh.operating_date = oh.operating_date and sh.schedule_id    = oh.schedule_id
      and sh.order_id       = oh.order_id       and sh.train_order_id = oh.train_order_id
left join schedule_details sd
       on sd.schedule_id = oh.schedule_id and sd.order_id = oh.order_id
      and sd.order_number = od.planned_sequence;

grant select on gold.v_rep_run_route to DEV_APP;