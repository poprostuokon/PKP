-- =============================================================================
-- silver.v_rep_trasa_start_miesiac
-- -----------------------------------------------------------------------------
-- Widok raportowy APEX (strona 9: naglowek + Ajax POBIERZ_TRASE): opoznienie
-- ODJAZDU ze stacji poczatkowej trasy w miesiacu, per kategoria i przewoznik
-- (nazwy z gold.d_train_type, spojne z widokami gold).
-- Kurs liczony, gdy: nieodwolany, plan zaczyna sie i konczy na koncowkach trasy
-- (gold.d_route), odjazd z pierwszej stacji planu jest potwierdzony;
-- potwierdzony bez opoznienia = 0 (jak w gold).
-- Surowe suma + liczba: srednia liczona w APEX (poprawna tez dla "wszyscy").
-- Filtrowac po month + route_id (CROSS APPLY zaweza sie tylko po nich);
-- kategorie/przewoznika filtrowac w PL/SQL - w SQL psuly plan.
-- Pierwsza/ostatnia stacja planu przez min/max(order_number) z indeksu
-- (NIE keep dense_rank na dsta_id - pelny skan na kazdego kandydata).
-- Zakres: ostatnie 24 miesiace. Wymaga: grant select on gold.d_route
-- i gold.d_train_type to silver with grant option.
-- =============================================================================


CREATE OR REPLACE FORCE VIEW silver.v_rep_trasa_start_miesiac AS
WITH m AS (             -- ostatnie 24 miesiace
    select to_number(to_char(add_months(trunc(sysdate,'MM'), 1 - level), 'YYYYMM')) as month,
           add_months(trunc(sysdate,'MM'), 1 - level)                               as od
    from dual
    connect by level <= 24
)
select m.month,
       dr.id              as route_id,
       x.category_name,
       x.carrier_name,
       sum(x.op)          as suma_op_start,
       count(*)           as liczba_start
from m
cross join gold.d_route dr
cross apply (
    select nvl(od.departure_delay_min, 0) as op,
           tt.category_name,
           tt.carrier_name
    from operation_header oh
    join schedule_header sh
      on  sh.operating_date = oh.operating_date and sh.schedule_id    = oh.schedule_id
      and sh.order_id       = oh.order_id       and sh.train_order_id = oh.train_order_id
    join operation_details od on od.ophe_id = oh.id
    join gold.d_train_type tt
      on  tt.category_code = sh.category_code and tt.carrier_code = sh.carrier_code
      and oh.operating_date between tt.valid_from and tt.valid_to
    where oh.operating_date >= m.od
      and oh.operating_date <  add_months(m.od, 1)
      and oh.train_status <> 'X'
      and od.is_confirmed = 1
      and od.dsta_id = dr.from_station_id
      -- odjazd z PIERWSZEJ stacji planu (min order_number z indeksu)
      and od.planned_sequence = (select min(s.order_number) from schedule_details s
                                  where s.schedule_id = oh.schedule_id and s.order_id = oh.order_id)
      -- kurs konczy sie na stacji koncowej trasy: max(order_number) z indeksu, potem 1 wiersz po PK
      and exists (select 1
                    from schedule_details e
                   where e.schedule_id  = oh.schedule_id
                     and e.order_id     = oh.order_id
                     and e.dsta_id      = dr.to_station_id
                     and e.order_number = (select max(e2.order_number)
                                             from schedule_details e2
                                            where e2.schedule_id = oh.schedule_id
                                              and e2.order_id    = oh.order_id))
) x
group by m.month, dr.id, x.category_name, x.carrier_name;

grant select on silver.v_rep_trasa_start_miesiac to DEV_APP;