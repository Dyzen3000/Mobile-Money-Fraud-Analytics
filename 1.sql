CREATE TABLE transactions_raw (
    step INTEGER,
    type VARCHAR(20),
    amount NUMERIC(18,2),
    nameOrig VARCHAR(20),
    oldbalanceOrg NUMERIC(18,2),
    newbalanceOrig NUMERIC(18,2),
    nameDest VARCHAR(20),
    oldbalanceDest NUMERIC(18,2),
    newbalanceDest NUMERIC(18,2),
    isFraud INTEGER)

SELECT * FROM transactions_raw




CREATE TABLE transactions_clean AS
SELECT
    step,
    LOWER(type) AS type,
    amount,
    nameOrig,
    oldbalanceOrg,
    newbalanceOrig,
    nameDest,
    oldbalanceDest,
    newbalanceDest,
    isFraud,
    -- derived fields
    (oldbalanceOrg - newbalanceOrig) AS orig_balance_delta,
    (newbalanceDest - oldbalanceDest) AS dest_balance_delta,
    CASE WHEN nameDest LIKE 'M%' THEN TRUE ELSE FALSE END AS dest_is_merchant,
    CASE WHEN oldbalanceOrg = 0 AND newbalanceOrig = 0 AND amount > 0 THEN TRUE ELSE FALSE END AS orig_balance_error,
    CEIL(step / 24.0) AS sim_day,
    MOD(step, 24) AS hour_of_day
FROM transactions_raw
WHERE amount > 0;
 
CREATE INDEX idx_clean_type ON transactions_clean(type);
CREATE INDEX idx_clean_fraud ON transactions_clean(isFraud);
CREATE INDEX idx_clean_orig ON transactions_clean(nameOrig);
CREATE INDEX idx_clean_dest ON transactions_clean(nameDest);

SELECT * FROM transactions_clean





CREATE TABLE fraud_analysis AS
SELECT
    type,
    sim_day,
    hour_of_day,
    COUNT(*) AS total_txns,
    SUM(isFraud) AS fraud_txns,
    ROUND(SUM(isFraud)::NUMERIC / COUNT(*), 6) AS fraud_rate,
    SUM(CASE WHEN isFraud = 1 THEN amount ELSE 0 END) AS fraud_amount
FROM transactions_clean
GROUP BY type, sim_day, hour_of_day;
 
CREATE INDEX idx_fraud_type ON fraud_analysis(type);

SELECT * FROM fraud_analysis






DROP TABLE customer_analysis


CREATE TABLE customer_analysis AS
SELECT
    nameOrig,
    COUNT(*) AS num_txns,
    SUM(amount) AS total_sent,
    AVG(amount) AS avg_txn_amount,
    MAX(amount) AS max_txn_amount,
    SUM(isFraud) AS fraud_txns,
    COUNT(DISTINCT type) AS distinct_txn_types,
    MIN(step) AS first_step,
    MAX(step) AS last_step
FROM transactions_clean
GROUP BY nameOrig
ORDER BY num_txns DESC;
 
CREATE INDEX idx_cust_fraud ON customer_analysis(fraud_txns);

SELECT * FROM customer_analysis





-- Overview KPIs
CREATE VIEW dash_overview AS
SELECT
    COUNT(*) AS total_txns,
    SUM(amount) AS total_volume,
    SUM(isFraud) AS total_fraud_txns,
    ROUND(SUM(isFraud)::NUMERIC / COUNT(*) * 100, 4) AS fraud_pct,
    SUM(CASE WHEN isFraud = 1 THEN amount ELSE 0 END) AS fraud_volume
FROM transactions_clean;
 
-- Fraud by transaction type
CREATE VIEW dash_fraud_by_type AS
SELECT type, SUM(total_txns) AS total_txns, SUM(fraud_txns) AS fraud_txns,
       ROUND(SUM(fraud_txns)::NUMERIC / NULLIF(SUM(total_txns),0) * 100, 4) AS fraud_pct
FROM fraud_analysis
GROUP BY type
ORDER BY fraud_pct DESC;
 
-- Fraud trend over time (daily)
CREATE VIEW dash_fraud_trend AS
SELECT sim_day, SUM(fraud_txns) AS fraud_txns, SUM(fraud_amount) AS fraud_amount
FROM fraud_analysis
GROUP BY sim_day
ORDER BY sim_day;
 
-- Top risky customers
CREATE VIEW dash_top_risky_customers AS
SELECT nameOrig, num_txns, total_sent, fraud_txns
FROM customer_analysis
WHERE fraud_txns > 0
ORDER BY fraud_txns DESC, total_sent DESC
LIMIT 100;

