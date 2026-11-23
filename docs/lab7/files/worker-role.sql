-- LR7: database role for the Lambda functions (least privilege, not the owner `timecapsule`).
SELECT format('CREATE ROLE timecapsule_worker LOGIN PASSWORD %L', :'pw')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'timecapsule_worker') \gexec
ALTER ROLE timecapsule_worker PASSWORD :'pw';
ALTER ROLE timecapsule_worker CONNECTION LIMIT 5;
GRANT CONNECT ON DATABASE timecapsule TO timecapsule_worker;
\c timecapsule
GRANT USAGE ON SCHEMA public TO timecapsule_worker;
GRANT SELECT ON users, capsules TO timecapsule_worker;
GRANT UPDATE (opened_at) ON capsules TO timecapsule_worker;
GRANT SELECT, INSERT ON notifications TO timecapsule_worker;
GRANT USAGE ON SEQUENCE notifications_id_seq TO timecapsule_worker;
