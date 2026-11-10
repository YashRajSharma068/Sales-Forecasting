USE Superstore;

CREATE OR REPLACE VIEW orders AS
SELECT
    `Row ID`                              AS row_id,
    `Order ID`                            AS order_id,
    STR_TO_DATE(`Order Date`, '%d/%m/%Y') AS order_date,
    STR_TO_DATE(`Ship Date`,  '%d/%m/%Y') AS ship_date,
    `Ship Mode`                           AS ship_mode,
    `Customer ID`                         AS customer_id,
    `Customer Name`                       AS customer_name,
    Segment                               AS segment,
    City                                  AS city,
    State                                 AS state,
    Region                                AS region,
    `Product ID`                          AS product_id,
    Category                              AS category,
    `Sub-Category`                        AS sub_category,
    `Product Name`                        AS product_name,
    Sales                                 AS sales
FROM train;

-- Check: expect 9800 rows, first order 2015-01-03, last order 2018-12-30, total sales 2261536.78
SELECT COUNT(*) AS row_count, MIN(order_date) AS first_order, MAX(order_date) AS last_order,
       ROUND(SUM(sales), 2) AS total_sales
FROM orders;

-- ---------------------------------------------------------------------
-- 1. Headline KPIs in one row
--    Expected: 2261536.78 | 4922 | 793 | 459.48 | 1.99
-- ---------------------------------------------------------------------
SELECT
    ROUND(SUM(sales), 2)                                    AS total_sales,
    COUNT(DISTINCT order_id)                                AS total_orders,
    COUNT(DISTINCT customer_id)                             AS total_customers,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2)         AS avg_order_value,
    ROUND(COUNT(*) / COUNT(DISTINCT order_id), 2)           AS lines_per_order
FROM orders;

-- ---------------------------------------------------------------------
-- 2. Year by year: how fast is the business growing, and where does growth come from?
--    Sales rose 14.6% a year on average (2015 to 2018), but order value fell while orders rose.
-- ---------------------------------------------------------------------
SELECT
    yr,
    orders,
    customers,
    ROUND(sales_raw, 2)                                          AS total_sales,
    ROUND(100 * (sales_raw / LAG(sales_raw) OVER (ORDER BY yr) - 1), 1) AS sales_growth_pct,
    ROUND(sales_raw / orders, 2)                                 AS avg_order_value,
    ROUND(orders / customers, 2)                                 AS orders_per_active_customer
FROM (
    SELECT YEAR(order_date)           AS yr,
           COUNT(DISTINCT order_id)    AS orders,
           COUNT(DISTINCT customer_id) AS customers,
           SUM(sales)                  AS sales_raw
    FROM orders
    GROUP BY YEAR(order_date)
) AS y
ORDER BY yr;

-- ---------------------------------------------------------------------
-- 3. Month by month, with change on the previous month, a 3-month moving average,
--    and change on the same month a year earlier.
--    (The first two moving-average rows use fewer than three months. The first 12 months
--    have no same-month-last-year figure, so those cells are empty.)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT YEAR(order_date) AS yr, MONTH(order_date) AS mth, SUM(sales) AS sales_raw
    FROM orders
    GROUP BY YEAR(order_date), MONTH(order_date)
)
SELECT
    yr,
    mth,
    ROUND(sales_raw, 2)                                                            AS total_sales,
    ROUND(100 * (sales_raw / LAG(sales_raw, 1)  OVER (ORDER BY yr, mth) - 1), 1)   AS vs_previous_month_pct,
    ROUND(AVG(sales_raw) OVER (ORDER BY yr, mth ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3_months,
    ROUND(100 * (sales_raw / LAG(sales_raw, 12) OVER (ORDER BY yr, mth) - 1), 1)   AS vs_same_month_last_year_pct
FROM monthly
ORDER BY yr, mth;

-- ---------------------------------------------------------------------
-- 4. Seasonality: which months are busy?
--    Seasonal index = a month's sales divided by that year's average month, averaged over the years.
--    1.00 is an average month; 1.86 means 86% above average. (The Excel forecast uses the same index.)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT YEAR(order_date) AS yr, MONTH(order_date) AS mth, SUM(sales) AS sales_raw
    FROM orders
    GROUP BY YEAR(order_date), MONTH(order_date)
),
ratios AS (
    SELECT yr, mth, sales_raw, sales_raw / AVG(sales_raw) OVER (PARTITION BY yr) AS ratio
    FROM monthly
)
SELECT
    mth,
    ROUND(AVG(ratio), 2)                                                   AS seasonal_index,
    ROUND(100 * SUM(sales_raw) / (SELECT SUM(sales) FROM orders), 1)       AS share_of_all_sales_pct
FROM ratios
GROUP BY mth
ORDER BY mth;

-- The same idea by quarter: Q4 earns 38.5% of sales.
SELECT
    QUARTER(order_date)                                                    AS qtr,
    ROUND(SUM(sales), 2)                                                   AS total_sales,
    ROUND(100 * SUM(sales) / (SELECT SUM(sales) FROM orders), 1)           AS share_of_all_sales_pct
FROM orders
GROUP BY QUARTER(order_date)
ORDER BY qtr;

-- ---------------------------------------------------------------------
-- 5. What sells: category, then sub-category ranked inside its category
-- ---------------------------------------------------------------------
SELECT
    category,
    COUNT(*)                                                               AS order_lines,
    ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM orders), 1)               AS share_of_lines_pct,
    ROUND(SUM(sales), 2)                                                   AS total_sales,
    ROUND(100 * SUM(sales) / (SELECT SUM(sales) FROM orders), 1)           AS share_of_sales_pct
FROM orders
GROUP BY category
ORDER BY total_sales DESC;

SELECT
    category,
    sub_category,
    ROUND(SUM(sales), 2)                                                   AS total_sales,
    ROUND(100 * SUM(sales) / (SELECT SUM(sales) FROM orders), 1)           AS share_of_sales_pct,
    RANK() OVER (PARTITION BY category ORDER BY SUM(sales) DESC)           AS rank_in_category
FROM orders
GROUP BY category, sub_category
ORDER BY category, rank_in_category;

-- ---------------------------------------------------------------------
-- 6. Growth by category: which parts of the business are speeding up or slowing down?
--    Furniture grew only 8.4% in 2018 against 31.8% for Office Supplies.
-- ---------------------------------------------------------------------
SELECT
    category,
    ROUND(SUM(CASE WHEN YEAR(order_date) = 2015 THEN sales END), 0)        AS sales_2015,
    ROUND(SUM(CASE WHEN YEAR(order_date) = 2016 THEN sales END), 0)        AS sales_2016,
    ROUND(SUM(CASE WHEN YEAR(order_date) = 2017 THEN sales END), 0)        AS sales_2017,
    ROUND(SUM(CASE WHEN YEAR(order_date) = 2018 THEN sales END), 0)        AS sales_2018,
    ROUND(100 * (SUM(CASE WHEN YEAR(order_date) = 2018 THEN sales END)
               / SUM(CASE WHEN YEAR(order_date) = 2017 THEN sales END) - 1), 1) AS growth_2018_pct
FROM orders
GROUP BY category
ORDER BY category;

-- ---------------------------------------------------------------------
-- 7. Where: region by year, then the ten biggest states
--    Central was the only region that shrank in 2018.
-- ---------------------------------------------------------------------
SELECT
    region,
    ROUND(SUM(CASE WHEN YEAR(order_date) = 2015 THEN sales END), 0)        AS sales_2015,
    ROUND(SUM(CASE WHEN YEAR(order_date) = 2016 THEN sales END), 0)        AS sales_2016,
    ROUND(SUM(CASE WHEN YEAR(order_date) = 2017 THEN sales END), 0)        AS sales_2017,
    ROUND(SUM(CASE WHEN YEAR(order_date) = 2018 THEN sales END), 0)        AS sales_2018,
    ROUND(100 * SUM(sales) / (SELECT SUM(sales) FROM orders), 1)           AS share_of_sales_pct,
    ROUND(100 * (SUM(CASE WHEN YEAR(order_date) = 2018 THEN sales END)
               / SUM(CASE WHEN YEAR(order_date) = 2017 THEN sales END) - 1), 1) AS growth_2018_pct
FROM orders
GROUP BY region
ORDER BY share_of_sales_pct DESC;

SELECT
    state,
    ROUND(SUM(sales), 2)                                                   AS total_sales,
    ROUND(100 * SUM(sales) / (SELECT SUM(sales) FROM orders), 1)           AS share_of_sales_pct,
    ROUND(100 * SUM(SUM(sales)) OVER (ORDER BY SUM(sales) DESC)
              / (SELECT SUM(sales) FROM orders), 1)                        AS cumulative_share_pct
FROM orders
GROUP BY state
ORDER BY total_sales DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- 8. Segment: segments differ in how many orders they place, not in order size
-- ---------------------------------------------------------------------
SELECT
    segment,
    COUNT(DISTINCT order_id)                                               AS orders,
    ROUND(SUM(sales), 2)                                                   AS total_sales,
    ROUND(100 * SUM(sales) / (SELECT SUM(sales) FROM orders), 1)           AS share_of_sales_pct,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2)                        AS avg_order_value
FROM orders
GROUP BY segment
ORDER BY total_sales DESC;

-- ---------------------------------------------------------------------
-- 9. Customers: how concentrated is revenue? Customers split into ten equal groups
--    (decile 1 = the biggest-spending tenth of customers).
-- ---------------------------------------------------------------------
WITH customer_totals AS (
    SELECT customer_id, SUM(sales) AS total_sales
    FROM orders
    GROUP BY customer_id
),
ranked AS (
    SELECT customer_id, total_sales, NTILE(10) OVER (ORDER BY total_sales DESC) AS decile
    FROM customer_totals
)
SELECT
    decile,
    COUNT(*)                                                               AS customers,
    ROUND(SUM(total_sales), 2)                                             AS total_sales,
    ROUND(100 * SUM(total_sales) / (SELECT SUM(sales) FROM orders), 1)     AS share_of_sales_pct
FROM ranked
GROUP BY decile
ORDER BY decile;

-- ---------------------------------------------------------------------
-- 10. New versus existing customers each year ("new" = first order in that year).
--     2015 is the first year in the file, so every 2015 customer shows as new.
--     By 2018 only 11 customers were new and they made 1.0% of sales: growth came from existing customers.
-- ---------------------------------------------------------------------
WITH first_year AS (
    SELECT customer_id, MIN(YEAR(order_date)) AS first_yr
    FROM orders
    GROUP BY customer_id
)
SELECT
    YEAR(o.order_date)                                                     AS yr,
    COUNT(DISTINCT o.customer_id)                                          AS active_customers,
    COUNT(DISTINCT CASE WHEN YEAR(o.order_date) = f.first_yr THEN o.customer_id END) AS new_customers,
    ROUND(SUM(CASE WHEN YEAR(o.order_date) = f.first_yr THEN o.sales ELSE 0 END), 2) AS sales_from_new_customers,
    ROUND(100 * SUM(CASE WHEN YEAR(o.order_date) = f.first_yr THEN o.sales ELSE 0 END)
              / SUM(o.sales), 1)                                           AS new_customer_share_pct
FROM orders AS o
JOIN first_year AS f ON f.customer_id = o.customer_id
GROUP BY YEAR(o.order_date)
ORDER BY yr;

-- ---------------------------------------------------------------------
-- 11. Shipping: how long does each ship mode take (days from order to shipping)?
--     One row per order, because every line of an order ships together.
-- ---------------------------------------------------------------------
WITH one_row_per_order AS (
    SELECT order_id, ship_mode, MIN(order_date) AS order_date, MIN(ship_date) AS ship_date
    FROM orders
    GROUP BY order_id, ship_mode
)
SELECT
    ship_mode,
    COUNT(*)                                                               AS orders,
    ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM one_row_per_order), 1)    AS share_of_orders_pct,
    ROUND(AVG(DATEDIFF(ship_date, order_date)), 2)                         AS avg_days_to_ship,
    MIN(DATEDIFF(ship_date, order_date))                                   AS fastest_days,
    MAX(DATEDIFF(ship_date, order_date))                                   AS slowest_days
FROM one_row_per_order
GROUP BY ship_mode
ORDER BY avg_days_to_ship;

-- ---------------------------------------------------------------------
-- 12. Forecast the next 12 months of total sales 
--     Method (the same one built with formulas in the Excel workbook):
--       a) seasonal index for each calendar month (as in query 4);
--       b) divide each month by its index to take out the seasonal pattern;
--       c) fit a straight line through that series (least squares);
--       d) extend the line 12 months and multiply by the seasonal index again.
--     @last_year is the last year of data the model may learn from.
--       Run with 2017 to TEST the method: it forecasts 2018, and the output shows the real 2018
--       sales next to the forecast, the miss for each month, and the average miss (wape_pct).
--       Run with 2018 to forecast 2019 (no actuals exist, so those columns are empty).
--     Select the SET line and the query together, then press Ctrl+Enter.
--     Expected with 2017: forecast total 681,258 against 722,052 actual, wape_pct 18.7.
--     Expected with 2018: forecast total 830,391 for 2019.
-- ---------------------------------------------------------------------
SET @last_year = 2017;

WITH monthly AS (
    SELECT YEAR(order_date) AS yr, MONTH(order_date) AS mth, SUM(sales) AS sales_raw
    FROM orders
    GROUP BY YEAR(order_date), MONTH(order_date)
),
training_months AS (
    SELECT yr, mth, sales_raw,
           (yr - 2015) * 12 + mth                       AS t,
           sales_raw / AVG(sales_raw) OVER (PARTITION BY yr) AS ratio
    FROM monthly
    WHERE yr <= @last_year
),
season AS (
    SELECT mth, AVG(ratio) AS seasonal_index
    FROM training_months
    GROUP BY mth
),
deseasonalised AS (
    SELECT h.t, h.sales_raw / s.seasonal_index AS base_sales
    FROM training_months AS h
    JOIN season AS s ON s.mth = h.mth
),
sums AS (
    SELECT COUNT(*) AS n, SUM(t) AS sx, SUM(base_sales) AS sy,
           SUM(t * base_sales) AS sxy, SUM(t * t) AS sxx
    FROM deseasonalised
),
trend AS (
    SELECT (n * sxy - sx * sy) / (n * sxx - sx * sx)                                AS slope,
           (sy - (n * sxy - sx * sy) / (n * sxx - sx * sx) * sx) / n                AS intercept
    FROM sums
),
forecast AS (
    SELECT
        @last_year + 1                                   AS yr,
        s.mth,
        s.seasonal_index,
        (tr.intercept + tr.slope * ((@last_year - 2014) * 12 + s.mth)) * s.seasonal_index AS forecast_sales,
        a.sales_raw                                      AS actual_sales
    FROM season AS s
    CROSS JOIN trend AS tr
    LEFT JOIN monthly AS a ON a.yr = @last_year + 1 AND a.mth = s.mth
)
SELECT
    yr,
    mth,
    ROUND(seasonal_index, 3)                                               AS seasonal_index,
    ROUND(forecast_sales, 0)                                               AS forecast_sales,
    ROUND(actual_sales, 0)                                                 AS actual_sales,
    ROUND(100 * (forecast_sales / actual_sales - 1), 1)                    AS miss_pct,
    ROUND(100 * SUM(ABS(forecast_sales - actual_sales)) OVER ()
              / SUM(actual_sales) OVER (), 1)                              AS wape_pct,
    ROUND(SUM(forecast_sales) OVER (), 0)                                  AS forecast_year_total
FROM forecast
ORDER BY mth;