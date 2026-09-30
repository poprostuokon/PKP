-- =============================================================================
-- silver.v_rep_trasa_stacje_miesiac
-- -----------------------------------------------------------------------------
-- Widok raportowy APEX (strona 9, Ajax POBIERZ_TRASE): stacje trasy po kolei
-- w danym miesiacu, osobno dla kazdej kategorii pociagu. Jeden wiersz = postoj
-- (plus stacja poczatkowa, ktora ma tylko odjazd).
-- Kolejnosc stacji z planu wzorcowego: kurs tej trasy i tej kategorii z miesiaca,
-- ktorego plan zaczyna sie i konczy na koncowkach trasy (gold.d_route), z
-- najwieksza liczba postojow. Dzieki kategorii os pokazuje tylko stacje, na
-- ktorych dana kategoria staje (np. InterCity bez przystankow regionalnych).
-- Filtrowac po month + route_id + category_name: wszystkie trzy leza po LEWEJ
-- stronie CROSS APPLY (m / d_route / kat), wiec zawezaja lateral i nie psuja planu.
-- NO_PARALLEL - male zapytanie, PX tylko dokladal narzut.
-- Zakres: ostatnie 24 miesiace. Wymaga: grant select on gold.d_route
-- i gold.d_train_type to silver with grant option.
-- =============================================================================

CREATE OR REPLACE FORCE VIEW SILVER.V_REP_TRASA_STACJE_MIESIAC
AS WITH m AS (             -- ostatnie 24 miesiace (bez dostepu do d_date)
    select to_number(to_char(add_months(trunc(sysdate,'MM'), 1 - level), 'YYYYMM')) as month,
           add_months(trunc(sysdate,'MM'), 1 - level)                               as od
    from dual
    connect by level <= 24
),
kat AS (                -- kategorie pociagow (nazwy jak w widokach gold)
    select distinct category_name from gold.d_train_type
)
select /*+ no_parallel */
       m.month,
       dr.id              as route_id,
       kat.category_name,
       x.stacja_kolejnosc,
       x.stacja_id,
       x.stacja_nazwa,
       x.czy_start,
       x.czy_koniec
from m
cross join gold.d_route dr
cross join kat
-- 1) plan wzorcowy: kursy z miesiaca tej kategorii, ktorych plan zawiera obie koncowki trasy
cross apply (
    select /*+ no_parallel */
           c.schedule_id, c.order_id
    from operation_header oh
    join schedule_header sh
      on  sh.operating_date = oh.operating_date and sh.schedule_id    = oh.schedule_id
      and sh.order_id       = oh.order_id       and sh.train_order_id = oh.train_order_id
    join gold.d_train_type tt                    -- tylko kursy wybranej kategorii
      on  tt.category_code = sh.category_code and tt.carrier_code = sh.carrier_code
      and oh.operating_date between tt.valid_from and tt.valid_to
      and tt.category_name = kat.category_name
    join schedule_details f                      -- plan zawiera stacje poczatkowa
      on  f.schedule_id = oh.schedule_id and f.order_id = oh.order_id
      and f.dsta_id     = dr.from_station_id
    join schedule_details t                      -- plan zawiera stacje koncowa
      on  t.schedule_id = oh.schedule_id and t.order_id = oh.order_id
      and t.dsta_id     = dr.to_station_id
    join schedule_details c                      -- wszystkie przystanki planu
      on  c.schedule_id = oh.schedule_id and c.order_id = oh.order_id
    where oh.operating_date >= m.od
      and oh.operating_date <  add_months(m.od, 1)
    group by c.schedule_id, c.order_id
    -- koncowki planu = koncowki trasy (nie tylko "przejezdza przez")
    having min(c.dsta_id) keep (dense_rank first order by c.order_number) = dr.from_station_id
       and max(c.dsta_id) keep (dense_rank last  order by c.order_number) = dr.to_station_id
    -- najwiecej postojow; distinct, bo kurs jezdzi wiele dni w miesiacu
    order by count(distinct case when c.arrival_time is not null then c.order_number end) desc,
             c.schedule_id
    fetch first 1 row only
) w
-- 2) stacje planu wzorcowego
cross apply (
    select /*+ no_parallel */
           sd.order_number as stacja_kolejnosc,
           sd.dsta_id      as stacja_id,
           st.name         as stacja_nazwa,
           sd.arrival_time,
           case when sd.order_number = min(sd.order_number) over () then 1 else 0 end as czy_start,
           case when sd.order_number = max(sd.order_number) over () then 1 else 0 end as czy_koniec
    from schedule_details sd
    join def_station st on st.id = sd.dsta_id
    where sd.schedule_id = w.schedule_id
      and sd.order_id    = w.order_id
) x
where x.arrival_time is not null or x.czy_start = 1
;

grant select on silver.V_REP_TRASA_STACJE_MIESIAC to DEV_APP;

