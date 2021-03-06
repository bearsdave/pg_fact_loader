SET client_min_messages TO warning;
--This is for testing functionality of timezone-specific timestamps
SET TIMEZONE TO 'America/Chicago';

SELECT pglogical.create_node('test','host=localhost') INTO TEMP foonode;
DROP TABLE foonode;

WITH sets AS (
SELECT 'test'||generate_series AS set_name
FROM generate_series(1,1)
)

SELECT pglogical.create_replication_set
(set_name:=s.set_name
,replicate_insert:=TRUE
,replicate_update:=TRUE
,replicate_delete:=TRUE
,replicate_truncate:=TRUE) AS result
INTO TEMP repsets
FROM sets s
WHERE NOT EXISTS (
SELECT 1
FROM pglogical.replication_set
WHERE set_name = s.set_name);

DROP TABLE repsets;

SELECT pglogical_ticker.deploy_ticker_tables();
--As of pglogical_ticker 1.2, we don't tick tables not in replication uselessly, but this
--would break our tests which did exactly that.  So we can fix the test breakage by just adding these tables
--to replication as they would be on an actual provider
SELECT pglogical_ticker.add_ticker_tables_to_replication();
--The tests will manually run tick() before new data is needed
-- SELECT pglogical_ticker.launch();
-- SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query = 'SELECT pglogical_ticker.tick();';

UPDATE fact_loader.queue_tables SET pglogical_node_if_id = (SELECT if_id FROM pglogical.node_interface);

/***
Mock this function so that we find results locally
 */
CREATE OR REPLACE FUNCTION pglogical_ticker.all_subscription_tickers()
RETURNS TABLE (provider_name NAME, set_name NAME, source_time TIMESTAMPTZ)
AS
$BODY$
BEGIN

RETURN QUERY SELECT t.provider_name, 'test1'::NAME AS set_name, t.source_time FROM pglogical_ticker.test1 t;

END;
$BODY$
LANGUAGE plpgsql;

/***
Mock so we get what we want here also
 */
    CREATE OR REPLACE FUNCTION fact_loader.logical_subscription()
    RETURNS TABLE (sub_origin_if OID, sub_replication_sets text[])
    AS $BODY$
    BEGIN

    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pglogical') THEN

      RETURN QUERY EXECUTE $$
      SELECT if_id AS sub_origin_if, '{test1}'::text[] as sub_replication_sets
      FROM pglogical.node_interface;
      $$;
    ELSE
      RETURN QUERY
      SELECT NULL::OID, NULL::TEXT[];

    END IF;

    END;
    $BODY$
    LANGUAGE plpgsql;
