WITH PerfData AS (
    SELECT
        a.{ACCOUNT_NUMBER} AS AccountNbr,
        c.{DATE_FIELD} AS BoardDt,
        DATEDIFF(month, c.{DATE_FIELD}, d.{DATE_FIELD}) AS AcctAge,
        d.{DATE_FIELD} AS SnapShotDt,
        a.{PAST_DUE_DAYS_FIELD},
        a.{DQ_STATUS_FIELD},
        b.{ACCOUNT_STATUS_FIELD},
        h.{CATEGORY_FIELD},
        a.{TIER_FIELD},
        a.{BOOKED_AMOUNT_FIELD},
        a.{DEFAULT_UNIT_FIELD},
        a.{LAST_FULL_PAYMENT_FIELD},
        a.{LAST_PAYMENT_FIELD},
        i.{DATE_FIELD} AS ContractStartDt,
        j.{DATE_FIELD} AS ChargeOffDt,
        CASE 
            WHEN DATEDIFF(day, f.{DATE_FIELD}, g.{DATE_FIELD}) >= {DEFERRED_PAYMENT_THRESHOLD} THEN {DEFERRED_PAYMENT_TEXT}
            ELSE {NON_DEFERRED_PAYMENT_TEXT} 
        END AS DeferralFlag,
        CASE 
            WHEN DATEDIFF(day, f.{DATE_FIELD}, g.{DATE_FIELD}) BETWEEN {AGE_RANGE_1_START} AND {AGE_RANGE_1_END} THEN DATEDIFF(month, c.{DATE_FIELD}, d.{DATE_FIELD}) - 1
            WHEN DATEDIFF(day, f.{DATE_FIELD}, g.{DATE_FIELD}) BETWEEN {AGE_RANGE_2_START} AND {AGE_RANGE_2_END} THEN DATEDIFF(month, c.{DATE_FIELD}, d.{DATE_FIELD}) - 2
            ELSE DATEDIFF(month, c.{DATE_FIELD}, d.{DATE_FIELD})
        END AS AcctAgeAdj
    FROM {DATABASE}.{SCHEMA}.{TABLE_ACCOUNT_DETAILS} a
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_ACCOUNT_STATUS} b ON a.{ACCOUNT_STATUS_ID_FIELD} = b.{ACCOUNT_STATUS_ID_FIELD}
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_DATE} c ON a.{BOARD_DATE_ID_FIELD} = c.{DATE_KEY_FIELD}
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_DATE} d ON a.{SNAPSHOT_DATE_ID_FIELD} = d.{DATE_KEY_FIELD}
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_CATEGORY} e ON a.{CATEGORY_ID_FIELD} = e.{CATEGORY_ID_FIELD}
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_DATE} f ON a.{CONTRACT_DATE_ID_FIELD} = f.{DATE_KEY_FIELD}
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_DATE} g ON a.{FIRST_DUE_DATE_ID_FIELD} = g.{DATE_KEY_FIELD}
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_APPLICATION} h ON a.{ACCOUNT_NUMBER} = h.{APPLICATION_ID_FIELD}
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_DATE} i ON a.{CONTRACT_START_DATE_ID_FIELD} = i.{DATE_KEY_FIELD}
    LEFT JOIN {DATABASE}.{SCHEMA}.{TABLE_DATE} j ON a.{CHARGE_OFF_DATE_ID_FIELD} = j.{DATE_KEY_FIELD}
),
LatestSnapShot AS (
    SELECT 
        AccountNbr,
        MAX(SnapShotDt) AS LatestSnapShotDt
    FROM PerfData
    GROUP BY AccountNbr
),
Delinquency30 AS (
    SELECT 
        AccountNbr,
        MAX({PAST_DUE_DAYS_FIELD}) AS MaxDPD_30
    FROM PerfData pd
    JOIN LatestSnapShot ls ON pd.AccountNbr = ls.AccountNbr AND pd.SnapShotDt = ls.LatestSnapShotDt
    WHERE {ACCOUNT_STATUS_FIELD} IN ({STATUS_30_59}, {STATUS_60_89}, {STATUS_90_119}, {STATUS_120_PLUS}, {STATUS_CHARGE_OFF})
          AND AcctAge <= {AGE_THRESHOLD_30}
    GROUP BY AccountNbr
),
Delinquency60 AS (
    SELECT 
        AccountNbr,
        MAX({PAST_DUE_DAYS_FIELD}) AS MaxDPD_60
    FROM PerfData pd
    JOIN LatestSnapShot ls ON pd.AccountNbr = ls.AccountNbr AND pd.SnapShotDt = ls.LatestSnapShotDt
    WHERE {ACCOUNT_STATUS_FIELD} IN ({STATUS_60_89}, {STATUS_90_119}, {STATUS_120_PLUS}, {STATUS_CHARGE_OFF})
          AND AcctAge <= {AGE_THRESHOLD_60}
    GROUP BY AccountNbr
),
Delinquency90 AS (
    SELECT 
        AccountNbr,
        MAX({PAST_DUE_DAYS_FIELD}) AS MaxDPD_90
    FROM PerfData pd
    JOIN LatestSnapShot ls ON pd.AccountNbr = ls.AccountNbr AND pd.SnapShotDt = ls.LatestSnapShotDt
    WHERE {ACCOUNT_STATUS_FIELD} IN ({STATUS_90_119}, {STATUS_120_PLUS}, {STATUS_CHARGE_OFF})
          AND AcctAge <= {AGE_THRESHOLD_90}
    GROUP BY AccountNbr
),
DefaultAlternative AS (
    SELECT 
        AccountNbr,
        MAX({PAST_DUE_DAYS_FIELD}) AS MaxDPD_DFLTALT
    FROM PerfData pd
    JOIN LatestSnapShot ls ON pd.AccountNbr = ls.AccountNbr AND pd.SnapShotDt = ls.LatestSnapShotDt
    WHERE {DEFAULT_UNIT_FIELD} = {DEFAULT_FLAG}
          AND COALESCE({LAST_FULL_PAYMENT_FIELD}, {LAST_PAYMENT_FIELD}) IS NOT NULL
    GROUP BY AccountNbr
),
Defaulted AS (
    SELECT 
        AccountNbr,
        MAX({PAST_DUE_DAYS_FIELD}) AS MaxDPD_DFLT
    FROM PerfData pd
    JOIN LatestSnapShot ls ON pd.AccountNbr = ls.AccountNbr AND pd.SnapShotDt = ls.LatestSnapShotDt
    WHERE {CHARGE_OFF_DATE_FIELD} IS NOT NULL 
          AND DATEDIFF('month', {CONTRACT_START_DATE_FIELD}, {CHARGE_OFF_DATE_FIELD}) <= {DEFAULT_THRESHOLD}
    GROUP BY AccountNbr
)
SELECT
    a1.AccountNbr,
    a2.MaxDPD_30,
    a3.MaxDPD_60, 
    a4.MaxDPD_90,
    a5.MaxDPD_DFLTALT,
    a6.MaxDPD_DFLT,
    a1.BoardDt,
    a1.DeferralFlag,
    DATEDIFF(month, a1.BoardDt, CURRENT_DATE) AS AcctAgeCurr,
    a1.{CATEGORY_FIELD},
    a1.{TIER_FIELD},
    a1.{BOOKED_AMOUNT_FIELD},
    CASE WHEN a2.AccountNbr IS NOT NULL THEN {TRUE_FLAG} ELSE {FALSE_FLAG} END AS Delinquency30Cnt,
    CASE WHEN a3.AccountNbr IS NOT NULL THEN {TRUE_FLAG} ELSE {FALSE_FLAG} END AS Delinquency60Cnt,
    CASE WHEN a4.AccountNbr IS NOT NULL THEN {TRUE_FLAG} ELSE {FALSE_FLAG} END AS Delinquency90Cnt,
    CASE WHEN a5.AccountNbr IS NOT NULL THEN {TRUE_FLAG} ELSE {FALSE_FLAG} END AS DefaultAltCnt,
    CASE WHEN a6.AccountNbr IS NOT NULL THEN {TRUE_FLAG} ELSE {FALSE_FLAG} END AS DefaultCnt,
    CASE WHEN a2.AccountNbr IS NOT NULL THEN a1.{BOOKED_AMOUNT_FIELD} ELSE {ZERO_VALUE} END AS Delinquency30Amt,
    CASE WHEN a3.AccountNbr IS NOT NULL THEN a1.{BOOKED_AMOUNT_FIELD} ELSE {ZERO_VALUE} END AS Delinquency60Amt,
    CASE WHEN a4.AccountNbr IS NOT NULL THEN a1.{BOOKED_AMOUNT_FIELD} ELSE {ZERO_VALUE} END AS Delinquency90Amt,
    CASE WHEN a5.AccountNbr IS NOT NULL THEN a1.{BOOKED_AMOUNT_FIELD} ELSE {ZERO_VALUE} END AS DefaultAltAmt,
    CASE WHEN a6.AccountNbr IS NOT NULL THEN a1.{BOOKED_AMOUNT_FIELD} ELSE {ZERO_VALUE} END AS DefaultAmt
FROM PerfData a1
LEFT JOIN Delinquency30 a2 ON a1.AccountNbr = a2.AccountNbr
LEFT JOIN Delinquency60 a3 ON a1.AccountNbr = a3.AccountNbr
LEFT JOIN Delinquency90 a4 ON a1.AccountNbr = a4.AccountNbr
LEFT JOIN DefaultAlternative a5 ON a1.AccountNbr = a5.AccountNbr
LEFT JOIN Defaulted a6 ON a1.AccountNbr = a6.AccountNbr
WHERE a1.AcctAge = {AGE_THRESHOLD_FILTER};
