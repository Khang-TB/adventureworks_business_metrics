-- Query 01: Calc Quantity of items, Sales value & Order quantity by each Subcategory in L12M
WITH L12M AS(
  SELECT
    MAX(ModifiedDate) AS curr_date
  FROM `adventureworks2019.Sales.SalesTable`
)
SELECT
  FORMAT_DATE('%b %Y', DATE(ModifiedDate)) AS period,
  Subcategory,
  SUM(OrderQty) AS item_quantity,
  ROUND(SUM(LineTotal), 2) AS sales_value,
  COUNT(SalesOrderID) AS order_quantity
FROM `adventureworks2019.Sales.SalesTable`
LEFT JOIN `adventureworks2019.Sales.Product` USING(ProductID)
WHERE DATE_SUB((SELECT date(curr_date) FROM L12M), INTERVAL 12 MONTH) <= DATE(ModifiedDate)
GROUP BY Subcategory, FORMAT_DATE('%b %Y', DATE(ModifiedDate))
ORDER BY FORMAT_DATE('%b %Y', DATE(ModifiedDate)) ASC;

-- Query 02: Calc % YoY growth rate by SubCategory & release top 3 cat with highest grow rate. Can use metric: quantity_item. Round results to 2 decimal
WITH quantity AS(
  SELECT
    EXTRACT(YEAR FROM ModifiedDate) AS year,
    Subcategory,
    SUM(OrderQty) AS item_quantity
  FROM `adventureworks2019.Sales.SalesTable`
  LEFT JOIN `adventureworks2019.Sales.Product` USING(ProductID)
  GROUP BY EXTRACT(YEAR FROM ModifiedDate), Subcategory
),
YoY AS(
  SELECT
    year,
    Subcategory,
    item_quantity,
    LAG(item_quantity) OVER(PARTITION BY Subcategory ORDER BY year ASC) AS prev_quantity,
    ROUND((item_quantity - LAG(item_quantity) OVER(PARTITION BY Subcategory ORDER BY year ASC))/ LAG(item_quantity) OVER(PARTITION BY Subcategory ORDER BY year ASC)*100, 2) AS `%YoY`
  FROM quantity
  ORDER BY year, Subcategory ASC
),
ranked AS(
  SELECT *,
    RANK() OVER(ORDER BY `%YoY` DESC) AS ranking
  FROM YoY
  WHERE prev_quantity IS NOT NULL
)
SELECT
  year,
  Subcategory,
  item_quantity,
  prev_quantity,
  `%Yoy`
FROM ranked
WHERE `ranking` <= 3
ORDER BY `%YoY` DESC;

-- Query 03: Ranking Top 3 TeritoryID with biggest Order quantity of every year. If there's TerritoryID with same quantity in a year, do not skip the rank number
WITH prep AS (
  SELECT
    FORMAT_DATE('%Y', od.ModifiedDate) AS `year`,
    TerritoryID,
    COUNT(SalesOrderID) AS Order_quantity
  FROM adventureworks2019.Sales.SalesOrderDetail od
  INNER JOIN adventureworks2019.Sales.SalesOrderHeader USING(SalesOrderID)
  GROUP BY FORMAT_DATE('%Y', od.ModifiedDate), TerritoryID
),
ranking AS(
  SELECT
    year,
    TerritoryID,
    Order_quantity,
    DENSE_RANK() OVER(PARTITION BY year ORDER BY Order_quantity DESC) AS ranked
  FROM prep
)
SELECT 
  year,
  TerritoryID,
  Order_quantity
FROM ranking 
WHERE ranked <= 3
ORDER BY year ASC, Order_quantity DESC;

-- Query 04: Calc Total Discount Cost belongs to Seasonal Discount for each SubCategory
SELECT
  FORMAT_DATE('%Y', od.ModifiedDate) AS `year`,
  ps.Name,
  ROUND(SUM(DiscountPct*UnitPrice*OrderQty), 2) AS Discount_cost
FROM adventureworks2019.Sales.SalesOrderDetail od
LEFT JOIN adventureworks2019.Production.Product p USING(ProductID)
LEFT JOIN adventureworks2019.Production.ProductSubcategory ps ON p.ProductSubcategoryID = CAST(ps.ProductSubcategoryID AS STRING)
LEFT JOIN adventureworks2019.Sales.SpecialOffer so USING(SpecialOfferID)
WHERE so.Type = 'Seasonal Discount'
GROUP BY FORMAT_DATE('%Y', od.ModifiedDate), ps.Name
ORDER BY `year`, Discount_cost ASC;

-- Query 05: Retention rate of Customer in 2014 with status of Successfully Shipped (Cohort Analysis)
WITH sucessfully_shipped_customer AS(
  SELECT
    CAST(FORMAT_DATE('%m', ModifiedDate) AS INT64) AS month,
    CustomerID
  FROM adventureworks2019.Sales.SalesTable
  WHERE
    FORMAT_DATE('%Y', ModifiedDate) = '2014'
    AND Status = 5
),
first_month AS(
  SELECT
    CustomerID,
    MIN(month) AS firstmonth
  FROM sucessfully_shipped_customer
  GROUP BY CustomerID
)
SELECT
  firstmonth,
  CONCAT('M-', month - firstmonth) AS month_diff,
  COUNT(DISTINCT CustomerID) AS customer_count
FROM sucessfully_shipped_customer
LEFT JOIN first_month USING(CustomerID)
GROUP BY CONCAT('M-', month - firstmonth), firstmonth
ORDER BY firstmonth, CONCAT('M-', month - firstmonth);

-- Query 06: Trend of Stock level & MoM diff % by all product in 2011. If %gr rate is null then 0. Round to 1 decimal
WITH prep AS(
  SELECT
    p.Name,
    EXTRACT(MONTH FROM DATE(wo.ModifiedDate)) AS month,
    EXTRACT(YEAR FROM DATE(wo.ModifiedDate)) AS year,
    SUM(StockedQty) AS stock_quantity
  FROM adventureworks2019.Production.Product p
  INNER JOIN adventureworks2019.Production.WorkOrder wo USING(ProductID)
  GROUP BY p.Name, EXTRACT(MONTH FROM DATE(wo.ModifiedDate)), EXTRACT(YEAR FROM DATE(wo.ModifiedDate))
),
`lag` AS(
  SELECT
    Name,
    month,
    year,
    stock_quantity,
    LAG(stock_quantity) OVER(PARTITION BY Name ORDER BY year, month ASC) AS prev_stock
  FROM prep
)
SELECT
  Name,
  month,
  year,
  stock_quantity,
  prev_stock,
  CONCAT(COALESCE(ROUND((stock_quantity - prev_stock) / prev_stock * 100, 2),0),'%') AS diff
FROM `lag`
ORDER BY Name, year, month ASC;

-- Query 07: Calc Ratio of Stock / Sales in 2011 by product name, by month
--- Order results by month desc, ratio desc. Round Ratio to 1 decimal
WITH stock AS(
  SELECT
    EXTRACT(MONTH FROM DATE(wo.ModifiedDate)) AS month,
    EXTRACT(YEAR FROM DATE(wo.ModifiedDate)) AS year,
    p.Name,
    p.ProductId,
    SUM(StockedQty) AS stock_quantity
  FROM adventureworks2019.Production.Product p
  INNER JOIN adventureworks2019.Production.WorkOrder wo USING(ProductID)
  WHERE EXTRACT(YEAR FROM DATE(wo.ModifiedDate)) = 2011
  GROUP BY p.Name, p.ProductId, EXTRACT(MONTH FROM DATE(wo.ModifiedDate)), EXTRACT(YEAR FROM DATE(wo.ModifiedDate))
),
sales AS(
  SELECT
    EXTRACT(MONTH FROM DATE(od.ModifiedDate)) AS month,
    EXTRACT(YEAR FROM DATE(od.ModifiedDate)) AS year,
    p.Name,
    p.ProductId,
    SUM(OrderQty) AS order_quantity
  FROM adventureworks2019.Production.Product p
  INNER JOIN adventureworks2019.Sales.SalesOrderDetail od USING(ProductID)
  WHERE EXTRACT(YEAR FROM DATE(od.ModifiedDate)) = 2011
  GROUP BY p.Name, p.ProductId, EXTRACT(MONTH FROM DATE(od.ModifiedDate)), EXTRACT(YEAR FROM DATE(od.ModifiedDate))
)
SELECT
  sales.month,
  sales.year,
  sales.Name,
  sales.ProductID,
  sales.order_quantity,
  stock.stock_quantity,
  ROUND(stock.stock_quantity/sales.order_quantity,1) AS ratio
FROM sales
JOIN stock ON
  sales.month = stock.month
  AND sales.year = stock.year
  AND sales.Name = stock.Name
  AND sales.ProductID = stock.ProductID
WHERE sales.year = 2011
ORDER BY sales.month DESC, ratio DESC;

-- Query 08: No of order and value at Pending status in 2014
WITH order_count AS(
  SELECT 
    EXTRACT(YEAR FROM DATE(poh.ModifiedDate)) AS year,
    poh.status,
    COUNT(DISTINCT poh.PurchaseOrderID) AS od_count
  FROM adventureworks2019.Purchasing.PurchaseOrderHeader poh
  WHERE EXTRACT(YEAR FROM DATE(poh.ModifiedDate)) = 2014
    AND poh.status = 1
  GROUP BY EXTRACT(YEAR FROM DATE(poh.ModifiedDate)), poh.status
),
value AS(
  SELECT 
    EXTRACT(YEAR FROM DATE(soh.ModifiedDate)) AS year,
    soh.status,
    SUM(TotalDue) AS value
  FROM adventureworks2019.Sales.SalesOrderHeader soh
  WHERE EXTRACT(YEAR FROM DATE(soh.ModifiedDate)) = 2014
  GROUP BY EXTRACT(YEAR FROM DATE(soh.ModifiedDate)), soh.status
)
SELECT 
  value.year,
  order_count.status AS ordercount_status,
  od_count AS order_count,
  value
FROM value
FULL JOIN order_count USING(year);