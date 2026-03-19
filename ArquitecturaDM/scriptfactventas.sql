/* =============================================================
   ETL - Carga de Tablas: Load, Stage y Fact Sales (Northwind)
   Databases: Load_Northwind, Stage_Northwind, Datamart_Northwind
   Autor: José Luis Herrera Gallardo
   Descripción: DDL y DML para la carga incremental de ventas
                siguiendo la metodología Kimball.
================================================================*/


/* =============================================================
   1) DDL - Tablas en Load_Northwind
      (capa de aterrizaje crudo desde la fuente NORTHWND)
================================================================*/

IF OBJECT_ID('Load_Northwind.dbo.Customers') IS NULL
BEGIN
    CREATE TABLE Load_Northwind.dbo.Customers(
        [CustomerID]    [nchar](5)      NOT NULL,
        [CompanyName]   [nvarchar](40)  NOT NULL,
        [ContactName]   [nvarchar](30)  NULL,
        [ContactTitle]  [nvarchar](30)  NULL,
        [Address]       [nvarchar](60)  NULL,
        [City]          [nvarchar](15)  NULL,
        [Region]        [nvarchar](15)  NULL,
        [PostalCode]    [nvarchar](10)  NULL,
        [Country]       [nvarchar](15)  NULL,
        [Phone]         [nvarchar](24)  NULL,
        [Fax]           [nvarchar](24)  NULL,
        ETLLoad         datetime,
        ETLExecution    int
    )
END
GO

IF OBJECT_ID('Load_Northwind.dbo.Shippers') IS NULL
BEGIN
    CREATE TABLE Load_Northwind.[dbo].[Shippers](
        [ShipperID]     [int]           NOT NULL,
        [CompanyName]   [nvarchar](40)  NOT NULL,
        [Phone]         [nvarchar](24)  NULL,
        ETLLoad         datetime,
        ETLExecution    int
    )
END
GO

IF OBJECT_ID('Load_Northwind.dbo.Orders') IS NULL
BEGIN
    CREATE TABLE Load_Northwind.[dbo].[Orders](
        [OrderID]           [int]           NOT NULL,
        [CustomerID]        [nchar](5)      NULL,
        [EmployeeID]        [int]           NULL,
        [OrderDate]         [datetime]      NULL,
        [RequiredDate]      [datetime]      NULL,
        [ShippedDate]       [datetime]      NULL,
        [ShipVia]           [int]           NULL,
        [Freight]           [money]         NULL,
        [ShipName]          [nvarchar](40)  NULL,
        [ShipAddress]       [nvarchar](60)  NULL,
        [ShipCity]          [nvarchar](15)  NULL,
        [ShipRegion]        [nvarchar](15)  NULL,
        [ShipPostalCode]    [nvarchar](10)  NULL,
        [ShipCountry]       [nvarchar](15)  NULL,
        ETLLoad             datetime,
        ETLExecution        int
    )
END
GO

IF OBJECT_ID('Load_Northwind.dbo.Order Details') IS NULL
BEGIN
    CREATE TABLE Load_Northwind.[dbo].[Order Details](
        [OrderID]       [int]       NOT NULL,
        [ProductID]     [int]       NOT NULL,
        [UnitPrice]     [money]     NOT NULL,
        [Quantity]      [smallint]  NOT NULL,
        [Discount]      [real]      NOT NULL,
        ETLLoad         datetime,
        ETLExecution    int
    )
END
GO


/* =============================================================
   2) DDL - Tablas en Stage_Northwind
      (capa de transformación / limpieza)
================================================================*/

IF OBJECT_ID('Stage_Northwind.dbo.Customers') IS NULL
BEGIN
    CREATE TABLE Stage_Northwind.dbo.Customers(
        [CustomerID]    [nchar](5)      NOT NULL,
        [CompanyName]   [nvarchar](40)  NOT NULL,
        [ContactName]   [nvarchar](30)  NULL,
        [ContactTitle]  [nvarchar](30)  NULL,
        [Address]       [nvarchar](60)  NULL,
        [City]          [nvarchar](15)  NULL,
        [Region]        [nvarchar](15)  NULL,
        [PostalCode]    [nvarchar](10)  NULL,
        [Country]       [nvarchar](15)  NULL,
        ETLLoad         datetime,
        ETLExecution    int
    )
END
GO

IF OBJECT_ID('Stage_Northwind.dbo.Shippers') IS NULL
BEGIN
    CREATE TABLE Stage_Northwind.[dbo].[Shippers](
        [ShipperID]     [int]           NOT NULL,
        [CompanyName]   [nvarchar](40)  NOT NULL,
        [Phone]         [nvarchar](24)  NULL,
        ETLLoad         datetime,
        ETLExecution    int
    )
END
GO

IF OBJECT_ID('Stage_Northwind.dbo.Stage_Ventas') IS NULL
BEGIN
    CREATE TABLE Stage_Northwind.[dbo].[Stage_Ventas](
        [Cliente_Codigo]        [char](5)       NOT NULL,
        [Empleado_Codigo]       [int]           NOT NULL,
        [Producto_Codigo]       [int]           NOT NULL,
        [Transportista_codigo]  [int]           NOT NULL,
        [Ventas_OrderDate]      [datetime]      NOT NULL,
        [Ventas_NOrden]         [int]           NOT NULL,
        [Ventas_Monto]          [decimal](15,2) NOT NULL,
        [Ventas_Unidades]       [int]           NOT NULL,
        [Ventas_PUnitario]      [decimal](15,2) NOT NULL,
        [Ventas_Descuento]      [decimal](15,2) NOT NULL,
        [ETLLoad]               [datetime]      NULL,
        [ETLExecution]          [int]           NULL
    )
END
GO


/* =============================================================
   3) DML - Carga de dimensiones en Datamart_Northwind
      (carga inicial desde fuente; solo para carga manual/inicial)
================================================================*/

-- dim_shipper
INSERT INTO Datamart_Northwind.dbo.dim_shipper (shipperid_nk, company_name)
SELECT ShipperID, CompanyName
FROM NORTHWND.dbo.Shippers
GO

-- dim_customer (SCD Type 2 - carga inicial)
INSERT INTO Datamart_Northwind.dbo.dim_customer
    (customerid_nk, company_name, contact_name, contact_title,
     [address], city, region, postal_code, country, start_date, end_date)
SELECT
    CustomerID, CompanyName, ContactName, ContactTitle, [Address],
    City, ISNULL(Region, 'NO REGION') AS Region, PostalCode, Country,
    GETDATE() AS start_date,
    NULL AS end_date
FROM NORTHWND.dbo.Customers
GO


/* =============================================================
   4) DML - Carga de Stage_Ventas desde Load_Northwind
      (query utilizado en SSIS; filtra por ETLExecution para carga incremental)
================================================================*/

-- Nota: los parámetros (?) son sustituidos por SSIS en tiempo de ejecución.
INSERT INTO Stage_Northwind.dbo.[Stage_Ventas]
    (Cliente_Codigo, Empleado_Codigo, Producto_Codigo, Transportista_codigo,
     Ventas_OrderDate, Ventas_NOrden, Ventas_Monto, Ventas_Unidades,
     Ventas_PUnitario, Ventas_Descuento)
SELECT
    o.CustomerID,
    o.EmployeeID,
    od.ProductID,
    o.ShipVia,
    o.OrderDate,
    o.OrderID,
    (od.UnitPrice * od.Quantity * (1 - od.Discount)) AS Monto,
    od.Quantity,
    od.UnitPrice,
    od.Discount
FROM Load_Northwind.dbo.Orders AS o
INNER JOIN Load_Northwind.dbo.[Order Details] AS od
    ON o.OrderID = od.OrderID
WHERE o.ETLExecution = ? AND od.ETLExecution = ?
GO


/* =============================================================
   5) DML - Carga incremental de fact_sales desde Stage_Northwind
      Considera SCD Type 2 en dim_customer (join por rango de fechas).
      Solo inserta ventas posteriores a la última fecha ya cargada.
================================================================*/

INSERT INTO Datamart_Northwind.dbo.fact_sales
    (order_date_key, customer_key, product_key, employee_key, shipper_key,
     order_number, order_qty, unit_price, discount)
SELECT
      dd.date_key         AS order_date_key
    , dc.customer_key
    , dp.product_key
    , de.employee_key
    , ds.shipper_key
    , sv.[Ventas_NOrden]
    , sv.[Ventas_Unidades]
    , sv.[Ventas_PUnitario]
    , sv.[Ventas_Descuento]
FROM [STAGE_NORTHWIND].[dbo].[Stage_Ventas] AS sv
JOIN [Datamart_Northwind].dbo.dim_customer AS dc
    ON  sv.Cliente_Codigo   = dc.customerid_nk
    AND sv.Ventas_OrderDate >= dc.start_date
    AND sv.Ventas_OrderDate <  ISNULL(dc.end_date, '9999-12-31')  -- SCD2: versión vigente en la fecha de la venta
JOIN Datamart_Northwind.[dbo].[dim_employee] AS de
    ON sv.Empleado_Codigo   = de.employeeid_nk
JOIN Datamart_Northwind.[dbo].[dim_product] AS dp
    ON sv.Producto_Codigo   = dp.productid_nk
JOIN [Datamart_Northwind].[dbo].[dim_date] AS dd
    ON dd.[date]            = sv.Ventas_OrderDate
JOIN Datamart_Northwind.dbo.dim_shipper AS ds
    ON ds.shipperid_nk      = sv.Transportista_codigo
WHERE sv.Ventas_OrderDate >
    COALESCE(
        (SELECT MAX(d.[date])
         FROM Datamart_Northwind.dbo.fact_sales fs
         JOIN Datamart_Northwind.dbo.dim_date d
             ON fs.order_date_key = d.date_key),
        '19000101'
    )
ORDER BY
      dc.customer_key
    , de.employee_key
    , dp.product_key
    , ds.shipper_key
    , dd.date_key
    , sv.Ventas_NOrden;
GO
