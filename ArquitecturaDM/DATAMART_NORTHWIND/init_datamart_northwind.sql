/* =============================================================
DataMart de Ventas (Northwind) - DDL Construcción Esquema start
Databases: Datamart_Northwind
Autor: José Luis Herrera Gallardo
================================================================*/

USE Datamart_Northwind;
GO


/* =================================
   1) dim_customer (SCD Type 2)
   =================================*/ 
 IF OBJECT_ID('dim_customer') IS NULL
    BEGIN
        CREATE TABLE dim_customer (
            customer_key          INT IDENTITY(1,1) PRIMARY KEY, 
            customerid_nk         NVARCHAR(10) NOT NULL, -- clave natural (source)
            company_name          NVARCHAR(40) NOT NULL,
            contact_name          NVARCHAR(30) NULL, 
            contact_title         NVARCHAR(30) NULL,
            [address]             NVARCHAR(60) NULL,
            city                  NVARCHAR(15) NULL,
            region                NVARCHAR(15) NULL,
            postal_code           NVARCHAR(10) NULL, 
            country               NVARCHAR(15) NULL,
            start_date            DATE NOT NULL, 
            end_date              DATE NULL, 
            is_current            BIT NOT NULL DEFAULT (1)
        );
    END
 GO

/* =================================
   2) dim_product (SCD Type 1)
   =================================*/ 

IF OBJECT_ID ('dim_product') IS NULL
BEGIN
CREATE TABLE dim_product(
    product_key INT IDENTITY(1,1) PRIMARY KEY, 
    productid_nk INT NOT NULL, 
    product_name NVARCHAR(40) NOT NULL, 
    category_name NVARCHAR(15) NOT NULL, 
    supplier_name NVARCHAR(40) NOT NULL,
    quantity_per_unit NVARCHAR(20) NOT NULL, 
    discontinued BIT NOT NULL 
);
END
GO

/* =================================
   3) dim_employee (SCD Type 1)
   =================================*/ 

IF OBJECT_ID ('dim_employee') IS NULL
BEGIN
CREATE TABLE dim_employee(
    employee_key INT IDENTITY(1,1) PRIMARY KEY, 
    employeeid_nk INT NOT NULL, 
    full_name NVARCHAR(61) NOT NULL, 
    [title] NVARCHAR(30) NULL, 
    hire_date DATE NULL
);
END
GO

/* =================================
   4) dim_shipper (SCD Type 1)
   =================================*/ 

IF OBJECT_ID ('dim_shipper') IS NULL
BEGIN
CREATE TABLE dim_shipper(
    shipper_key INT IDENTITY(1,1) PRIMARY KEY, 
    shipperid_nk INT NOT NULL, 
    company_name NVARCHAR(40) NOT NULL
);
END
GO


/* =================================
   5) dim_date (conformada)
   =================================*/ 

IF OBJECT_ID ('dim_date') IS NULL
BEGIN
CREATE TABLE dim_date(
   date_key INT NOT NULL PRIMARY KEY, --- YYYYMMDD
   [date]  DATE NOT NULL, 
   [day] TINYINT NOT NULL, --- 1...31
   [month] TINYINT NOT NULL,  -- 1 ... 12
   month_name VARCHAR(20) NOT NULL, 
   [quarter] TINYINT NOT NULL, --- 1 ... 4
   [year] SMALLINT NOT NULL, 
   week_of_year TINYINT NOT NULL, 
   is_weekend BIT NOT NULL
);
END
GO


/* =================================
   6) dim_supplier (SCD Type 2)
   =================================*/ 

IF OBJECT_ID('dim_supplier') IS NULL
    BEGIN
        CREATE TABLE dim_supplier (
            supplier_key          INT IDENTITY(1,1) PRIMARY KEY, 
            supplierid_nk         INT NOT NULL, -- clave natural (source)
            company_name          NVARCHAR(40) NOT NULL,
            contact_name          NVARCHAR(30) NULL, 
            contact_title         NVARCHAR(30) NULL,
            [address]             NVARCHAR(60) NULL,
            city                  NVARCHAR(15) NULL,
            region                NVARCHAR(15) NULL,
            postal_code           NVARCHAR(10) NULL, 
            country               NVARCHAR(15) NULL,
            start_date            DATE NOT NULL, 
            end_date              DATE NULL, 
            is_current            BIT NOT NULL DEFAULT (1)
        );
    END
GO

/* =================================
   7) fact_sales (grano: linea de pedido (pedido - producto))
   =================================*/

IF OBJECT_ID ('fact_sales') IS NULL
BEGIN
CREATE TABLE fact_sales(

    fact_sales_key BIGINT IDENTITY(1,1) PRIMARY KEY,
     
    -- Dimensiones
    order_date_key     INT NOT NULL,
    customer_key       INT NOT NULL, 
    product_key        INT NOT NULL, 
    employee_key       INT NOT NULL, 
    shipper_key        INT NOT NULL, 
    supplier_key       INT NOT NULL,
    order_number       INT NOT NULL,    --- orderID

    -- Medidas
    order_qty    INT NOT NULL, 
    unit_price   DECIMAL(19,4) NOT NULL, 
    discount     DECIMAL(5,4) NOT NULL, -- [0...1] 
    extended_amount AS (CAST(order_qty * unit_price * (1 - discount) AS DECIMAL(19,4))) PERSISTED,

    -- checks
    CONSTRAINT chk_fact_sales_qty_positive CHECK (order_qty > 0), 
    CONSTRAINT chk_fact_sales_price_positive CHECK (unit_price > 0),
    CONSTRAINT chk_fact_sales_dicount_01 CHECK (discount >= 0 and discount <=1)

);
END
GO

/* fk building*/

ALTER TABLE fact_sales 
ADD CONSTRAINT fk_fact_sales_dim_date
FOREIGN KEY (order_date_key)
REFERENCES dim_date (date_key)
GO

ALTER TABLE fact_sales 
ADD CONSTRAINT fk_fact_sales_dim_customer
FOREIGN KEY (customer_key)
REFERENCES dim_customer (customer_key)
GO

ALTER TABLE fact_sales 
ADD CONSTRAINT fk_fact_sales_dim_product
FOREIGN KEY (product_key)
REFERENCES dim_product (product_key)
GO

ALTER TABLE fact_sales 
ADD CONSTRAINT fk_fact_sales_dim_employee
FOREIGN KEY (employee_key)
REFERENCES dim_employee (employee_key)
GO

ALTER TABLE fact_sales 
ADD CONSTRAINT fk_fact_sales_dim_shipper
FOREIGN KEY (shipper_key)
REFERENCES dim_shipper (shipper_key)
GO


ALTER TABLE fact_sales 
ADD CONSTRAINT fk_fact_sales_dim_suplier
FOREIGN KEY (supplier_key)
REFERENCES dim_supplier (supplier_key)
GO