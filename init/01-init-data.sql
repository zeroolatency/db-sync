-- Create sample tables and data for the source database
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    product_name VARCHAR(100) NOT NULL,
    quantity INTEGER NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (name, email) VALUES 
    ('John Doe', 'john.doe@example.com'),
    ('Jane Smith', 'jane.smith@example.com'),
    ('Bob Johnson', 'bob.johnson@example.com'),
    ('Alice Brown', 'alice.brown@example.com'),
    ('Charlie Wilson', 'charlie.wilson@example.com');

INSERT INTO orders (user_id, product_name, quantity, price) VALUES 
    (1, 'Laptop', 1, 999.99),
    (1, 'Mouse', 2, 25.50),
    (2, 'Keyboard', 1, 75.00),
    (3, 'Monitor', 1, 299.99),
    (4, 'Headphones', 1, 150.00),
    (5, 'Webcam', 1, 89.99),
    (2, 'Tablet', 1, 399.99),
    (3, 'Phone', 1, 699.99);

-- Create some additional tables for more comprehensive data
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0
);

INSERT INTO products (name, category, price, stock_quantity) VALUES 
    ('MacBook Pro', 'Electronics', 1999.99, 10),
    ('iPhone 14', 'Electronics', 999.99, 25),
    ('Samsung Galaxy', 'Electronics', 899.99, 15),
    ('Dell Monitor', 'Electronics', 299.99, 20),
    ('Logitech Mouse', 'Accessories', 29.99, 50),
    ('Mechanical Keyboard', 'Accessories', 129.99, 30);

-- Create a view for order summary
CREATE VIEW order_summary AS
SELECT 
    u.name as customer_name,
    u.email,
    o.product_name,
    o.quantity,
    o.price,
    o.order_date
FROM users u
JOIN orders o ON u.id = o.user_id
ORDER BY o.order_date DESC;
