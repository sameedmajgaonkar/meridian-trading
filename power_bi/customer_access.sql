SELECT customer_key, customer_name, region_name, nation_name,
  customer_phone, customer_account_balance
FROM meridian_t02_prod.gold.dim_customer_history
WHERE is_current = true
ORDER BY customer_key
LIMIT 20;
