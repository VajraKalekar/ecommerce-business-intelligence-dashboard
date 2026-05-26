CREATE DATABASE ecommerce_project;
USE ecommerce_project;

CREATE TABLE customers(
customer_id VARCHAR(50) NOT NULL PRIMARY KEY,
customer_unique_id VARCHAR(50) NOT NULL UNIQUE,
customer_zip_code_prefix VARCHAR(20),
customer_city VARCHAR(50),
customer_state VARCHAR(50));

CREATE TABLE orders (
order_id VARCHAR(50) NOT NULL PRIMARY KEY,
customer_id VARCHAR(50) NOT NULL  ,
order_status VARCHAR(50) NOT NULL,
order_purchase_timestamp DATETIME NOT NULL,
order_approved_at DATETIME,
order_delivered_carrier_date DATETIME,
order_delivered_customer_date DATETIME,
order_estimated_delivery_date DATETIME,
FOREIGN KEY (customer_id)
REFERENCES customers(customer_id));

 CREATE TABLE products (
 product_id VARCHAR(50) NOT NULL PRIMARY KEY,
 product_category_name VARCHAR(50) ,
 product_name_lengtH INT,
 product_description_lengtH INT,
 product_photos_qty INT,
 product_weight_g INT);

CREATE TABLE sellers(
seller_id VARCHAR(50) NOT NULL PRIMARY KEY,
seller_zip_code_prefix VARCHAR(20),
seller_city VARCHAR(50),
seller_state VARCHAR(50));

CREATE TABLE order_items(
order_id VARCHAR(50) NOT NULL,
order_item_id INT,
product_id VARCHAR(50) NOT NULL,
seller_id VARCHAR(50) NOT NULL,
shipping_limit_date DATETIME,
price DECIMAL(10,2) NOT NULL,
freight_value DECIMAL(10,2) NOT NULL,
FOREIGN KEY (order_id)
REFERENCES orders(order_id),
FOREIGN KEY (seller_id)
REFERENCES sellers(seller_id),
FOREIGN KEY (product_id)
REFERENCES products(product_id),
PRIMARY KEY (order_id, order_item_id));

CREATE TABLE payments(
order_id VARCHAR(50) NOT NULL,
payment_sequential INT ,
payment_type VARCHAR(50) NOT NULL,
payment_installments INT,
payment_value DECIMAL(10,2) NOT NULL ,
PRIMARY KEY (order_id, payment_sequential),
FOREIGN KEY (order_id) 
REFERENCES orders(order_id));

CREATE TABLE reviews(
review_id VARCHAR(50) PRIMARY KEY,
order_id VARCHAR(50) NOT NULL,
review_score INT NOT NULL,
review_comment_title VARCHAR(50),
review_comment_message TEXT,
review_creation_date DATETIME NOT NULL,
review_answer_timestamp DATETIME ,
FOREIGN KEY (order_id) 
REFERENCES orders(order_id));

CREATE TABLE product_category_translated(
product_category_name VARCHAR(50),
product_category_name_english VARCHAR(50));

SHOW TABLES;
SET SQL_SAFE_UPDATES = 0;

DESCRIBE raw_orders;
DESCRIBE raw_order_items;

SELECT price, freight_value
FROM raw_order_items;

SELECT *
FROM raw_order_items
WHERE price IS NULL
   OR freight_value IS NULL;
   
-- to calculate total revenue
SELECT SUM(oi.price + oi.freight_value) AS total_revenue
FROM raw_orders o
JOIN raw_order_items oi
ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered';

-- to calculate revenue by category
-- Index the matching keys in the Order Items table
CREATE INDEX idx_oi_product ON raw_order_items (product_id);
CREATE INDEX idx_oi_order ON raw_order_items (order_id);

-- Index the matching keys in the Orders and Products tables
CREATE INDEX idx_o_order ON raw_orders (order_id, order_status);
CREATE INDEX idx_p_product ON raw_products (product_id);
CREATE INDEX idx_p_cat ON raw_products (product_category_name);

-- Index the translation mapping table
CREATE INDEX idx_ct_cat ON product_category_translated (product_category_name);

SELECT 
    ct.product_category_name_english AS product_category, -- Uses translated names for readability
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
FROM raw_order_items AS oi
JOIN raw_products AS p 
    ON oi.product_id = p.product_id
JOIN raw_orders AS o
    ON oi.order_id = o.order_id
JOIN product_category_translated AS ct
    ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY ct.product_category_name_english
ORDER BY total_revenue DESC
LIMIT 1000;

-- transformed orders table with cleaned data types
CREATE TABLE cleaned_orders AS
SELECT
    order_id,
    customer_id,
    order_status,
    STR_TO_DATE(NULLIF(order_purchase_timestamp, ''), '%m/%d/%Y %H:%i')
        AS order_purchase_timestamp,
    STR_TO_DATE(NULLIF(order_approved_at, ''), '%m/%d/%Y %H:%i')
        AS order_approved_at,
    STR_TO_DATE(NULLIF(order_delivered_carrier_date, ''), '%m/%d/%Y %H:%i')
        AS order_delivered_carrier_date,
    STR_TO_DATE(NULLIF(order_delivered_customer_date, ''), '%m/%d/%Y %H:%i')
        AS order_delivered_customer_date,
    STR_TO_DATE(NULLIF(order_estimated_delivery_date, ''), '%m/%d/%Y %H:%i')
        AS order_estimated_delivery_date
FROM raw_orders;

-- Revenue over time (month)
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
FROM cleaned_orders AS o
JOIN raw_order_items AS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY order_month
ORDER BY order_month;

-- revenue by customer
SELECT co.customer_id, SUM(price + freight_value) AS total_customer_revenue, COUNT(customer_id) AS frequency
FROM cleaned_orders AS co
JOIN raw_order_items AS oi
ON co.order_id = oi.order_id
WHERE co.order_status = 'delivered'
GROUP BY co.customer_id
ORDER BY total_customer_revenue DESC ;

-- customer segmentation
SELECT 
    c.customer_unique_id,
    COUNT(DISTINCT co.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) 
        AS total_customer_revenue,
    CASE
        WHEN SUM(oi.price + oi.freight_value) > 1000
            THEN 'High Value'
        WHEN SUM(oi.price + oi.freight_value) BETWEEN 200 AND 1000
            THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_segment
FROM cleaned_orders AS co
JOIN raw_customers AS c
    ON co.customer_id = c.customer_id
JOIN raw_order_items AS oi
    ON co.order_id = oi.order_id
WHERE co.order_status = 'delivered'
GROUP BY c.customer_unique_id
ORDER BY total_customer_revenue ASC;

-- Revenue summary by min, max, avg to classify segments
SELECT
    MIN(customer_revenue) AS min_revenue,
    MAX(customer_revenue) AS max_revenue,
    AVG(customer_revenue) AS avg_revenue
FROM (
    SELECT
        c.customer_unique_id,
        SUM(oi.price + oi.freight_value)
            AS customer_revenue
    FROM cleaned_orders AS co
    JOIN raw_customers AS c
        ON co.customer_id = c.customer_id
    JOIN raw_order_items AS oi
        ON co.order_id = oi.order_id
    WHERE co.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) AS revenue_summary;

-- avg delivery time
SELECT
    ROUND(
        AVG(
            DATEDIFF( order_delivered_customer_date,
                order_purchase_timestamp)),2) AS avg_delivery_days
FROM cleaned_orders
WHERE order_status = 'delivered';

-- Late Delivery Analysis
SELECT COUNT(*) AS total_delivered_orders,
    SUM(
        CASE
            WHEN order_delivered_customer_date >
                 order_estimated_delivery_date
            THEN 1
            ELSE 0
        END
    ) AS delayed_orders,
    ROUND(100.0 * SUM(
            CASE
                WHEN order_delivered_customer_date >
                     order_estimated_delivery_date
                THEN 1
                ELSE 0
            END
        ) / COUNT(*),
        2
    ) AS delayed_order_percentage
FROM cleaned_orders
WHERE order_status = 'delivered';

-- most used payment type
SELECT
    payment_type,
    COUNT(*) AS total_transactions,
    ROUND(SUM(payment_value), 2) AS total_payment_value
FROM raw_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- Installment Analysis
SELECT
    payment_installments,
    COUNT(*) AS total_transactions,
    ROUND(SUM(payment_value), 2) AS total_payment_value
FROM raw_payments
GROUP BY payment_installments
ORDER BY payment_installments;

-- seller performance analysis
SELECT
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(
        SUM(oi.price + oi.freight_value),
        2
    ) AS total_seller_revenue
FROM raw_order_items AS oi
JOIN cleaned_orders AS o
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY oi.seller_id
ORDER BY total_seller_revenue DESC
LIMIT 10;

-- avg customer review score
SELECT
    ROUND(AVG(review_score), 2)
        AS avg_review_score
FROM raw_reviews;

-- review score distribution
SELECT
    review_score,
    COUNT(*) AS total_reviews,
    ROUND(
        100.0 * COUNT(*) /
        (SELECT COUNT(*) FROM raw_reviews),
        2
    ) AS percentage_share
FROM raw_reviews
GROUP BY review_score
ORDER BY review_score;

-- delivery delay vs review score
SELECT
    CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN 'Delayed'
        ELSE 'On Time'
    END AS delivery_status,
    ROUND(AVG(r.review_score), 2)
        AS avg_review_score,
    COUNT(*) AS total_reviews
FROM cleaned_orders AS o
JOIN raw_reviews AS r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY delivery_status;

-- customer segmentation logic for power bi visualisation
CREATE VIEW customer_segments AS
SELECT
    co.customer_id,
    COUNT(DISTINCT co.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_spent,
CASE
    WHEN SUM(oi.price + oi.freight_value) > 500
        THEN 'High Value'

    WHEN SUM(oi.price + oi.freight_value)
         BETWEEN 100 AND 500
        THEN 'Medium Value'

    ELSE 'Low Value'
END AS customer_segment
FROM cleaned_orders AS co
JOIN raw_order_items AS oi
    ON co.order_id = oi.order_id
WHERE co.order_status = 'delivered'
GROUP BY co.customer_id;

-- customer satisfaction by order level granularity for visualisation
CREATE VIEW customer_satisfaction AS
SELECT
    cs.customer_id,
    cs.customer_segment,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM customer_segments cs
JOIN cleaned_orders o
    ON cs.customer_id = o.customer_id
JOIN raw_reviews r
    ON o.order_id = r.order_id
GROUP BY
    cs.customer_id,
    cs.customer_segment;
    
-- 
CREATE VIEW category_satisfaction AS
SELECT
    ct.product_category_name_english AS product_category,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM raw_reviews r
JOIN cleaned_orders o
    ON r.order_id = o.order_id
JOIN raw_order_items oi
    ON o.order_id = oi.order_id
JOIN raw_products p
    ON oi.product_id = p.product_id
JOIN product_category_translated ct
    ON p.product_category_name = ct.product_category_name
GROUP BY
    ct.product_category_name_english;
    
-- combines category, avg review, revenu order respective to category
CREATE VIEW category_business_analysis AS
SELECT
    ct.product_category_name_english AS product_category,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM raw_order_items AS oi
JOIN raw_orders AS o
    ON oi.order_id = o.order_id
JOIN raw_products AS p
    ON oi.product_id = p.product_id
JOIN product_category_translated AS ct
    ON p.product_category_name = ct.product_category_name
JOIN raw_reviews AS r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY ct.product_category_name_english;