-- ---- synonimy dla DEV_APP ----
CREATE OR REPLACE SYNONYM DEV_APP.pkg_tool                 FOR maintenance.pkg_tool;
CREATE OR REPLACE SYNONYM DEV_APP.def_station             	FOR silver.def_station;
CREATE OR REPLACE SYNONYM DEV_APP.def_city                	FOR silver.def_city;
CREATE OR REPLACE SYNONYM DEV_APP.schedule_header         	FOR silver.schedule_header;
CREATE OR REPLACE SYNONYM DEV_APP.schedule_details        	FOR silver.schedule_details;
CREATE OR REPLACE SYNONYM DEV_APP.def_commercial_category 	FOR silver.def_commercial_category;
CREATE OR REPLACE SYNONYM DEV_APP.def_carrier             	FOR silver.def_carrier;
CREATE OR REPLACE SYNONYM DEV_APP.def_train_status        	FOR silver.def_train_status;
CREATE OR REPLACE SYNONYM DEV_APP.def_disruption_cause    	FOR silver.def_disruption_cause;
CREATE OR REPLACE SYNONYM DEV_APP.operation_header  		FOR silver.operation_header;
CREATE OR REPLACE SYNONYM DEV_APP.operation_details 		FOR silver.operation_details;
CREATE OR REPLACE SYNONYM DEV_APP.disruption_header  		FOR silver.disruption_header;
CREATE OR REPLACE SYNONYM DEV_APP.disruption_details 		FOR silver.disruption_details;



-- ===== WYMIARY =====
CREATE OR REPLACE SYNONYM DEV_APP.d_date              FOR gold.d_date;
CREATE OR REPLACE SYNONYM DEV_APP.d_hour              FOR gold.d_hour;
CREATE OR REPLACE SYNONYM DEV_APP.d_station           FOR gold.d_station;
CREATE OR REPLACE SYNONYM DEV_APP.d_route             FOR gold.d_route;
CREATE OR REPLACE SYNONYM DEV_APP.d_train_type        FOR gold.d_train_type;
CREATE OR REPLACE SYNONYM DEV_APP.d_train_status      FOR gold.d_train_status;
CREATE OR REPLACE SYNONYM DEV_APP.d_disruption_cause  FOR gold.d_disruption_cause;

-- ===== FAKTY DZIENNE =====
CREATE OR REPLACE SYNONYM DEV_APP.f_train_run_daily         FOR gold.f_train_run_daily;
CREATE OR REPLACE SYNONYM DEV_APP.f_train_stop_daily        FOR gold.f_train_stop_daily;
CREATE OR REPLACE SYNONYM DEV_APP.f_train_disruption_daily  FOR gold.f_train_disruption_daily;

-- ===== FAKTY MIESIECZNE =====
CREATE OR REPLACE SYNONYM DEV_APP.f_train_run_monthly         FOR gold.f_train_run_monthly;
CREATE OR REPLACE SYNONYM DEV_APP.f_train_stop_monthly        FOR gold.f_train_stop_monthly;
CREATE OR REPLACE SYNONYM DEV_APP.f_train_disruption_monthly  FOR gold.f_train_disruption_monthly;

-- ===== WIDOKI DIAGNOSTYCZNE (trace) =====
CREATE OR REPLACE SYNONYM DEV_APP.v_run_daily_trace         FOR gold.v_run_daily_trace;
CREATE OR REPLACE SYNONYM DEV_APP.v_stop_daily_trace        FOR gold.v_stop_daily_trace;
CREATE OR REPLACE SYNONYM DEV_APP.v_disruption_daily_trace  FOR gold.v_disruption_daily_trace;

-- ===== WIDOKI RAPORTOWE =====
CREATE OR REPLACE SYNONYM DEV_APP.v_rep_punctuality_monthly  FOR gold.v_rep_punctuality_monthly;

-- ===== PAKIET =====
CREATE OR REPLACE SYNONYM DEV_APP.pkg_gold_load  FOR gold.pkg_gold_load;