-- =============================================================================
-- silver.mv_rep_utrudnienia_wro
-- -----------------------------------------------------------------------------
-- Migawka silver.v_rep_utrudnienia_wro (utrudnienia na stacji Wroclaw Glowny,
-- D-7..D-1). Odswiezana raz na dobe po zaladowaniu SILVER
-- (pkg_silver_load.p_refresh_rep_mv). Przebudowa przy kazdej zmianie pliku,
-- bo lista kolumn MV jest ustalana w chwili tworzenia.
-- Drop w bloku PL/SQL (parser Flyway nie obsluguje DROP ... IF EXISTS).
-- =============================================================================

begin
    execute immediate 'drop materialized view silver.mv_rep_utrudnienia_wro';
exception
    when others then
        if sqlcode != -12003 then raise; end if;   -- ORA-12003: MV nie istnieje
end;
/

create materialized view silver.mv_rep_utrudnienia_wro
    build immediate
    refresh complete on demand
as
select * from silver.v_rep_utrudnienia_wro;

create index silver.ix_mv_rep_utrudn_wro_dz on silver.mv_rep_utrudnienia_wro (data_wro);

grant select on silver.mv_rep_utrudnienia_wro to DEV_APP;