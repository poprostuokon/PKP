-- =============================================================================
-- silver.v_live_arrivals_wroclaw_gl
-- -----------------------------------------------------------------------------
-- Widok LIVE: tablica najbliższych przyjazdów pociągów na stację Wrocław Główny
-- (okno od -5 min do +8 godz). Dla każdego kursu bierze najnowszą wersję z logu
-- śledzenia i łączy ją z rozkładem: stacja początkowa, stacje pośrednie, peron,
-- tor, opóźnienia oraz status (planowy / opóźniony / przyjechał / odjechał /
-- odwołany). Dołącza też aktywne komunikaty o utrudnieniach dla danego kursu.
-- =============================================================================

CREATE OR REPLACE VIEW silver.v_live_arrivals_wroclaw_gl AS
WITH live_rank AS (
    -- najnowsza wersja live per kurs na Twojej stacji (append -> max snapshot_ts)
    SELECT o.*,
           ROW_NUMBER() OVER (
               PARTITION BY o.operating_date, o.train_order_id, o.dsta_id
               ORDER BY o.snapshot_ts DESC, o.id DESC
           ) AS rn
    FROM silver.operation_tracking_log o
    WHERE o.dsta_id = 60103
      AND o.operating_date >= TRUNC(SYSDATE) - 1          -- zawezenie partycji (dzis + wczoraj)
      AND o.actual_arrival AT TIME ZONE 'Europe/Warsaw'    -- jedno "teraz" = Warsaw; tu PRZYJAZD
          BETWEEN maintenance.pkg_tool.f_now_warsaw - INTERVAL '5' MINUTE
              AND maintenance.pkg_tool.f_now_warsaw + INTERVAL '8' HOUR
),
route_ends AS (
    -- min/max przystanku trasy w JEDNYM skanie: pierwsza (skad jedzie) + skrajne nazwy
    SELECT sd.schedule_id, sd.order_id,
           MIN(sd.order_number)                                          AS first_seq,
           MIN(st.name) KEEP (DENSE_RANK FIRST ORDER BY sd.order_number) AS station_start,
           MIN(st.id) KEEP (DENSE_RANK FIRST ORDER BY sd.order_number)   AS station_id_start,
           MAX(st.name) KEEP (DENSE_RANK LAST  ORDER BY sd.order_number) AS station_end,
           MAX(st.id) KEEP (DENSE_RANK LAST  ORDER BY sd.order_number)   AS station_id_end
    FROM silver.schedule_details sd
    JOIN silver.def_station st ON st.id = sd.dsta_id
    GROUP BY sd.schedule_id, sd.order_id
),
vias AS (
    -- stacje posrednie: miedzy stacja poczatkowa a Twoja stacja (przystanki PRZED Twoja)
    SELECT sd.schedule_id, sd.order_id, sd.dsta_id AS to_dsta,
           LISTAGG(st.name, ', ') WITHIN GROUP (ORDER BY sd2.order_number) AS via_stations
    FROM silver.schedule_details sd
    JOIN silver.schedule_details sd2
         ON  sd2.schedule_id = sd.schedule_id
         AND sd2.order_id    = sd.order_id
         AND sd2.order_number < sd.order_number           -- przystanki PRZED Twoja stacja
    JOIN route_ends re
         ON  re.schedule_id = sd.schedule_id
         AND re.order_id    = sd.order_id
         AND sd2.order_number > re.first_seq              -- ...ale po poczatkowej (posrednie)
    LEFT JOIN silver.def_station st ON st.id = sd2.dsta_id
    GROUP BY sd.schedule_id, sd.order_id, sd.dsta_id
),
disr AS (
    -- aktywne utrudnienia per kurs-na-stacji; placeholdery -> nazwy skrajnych stacji trasy
    SELECT dtl.schedule_id, dtl.order_id, dtl.operating_date, dtl.dsta_id,
           LISTAGG(
               REPLACE(
                   REPLACE(
                       NVL(dc.description, NVL(dtl.message, dtl.disruption_type_code)),
                       '{stacja_poczatkowa}', NVL(re.station_start, '—')),
                   '{stacja_koncowa}',   NVL(re.station_end, '—')),
               ' | ') WITHIN GROUP (ORDER BY dtl.snapshot_ts)              AS komunikat
    FROM silver.disruption_tracking_log dtl
    LEFT JOIN silver.def_disruption_cause dc
           ON LOWER(dc.code) = LOWER(NVL(dtl.message, dtl.disruption_type_code))
    LEFT JOIN route_ends re
           ON re.schedule_id = dtl.schedule_id
          AND re.order_id    = dtl.order_id
    WHERE dtl.is_active
      AND dtl.snapshot_ts >= maintenance.pkg_tool.f_now_warsaw - INTERVAL '24' HOUR
    GROUP BY dtl.schedule_id, dtl.order_id, dtl.operating_date, dtl.dsta_id
)
SELECT
    sh.operating_date + nvl(sd.ARRIVAL_DAY, 0)          AS planowy_przyjazd_dzien,
    sd.arrival_time                                     AS planowy_przyjazd_godzina,
    sh.carrier_code                                     AS przewoznik,          -- KD / IC
    sh.CATEGORY_CODE                                    AS kategoria,
    sh.name                                             AS nazwa_pociagu,
    sh.national_number                                  AS nr_pociagu,
    re.station_start                                    AS stacja_poczatkowa, 
    re.station_end                                      AS stacja_koncowa,
    v.via_stations                                      AS stacje_posrednie,
    sd.departure_platform                               AS peron,
    sd.departure_track                                  AS tor,
    l.arrival_delay_min                                 AS opoznienie_przyjazd_min,
    CASE
        WHEN l.is_cancelled THEN 'ODWOŁANY'
        WHEN l.actual_departure AT TIME ZONE 'Europe/Warsaw'
             <= maintenance.pkg_tool.f_now_warsaw THEN 'ODJECHAŁ'
        WHEN l.actual_arrival AT TIME ZONE 'Europe/Warsaw'
             <= maintenance.pkg_tool.f_now_warsaw THEN 'PRZYJECHAŁ'
        WHEN l.arrival_delay_min > 5 THEN 'OPÓŹNIONY'
        ELSE 'PLANOWY'
    END                                                 AS status,
    ROUND((CAST(l.actual_arrival AT TIME ZONE 'Europe/Warsaw' AS DATE)
           - CAST(maintenance.pkg_tool.f_now_warsaw AS DATE)) * 1440)  AS do_przyjazdu_min,
    CAST(l.actual_arrival AT TIME ZONE 'Europe/Warsaw' AS DATE)                                  AS faktyczny_przyjazd,
    case when re.station_id_end = l.dsta_id then null else sh.operating_date + nvl(sd.DEPARTURE_DAY, 0) end         AS planowy_odjazd_dzien,
    case when re.station_id_end = l.dsta_id then null else sd.departure_time end                                    AS planowy_odjazd_godzina,
    l.departure_delay_min                                  AS opoznienie_odjazdu_min,
    ROUND((CAST(l.actual_departure AT TIME ZONE 'Europe/Warsaw' AS DATE)
           - CAST(maintenance.pkg_tool.f_now_warsaw AS DATE)) * 1440)  AS do_odjazdu_min,
    CAST(l.actual_departure AT TIME ZONE 'Europe/Warsaw' AS DATE)                                   AS faktyczny_odjazd,
    dr.komunikat                                        AS utrudnienia
FROM live_rank l
JOIN silver.schedule_header sh
     ON  sh.operating_date = l.operating_date
     AND sh.schedule_id    = l.schedule_id
     AND sh.train_order_id = l.train_order_id
     AND sh.order_id       = l.order_id
JOIN silver.schedule_details sd
     ON  sd.schedule_id = l.schedule_id
     AND sd.order_id    = l.order_id
     AND sd.dsta_id     = l.dsta_id                      -- wiersz rozkladu dla Twojej stacji
LEFT JOIN route_ends re
     ON  re.schedule_id = sd.schedule_id
     AND re.order_id    = sd.order_id
LEFT JOIN vias v
     ON  v.schedule_id = sd.schedule_id
     AND v.order_id    = sd.order_id
     AND v.to_dsta     = sd.dsta_id
LEFT JOIN disr dr
     ON  dr.operating_date = l.operating_date
     AND dr.order_id       = l.order_id
     AND dr.dsta_id        = l.dsta_id
WHERE l.rn = 1
  AND sd.arrival_time IS NOT NULL                        -- tylko kursy z przyjazdem na Twoja stacje
ORDER BY sh.operating_date + nvl(sd.ARRIVAL_DAY, 0), sd.arrival_time, l.actual_arrival;

grant select on silver.v_live_arrivals_wroclaw_gl to dev_app;