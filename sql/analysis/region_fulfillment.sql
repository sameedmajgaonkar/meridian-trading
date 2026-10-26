SELECT region_name,MEASURE(delivery_days) AS delivery_days,
  MEASURE(late_delivery_rate) AS late_delivery_rate,MEASURE(return_rate) AS return_rate
FROM meridian_t02_prod.gold.mv_trading
WHERE :region='ALL' OR region_name=:region
GROUP BY region_name ORDER BY late_delivery_rate DESC;
