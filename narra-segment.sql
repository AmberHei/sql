CREATE TEMPORARY FUNCTION START_AT() AS(
    DATE("2021-01-01")
);
CREATE TEMPORARY FUNCTION END_AT() AS(
    DATE("2021-01-08")
);

WITH
daily_access AS(
SELECT
        a.user_id,
          service_id,
          IFNULL(app_name,'不明') AS app_name,
          COUNT(a.date) AS total_access_day
FROM
        (SELECT
                 user_id,service_id,date
         FROM
                 jp_mbga_1p.dau_summary_v
         WHERE
            (is_last_id = 1 OR is_last_id IS NULL) AND
            service_id IN (<:$APP_NAME_MULTI:>) AND
            date between START_AT() AND END_AT()
         )a LEFT JOIN
    gkpi_jp_1p.gd_jp_app_info_1p_v b
        ON b.asku = a.service_id
GROUP BY
        1,2,3
),
daily_session_per_uid AS (
SELECT
        a.user_id,
          service_id,
        IFNULL(b.session,0) AS session,
        IFNULL(b.total,0) AS total
FROM
        (SELECT
                 DISTINCT user_id,service_id
         FROM
                 jp_mbga_1p.dau_summary_v
         WHERE
            (is_last_id = 1 OR is_last_id IS NULL) AND
            service_id IN (<:$APP_NAME_MULTI:>) AND
            date between <:$DATES_FROM | date('today') - 31:> AND <:$DATES_TO | date('today')-1:>
         )a LEFT JOIN
    (SELECT
            user_id,SUM(count) AS session,SUM(total) AS total
         FROM
                 jp_mbga_1p.sakasho_daily_session_v
         WHERE game_id IN (<:$APP_NAME_SAKASHO:>) AND
                   d between <:$DATES_FROM | date('today') - 31:> AND <:$DATES_TO | date('today')-1:>
         GROUP BY
                 1
        )b
        ON a.user_id = b.user_id
),
hourly_coin_per_uid AS (
SELECT
        user_id,
          SUM(amount) AS amount,
          count(amount) AS pay_count
FROM
          jp_mbga_1p.transaction_summary_v
WHERE
          service_id IN (<:$APP_NAME_MULTI:>) AND
          transaction_type = 'consumption_paid_vc' AND
          date between <:$DATES_FROM | date('today') - 31:> AND <:$DATES_TO | date('today')-1:>
GROUP BY
        1
),
session_and_coin AS (
SELECT
        service_id,
          a.user_id   AS uid,
          a.session   AS session,
        a.total     AS total,
          IFNULL(b.amount,0)    AS amount,
          IFNULL(b.pay_count,0) AS pay_count
FROM
          daily_session_per_uid a LEFT JOIN
          hourly_coin_per_uid b
ON
          a.user_id = b.user_id
)
SELECT
        CASE
        WHEN session = 0 then    '[0] 0回'
    WHEN session < 47 then   '[1] 1~1  (1~46):    ライト'
    WHEN session < 109 then  '[2] 2~3  (47~108):  ミドル'
    WHEN session < 233 then  '[3] 4~7  (109~232): ミドル+'
    WHEN session < 388 then  '[4] 8~12 (233~387): ヘビー'
    WHEN session >= 388 then '[5] 13~  (388~):    スーパーヘビー'
    ELSE '0: 謎'
          END AS SEGMENT,
        COUNT(DISTINCT uid) AS UU,
        COUNT(DISTINCT uid)/SUM(COUNT(DISTINCT uid)) OVER() AS SEG_PER,
        SUM(COUNT(DISTINCT uid)) OVER()  AS TTL_UU,
        SUM(amount) AS SEG_AMOUNT,
        SUM(CASE WHEN amount > 0 THEN 1 ELSE 0 END) / COUNT(DISTINCT uid) AS PAYING_RATE,
        SUM(CASE WHEN amount > 0 THEN 1 ELSE 0 END) AS PUU,
        SUM(amount)/SUM(CASE WHEN amount > 0 THEN 1 ELSE 0 END) AS ARPPU,
    SUM(session) AS total_session,
    SUM(total) AS total_play_time
FROM
        session_and_coin
WHERE
    uid NOT IN (SELECT user_id FROM daily_access WHERE total_access_day <= 3)
GROUP BY
        1
ORDER BY 1
