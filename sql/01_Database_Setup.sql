-- =====================================================================================================================
-- 01_Database_Setup.sql
-- Instacart Market Basket Analysis - PostgreSQL database setup
-- =====================================================================================================================

-- More memory for building indexes and constraints on the ~32M-row table (applies to this session only)
SET maintenance_work_mem = '512MB';


-- =====================================================================================================================
-- STEP 1: Clean slate (makes the script re-runnable)
-- =====================================================================================================================
DROP TABLE IF EXISTS
    order_products_train,
    order_products_prior,
    orders,
    products,
    aisles,
    departments;


-- =====================================================================================================================
-- STEP 2: Data model
-- Primary keys of the large tables and all foreign keys are added in STEP 4, after the bulk load.
-- =====================================================================================================================
CREATE TABLE aisles (
    aisle_id SMALLINT PRIMARY KEY,
    aisle    VARCHAR(100)
);

CREATE TABLE departments (
    department_id SMALLINT PRIMARY KEY,
    department    VARCHAR(100)
);

CREATE TABLE products (
    product_id    INTEGER PRIMARY KEY,
    product_name  VARCHAR(255),
    aisle_id      SMALLINT,
    department_id SMALLINT
);

CREATE TABLE orders (
    order_id               INTEGER PRIMARY KEY,
    user_id                INTEGER  NOT NULL,   
    eval_set               VARCHAR(10) NOT NULL, 
    order_number           SMALLINT NOT NULL,   
    order_dow              SMALLINT,
    order_hour_of_day      SMALLINT,
    days_since_prior_order REAL             
                                      
);

-- Order line items of the 'prior' orders (history)
CREATE TABLE order_products_prior (
    order_id          INTEGER,
    product_id        INTEGER,
    add_to_cart_order SMALLINT,
    reordered         SMALLINT
);

-- Order line items of each user's last order for the 'train' set (loaded for completeness, not used in the analyses)
CREATE TABLE order_products_train (
    order_id          INTEGER,
    product_id        INTEGER,
    add_to_cart_order SMALLINT,
    reordered         SMALLINT
);


-- =====================================================================================================================
-- STEP 3: Bulk load
-- Only 'data_dir' needs to be edited.
-- =====================================================================================================================
DO $$
DECLARE
    data_dir TEXT := 'C:/path/to/instacart/data/';   -- <<< EDIT THIS LINE
    f        RECORD;
BEGIN
    FOR f IN
        SELECT * FROM (VALUES
            ('aisles',               'aisles.csv'),
            ('departments',          'departments.csv'),
            ('products',             'products.csv'),
            ('orders',               'orders.csv'),
            ('order_products_prior', 'order_products__prior.csv'),
            ('order_products_train', 'order_products__train.csv')
        ) AS t(table_name, file_name)
    LOOP
        EXECUTE format(
            'COPY %I FROM %L WITH (FORMAT csv, HEADER true, ENCODING ''UTF8'')',
            f.table_name,
            data_dir || f.file_name
        );
        RAISE NOTICE 'Loaded % from %', f.table_name, f.file_name;
    END LOOP;
END
$$;


-- =====================================================================================================================
-- STEP 4: Constraints (after the load, so each index is built once instead of being updated row by row)
-- =====================================================================================================================

-- Primary keys: one product appears at most once per order
ALTER TABLE order_products_prior
    ADD CONSTRAINT pk_order_products_prior PRIMARY KEY (order_id, product_id);

ALTER TABLE order_products_train
    ADD CONSTRAINT pk_order_products_train PRIMARY KEY (order_id, product_id);

-- Foreign keys: these match the relationships in instacart_schema.svg
ALTER TABLE products
    ADD CONSTRAINT fk_products_aisles      FOREIGN KEY (aisle_id)      REFERENCES aisles (aisle_id),
    ADD CONSTRAINT fk_products_departments FOREIGN KEY (department_id) REFERENCES departments (department_id);

ALTER TABLE order_products_prior
    ADD CONSTRAINT fk_order_products_prior_orders   FOREIGN KEY (order_id)   REFERENCES orders (order_id),
    ADD CONSTRAINT fk_order_products_prior_products FOREIGN KEY (product_id) REFERENCES products (product_id);

ALTER TABLE order_products_train
    ADD CONSTRAINT fk_order_products_train_orders   FOREIGN KEY (order_id)   REFERENCES orders (order_id),
    ADD CONSTRAINT fk_order_products_train_products FOREIGN KEY (product_id) REFERENCES products (product_id);


-- =====================================================================================================================
-- STEP 5: Indexes
-- - order_products_*: the composite primary key (order_id, product_id) already serves every lookup by order_id,
--   so no extra index is needed there. No analysis starts from product_id, so there is no index on it either.
-- - orders: user_id first, order_number second, serves the per-user aggregations (MAX(order_number)) and the
--   window functions that partition by user_id and order by order_number.
-- =====================================================================================================================
CREATE INDEX idx_orders_user_order ON orders (user_id, order_number);


-- =====================================================================================================================
-- STEP 6: Refresh planner statistics after loading millions of rows
-- =====================================================================================================================
ANALYZE aisles, departments, products, orders, order_products_prior, order_products_train;


-- =====================================================================================================================
-- STEP 7: Data quality checks
-- 'expected' holds the figures usually reported for this dataset. Any row with status = 'CHECK' deserves a look.
-- =====================================================================================================================
WITH user_stats AS (
    SELECT
        user_id,
        MAX(order_number) AS total_orders
    FROM orders
    GROUP BY user_id
),

checks AS (
    SELECT 'rows: aisles' AS check_name, COUNT(*) AS actual, 134 AS expected FROM aisles
    UNION ALL
    SELECT 'rows: departments', COUNT(*), 21 FROM departments
    UNION ALL
    SELECT 'rows: products', COUNT(*), 49688 FROM products
    UNION ALL
    SELECT 'rows: orders', COUNT(*), 3421083 FROM orders
    UNION ALL
    SELECT 'rows: order_products_prior', COUNT(*), 32434489 FROM order_products_prior
    UNION ALL
    SELECT 'rows: order_products_train', COUNT(*), 1384617 FROM order_products_train
    UNION ALL
    SELECT 'distinct users', COUNT(*), 206209 FROM user_stats
    UNION ALL
    -- Every user has exactly one order without a previous order, so this must equal the number of users
    SELECT 'orders with NULL days_since_prior_order = users',
           COUNT(*) FILTER (WHERE days_since_prior_order IS NULL),
           (SELECT COUNT(*) FROM user_stats)
    FROM orders
    UNION ALL
    SELECT 'min orders per user', MIN(total_orders), 4 FROM user_stats
    UNION ALL
    SELECT 'max orders per user', MAX(total_orders), 100 FROM user_stats
    UNION ALL
    SELECT 'max days_since_prior_order (dataset cap)', MAX(days_since_prior_order)::BIGINT, 30 FROM orders
)

SELECT
    check_name,
    actual,
    expected,
    CASE WHEN actual = expected THEN 'OK' ELSE 'CHECK' END AS status
FROM checks;
