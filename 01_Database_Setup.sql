-- Data Model Creation


CREATE TABLE aisles (
    aisle_id SMALLINT PRIMARY KEY,
    aisle VARCHAR(100)
);

CREATE TABLE departments (
    department_id SMALLINT PRIMARY KEY,
    department VARCHAR(100)
);

CREATE TABLE products (
    product_id INTEGER PRIMARY KEY,
    product_name VARCHAR(255),
    aisle_id SMALLINT,
    department_id SMALLINT
);

CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    user_id INTEGER,
    eval_set VARCHAR(10),
    order_number SMALLINT,
    order_dow SMALLINT,
    order_hour_of_day SMALLINT,
    days_since_prior_order REAL
);

CREATE TABLE order_products_prior (
    order_id INTEGER,
    product_id INTEGER,
    add_to_cart_order SMALLINT,
    reordered SMALLINT
);

CREATE TABLE order_products_train (
    order_id INTEGER,
    product_id INTEGER,
    add_to_cart_order SMALLINT,
    reordered SMALLINT
);


-- Loading data to populate their respective tables 

COPY aisles FROM 'C:\Users\joaof\Desktop\Projects_db\SQL\Instacard_Market_Analysis\data\aisles.csv' DELIMITER ',' CSV HEADER;
COPY departments FROM 'C:\Users\joaof\Desktop\Projects_db\SQL\Instacard_Market_Analysis\data\departments.csv' DELIMITER ',' CSV HEADER;
COPY products FROM 'C:\Users\joaof\Desktop\Projects_db\SQL\Instacard_Market_Analysis\data\products.csv' DELIMITER ',' CSV HEADER;
COPY orders FROM 'C:\Users\joaof\Desktop\Projects_db\SQL\Instacard_Market_Analysis\data\orders.csv' DELIMITER ',' CSV HEADER;
COPY order_products_prior FROM 'C:\Users\joaof\Desktop\Projects_db\SQL\Instacard_Market_Analysis\data\order_products__prior.csv' DELIMITER ',' CSV HEADER;
COPY order_products_train FROM 'C:\Users\joaof\Desktop\Projects_db\SQL\Instacard_Market_Analysis\data\order_products__train.csv' DELIMITER ',' CSV HEADER;


-- Creating indexes to improve query performance by allowing PostgreSQL to find rows faster without scanning the entire table.
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_opp_order_id ON order_products_prior(order_id);
CREATE INDEX idx_opp_product_id ON order_products_prior(product_id);

-- Quality check
SELECT 'aisles' AS table_name, COUNT(*) AS row_count FROM aisles
UNION ALL
SELECT 'departments', COUNT(*) FROM departments
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_products_prior', COUNT(*) FROM order_products_prior
UNION ALL
SELECT 'order_products_train', COUNT(*) FROM order_products_train;

SELECT * FROM orders LIMIT 5;
