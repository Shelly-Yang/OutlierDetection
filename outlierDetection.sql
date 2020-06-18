USE fraud;

SELECT * FROM sales;

-- some descriptive statsitics
SELECT COUNT(DISTINCT(ID)) FROM sales;
SELECT DISTINCT(Prod) FROM sales;

SELECT Prod, Insp, COUNT(*)
FROM sales
GROUP BY Prod, Insp WITH ROLLUP;

-- add Unit Price
ALTER TABLE sales
ADD COLUMN unit_price	DECIMAL(9,2);

UPDATE sales
SET unit_price = val/quant;

SELECT AVG(unit_price) FROM sales;

-- find median
select prod, count(*) from sales group by prod;
SET @rowindex := -1;
SELECT @rowindex := @rowindex + 1 AS rowindex,
			val/quant AS unit_price
		FROM sales
        WHERE Prod = "p1125"
        ORDER BY val/quant;

SELECT AVG(p.unit_price)
FROM 
	(	SELECT @rowindex := @rowindex + 1 AS rowindex,
			val/quant AS unit_price
		FROM sales
        WHERE Prod = "p1437"
        ORDER BY val/quant) AS p
WHERE
p.rowindex IN (FLOOR(@rowindex / 2), CEIL(@rowindex / 2));

SELECT (@rowindex / 2);



SELECT median("p1437");

-- careful!!  THis works but is slow query
SELECT DISTINCT(Prod), median(Prod) 
FROM sales
; 

-- list of products
SELECT DISTINCT(Prod)
FROM sales;

SELECT Prod, median(Prod)
FROM ( SELECT DISTINCT(Prod) FROM sales) AS prod_list
;

SELECT * 
FROM (
		SELECT Prod, @prod_index := @prod_index + 1 AS prod_index
			FROM (SELECT DISTINCT(Prod) FROM sales) AS prod_list
				JOIN (SELECT @prod_index := 0) AS prod_idx 
	) AS prod
;


-- box plot stats
SELECT 	"p1437" AS prod,
		q1("p1437") - 1.5 * iqr("p1437") AS lower,
		q1("p1437") AS q1,
        median("p1437") AS median,
		q3("p1437") AS q3,
        q3("p1437") + 1.5 * iqr("p1437") AS upper,
        iqr("p1437") AS iqr
        ;
  

CALL box_plot_stats();
SELECT * FROM box_plot_stats;


-- flag outliers        
SELECT ID, sales.Prod, unit_price, lower, upper, 
		CASE 	WHEN unit_price < lower THEN 1
				WHEN unit_price > upper THEN 1
                ELSE 0 
		END AS outlier
FROM sales
	JOIN box_plot_stats stats
		ON sales.Prod = stats.Prod_name
ORDER BY Prod, unit_price
;

-- count outliers
SELECT 	sales.Prod, 
		SUM(CASE 	WHEN unit_price < lower THEN 1
					WHEN unit_price > upper THEN 1
					ELSE 0 
			END) AS outlier
FROM sales
	JOIN box_plot_stats stats
		ON sales.Prod = stats.Prod_name
GROUP BY Prod
ORDER BY Prod, unit_price
;



-- confusion matrix
SELECT sales.Prod, Insp,
        SUM(CASE 	WHEN unit_price < lower THEN 1
					WHEN unit_price > upper THEN 1
					ELSE 0 
			END) AS predict_fraud,
        COUNT(*) - SUM(	CASE WHEN unit_price < lower THEN 1
							WHEN unit_price > upper THEN 1
							ELSE 0 
						END) AS predict_ok,
		COUNT(*) AS total
FROM sales
	JOIN box_plot_stats stats
		ON sales.Prod = stats.Prod_name
WHERE Insp != "unkn"
GROUP BY sales.Prod, Insp WITH ROLLUP
;

-- outlier scoring
-- Normalized distance to typical price (NDTP)
-- abs(unit_price - median(unit_price))/IQR

SELECT 	ID, sales.Prod, unit_price, median, 
		ABS(unit_price - median)/iqr AS outlierRankScore
FROM sales
	JOIN box_plot_stats stats
		ON sales.Prod = stats.Prod_name
ORDER BY outlierRankScore DESC
;

SELECT 	ID, sales.Prod, unit_price, median, 
		ABS(unit_price - median)/iqr AS outlierRankScore,
        NTILE(20) OVER (ORDER BY ABS(unit_price - median)/iqr DESC) AS outlierGroup
FROM sales
	JOIN box_plot_stats stats
		ON sales.Prod = stats.Prod_name
ORDER BY outlierRankScore DESC
;

SELECT 	Prod, Insp, 
		SUM(IF(outlierGroup = 1, 1, 0)) AS predict_fraud,
		COUNT(*) - SUM(IF(outlierGroup = 1, 1, 0)) AS predict_ok,
        COUNT(*) AS total
FROM (
		SELECT 	Insp, ID, sales.Prod AS Prod, unit_price, median, 
				ABS(unit_price - median)/iqr AS outlierRankScore,
				NTILE(20) OVER (ORDER BY ABS(unit_price - median)/iqr DESC) AS outlierGroup
		FROM sales
			JOIN box_plot_stats stats
				ON sales.Prod = stats.Prod_name
		) AS grouped
WHERE Insp = "fraud"
GROUP BY Prod, Insp
ORDER BY Prod
;

--
-- HB-method
SELECT 	ID, sales.Prod, unit_price, median, 
		unit_price / median AS ratio_1, median / unit_price AS ratio_2,
        GREATEST(unit_price / median, median / unit_price) AS HB_score,
        NTILE(20) OVER (ORDER BY GREATEST(unit_price / median, median / unit_price) DESC) AS HB_group
FROM sales
	JOIN box_plot_stats stats
		ON sales.Prod = stats.Prod_name
ORDER BY HB_Score DESC
;

SELECT 	Prod, Insp, 
		SUM(IF(outlierGroup = 1, 1, 0)) AS predict_fraud,
		COUNT(*) - SUM(IF(outlierGroup = 1, 1, 0)) AS predict_ok,
        COUNT(*) AS total
FROM (
		SELECT 	Insp, ID, sales.Prod, unit_price, median, 
				unit_price / median AS ratio_1, median / unit_price AS ratio_2,
				GREATEST(unit_price / median, median / unit_price) AS HB_score,
				NTILE(20) OVER (ORDER BY GREATEST(unit_price / median, median / unit_price) DESC) AS outlierGroup
		FROM sales
			JOIN box_plot_stats stats
				ON sales.Prod = stats.Prod_name
		) AS grouped
WHERE Insp = "fraud"
GROUP BY Prod, Insp
ORDER BY Prod
;