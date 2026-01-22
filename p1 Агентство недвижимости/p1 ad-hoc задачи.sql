--- ЗАДАЧА 1. Время активности объявлений----------

WITH limits AS
( SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price/total_area) AS lower_price_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY last_price/total_area) AS higher_price_limit
    FROM real_estate.flats
    INNER JOIN real_estate.advertisement a USING (id)),
filtered_data AS (
SELECT id
    FROM real_estate.flats f
    INNER JOIN real_estate.advertisement a USING (id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        		AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
		AND last_price/f.total_area 
			BETWEEN (SELECT lower_price_limit FROM limits) 
			AND (SELECT higher_price_limit FROM limits)
			),
categories AS (SELECT 
*,
	CASE 
		WHEN days_exposition<=30 THEN '1 месяц и меньше'
		WHEN days_exposition<=90 THEN '1-3 месяца'
		WHEN days_exposition<=180 THEN '3-6 месяцев'
		WHEN days_exposition IS NULL then 'aктивные объявления'
		else 'больше 6 месяцев'
	END AS period_category,
	CASE 
		WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
		ELSE 'ЛенОбл'
	END AS location_category,
	last_price/total_area AS price_per_m
FROM real_estate.flats f
INNER JOIN real_estate.advertisement a ON a.id = f.id
INNER JOIN real_estate.city c USING (city_id)
INNER JOIN real_estate.type t USING (type_id)
INNER JOIN filtered_data fd ON fd.id = a.id
WHERE type = 'город'
),
summary AS
(SELECT 
	location_category, 
	period_category, 
	ROUND(AVG(price_per_m)) AS avg_price_per_m,
	ROUND(AVG(total_area)::NUMERIC,2) AS avg_sq_m,
	COUNT(*) AS count_id,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS rooms_median,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(balcony,0))AS balcony_median ,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floor) AS floor_median
FROM categories c
GROUP BY location_category, period_category
ORDER BY location_category, 
	CASE period_category
    		WHEN '1 месяц и меньше' THEN 1
    		WHEN '1-3 месяца' THEN 2
    		WHEN '3-6 месяцев' THEN 3
    		WHEN 'больше 6 месяцев' THEN 4
    		WHEN 'Активные объявления' THEN 5
    		ELSE 6
 	END
  )
SELECT 
	*,
	CONCAT(ROUND(count_id::numeric/SUM(count_id) OVER (PARTITION BY location_category)*100,1),'%') AS share_per_location
FROM summary
;


--- ЗАДАЧА 2. Сезонность объявлений----------

WITH limits AS
( SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price/total_area) AS lower_price_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY last_price/total_area) AS higher_price_limit
    FROM real_estate.flats
    FULL JOIN real_estate.advertisement a USING (id)),
filtered_data AS (
SELECT id
    FROM real_estate.flats f
    FULL JOIN real_estate.advertisement a USING (id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        	AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
		AND last_price/f.total_area 
			BETWEEN (SELECT lower_price_limit FROM limits) 
			AND (SELECT higher_price_limit FROM limits)
			),
summary AS
(SELECT *,
	first_day_exposition+days_exposition::integer  AS last_day_exposition
FROM real_estate.flats
FULL JOIN real_estate.advertisement a USING (id)
FULL JOIN real_estate.city c USING (city_id)
FULL JOIN real_estate.type t USING (type_id)
INNER JOIN filtered_data fd ON fd.id = a.id
WHERE 
	type = 'город'	
	AND EXTRACT (YEAR  FROM first_day_exposition) BETWEEN 2015 AND 2018 
	AND EXTRACT (YEAR  FROM first_day_exposition+days_exposition::integer) BETWEEN 2015 AND 2018
),
start_counts AS 
(SELECT 
	TO_CHAR (first_day_exposition, 'Month') AS month_n,
	COUNT(*) AS sale_started_in_month,
	ROUND(AVG(last_price/total_area)) AS price_per_m_start,
	ROUND(AVG(total_area)::NUMERIC,2) AS avg_area_start,
	RANK() OVER (ORDER BY COUNT(*) desc) AS rank_start
FROM summary
GROUP BY month_n),
finish_counts AS 
(SELECT 
        TO_CHAR(last_day_exposition, 'Month') AS month_n,
        COUNT(*) AS sale_finished_in_month,
        ROUND(AVG(last_price/total_area)) AS price_per_m_finish,
		ROUND(AVG(total_area)::NUMERIC,2) AS avg_area_finish,
		RANK() OVER (ORDER BY count(*) desc) AS rank_finish
    FROM summary
    WHERE days_exposition IS NOT NULL
    GROUP BY month_n)
SELECT 
    COALESCE(s.month_n, f.month_n) AS month_n,
    s.sale_started_in_month,
    concat(round(((sale_started_in_month / sum(sale_started_in_month) OVER()) * 100)::numeric, 1),'%') AS month_share_start,
    rank_start,
    concat(round(((sale_finished_in_month / sum(sale_finished_in_month) OVER()) * 100)::numeric, 1),'%') AS month_share_finish,
    rank_finish,
    price_per_m_start, 
    avg_area_start,
    price_per_m_finish, 
    avg_area_finish
FROM start_counts s
JOIN finish_counts f ON s.month_n = f.month_n
ORDER BY rank_start
;

--- ЗАДАЧА  3. Анализ рынка недвижимости Ленобласти----------

 WITH limits AS
( SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY last_price/total_area) AS lower_price_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY last_price/total_area) AS higher_price_limit
    FROM real_estate.flats
    INNER JOIN real_estate.advertisement a USING (id)),
filtered_data AS (
SELECT id
    FROM real_estate.flats f
    INNER JOIN real_estate.advertisement a USING (id)
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        		AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
		AND last_price/f.total_area 
			BETWEEN (SELECT lower_price_limit FROM limits) 
			AND (SELECT higher_price_limit FROM limits)
			),
summary AS 
(SELECT 
	city, 
	COUNT(id) AS count_id, 
	ROUND(COUNT(days_exposition)/count(id)::NUMERIC*100,1) AS sold_share,
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_exposition)) AS median_sell_days
FROM real_estate.city
INNER JOIN real_estate.flats f USING (city_id) 
INNER JOIN real_estate.advertisement a USING (id)
WHERE 
	id IN (SELECT * FROM filtered_data) 
GROUP BY city
),
top_cities AS
(SELECT 
	city,
	SUM(count_id) OVER (ORDER BY count_id DESC) AS top_published,
	SUM(count_id) OVER () AS total_published
FROM summary)
SELECT 
	city,
	count_id, 
	median_sell_days,
	sold_share,
	round(count_id /(SELECT total_published FROM top_cities LIMIT 1)::NUMERIC,3) AS SHARE,
	round(avg(last_price/total_area)) AS avg_price, 
	round(avg(total_area)::NUMERIC,2) AS avg_area,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms
FROM summary
INNER JOIN top_cities tc USING (city)
INNER JOIN real_estate.city Using(city)
INNER JOIN real_estate.flats f USING (city_id)
INNER JOIN real_estate.advertisement a USING (id)
WHERE city IN (SELECT city FROM top_cities WHERE top_published<=total_published*0.9) --рассматриваем города, которые внесли основной 90% вклад 
GROUP BY 
	city, 
	count_id,
	median_sell_days,
	sold_share, 
	share
ORDER BY count_id DESC


