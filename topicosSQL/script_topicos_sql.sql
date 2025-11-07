
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name =N'miniBD')
BEGIN
	CREATE DATABASE miniBD
	COLLATE Latin1_General_100_CI_AS_SC_UTF8;
END 
GO

USE miniBD;
GO

-- Creaci�n de tablas 
IF OBJECT_ID('clientes', 'U') IS NOT NULL DROP TABLE clientes;

CREATE TABLE clientes(
  IdCliente INT not null, 
  Nombre NVARCHAR(100), 
  Edad INT, 
  Ciudad NVARCHAR(100),
  CONSTRAINT pk_clientes
  PRIMARY KEY (idcliente)
);
GO

IF OBJECT_ID('productos', 'U') IS NOT NULL DROP TABLE productos;

CREATE TABLE productos(
   Idproducto INT primary key,
   NombreProducto NVARCHAR(200), 
   Categoria NVARCHAR(200), 
   Precio DECIMAL(12,2)
);
GO

/*
  ===============Inserción de registros en las tablas ====================
*/



INSERT INTO clientes 
VALUES (1, 'Ana Torres', 25, 'Ciudad de México');

INSERT INTO clientes (IdCliente, Nombre, Edad, Ciudad)
VALUES(2, 'Luis Perez', 34, 'Guadalajara');
 
INSERT INTO clientes (IdCliente, Edad, Nombre, Ciudad)
VALUES (3, 29, 'Soyla Vaca', NULL);

INSERT INTO clientes (IdCliente, Nombre, Edad)
VALUES (4, 'Natacha', 41);

INSERT INTO clientes (IdCliente, Nombre, Edad, Ciudad)
VALUES (5, 'Sofía Lopez', 19, 'Chapulhuacan'),
       (6, 'Laura Hernandez', 38, NULL), 
	   (7, 'Victor Trujillo', 25, 'Zacualtipan');

GO

CREATE OR ALTER PROCEDURE sp_add_customer
 @Id INT, @Nombre NVARCHAR(100), @edad INT, @ciudad NVARCHAR(100)
AS
BEGIN 
	INSERT INTO clientes (IdCliente, Nombre, Edad, Ciudad)
	VALUES (@Id, @Nombre, @edad, @ciudad );
END;
GO

EXEC sp_add_customer 8, 'Carlos Ruiz', 41, 'Monterrey';
EXEC sp_add_customer 9, 'Jose Angel Perez', 74, 'Salte si Puedes';

SELECT *
FROM clientes;

SELECT COUNT(*) AS [Número de Clientes]
FROM clientes;

-- Mostrar todos los clientes ordenados por edad de menor a mayor
SELECT UPPER (Nombre) AS [Cliente], edad, UPPER(ciudad) AS [Ciudad]
FROM clientes
ORDER BY edad DESC;

-- Listar los clientes que viven en Guadalajara
SELECT UPPER (Nombre) AS [Cliente], edad, UPPER(ciudad) AS [Ciudad]
FROM clientes
WHERE Ciudad = 'Guadalajara';

-- Listar los clientes con una edad mayor o igual a 30
SELECT UPPER (Nombre) AS [Cliente], edad, UPPER(ciudad) AS [Ciudad]
FROM clientes
WHERE edad>=30;

-- Listar los clientes cuya ciudad sea nula
SELECT UPPER (Nombre) AS [Cliente], edad, UPPER(ciudad) AS [Ciudad]
FROM clientes
WHERE ciudad IS NULL;

-- Reemplazar en la consulta las ciudades nulas por la palabra DESCONOCIDA 
-- (sin modificar los datos orginales)

SELECT UPPER (Nombre) AS [Cliente], edad, 
ISNULL(UPPER(ciudad), 'DESCONOCIDO') AS [ciudad]
FROM clientes;

-- Selecciona los clientes que tengan edad entre 20 y 35 
-- y que vivan en puebla o Monterrey

SELECT UPPER (Nombre) AS [Cliente], edad, 
ISNULL(UPPER(ciudad), 'DESCONOCIDO') AS [ciudad]
FROM clientes
WHERE edad between 20 and 35 
      AND
	  Ciudad IN ('Guadalajara', 'Chapulhuacan');

/*
  ========================== Actualización de Datos ==================================0

*/

SELECT 
*
FROM clientes;

UPDATE clientes
SET ciudad = 'Xochitlan'
WHERE IdCliente = 5;

UPDATE clientes
SET ciudad = 'Sin Ciudad'
WHERE ciudad is null;

UPDATE clientes
SET edad = 30
WHERE IdCliente BETWEEN 3 and 6;

UPDATE clientes
SET ciudad = 'Metropoli'
WHERE ciudad IN 
('ciudad de México', 'Guadalajara', 'Monterrey');

UPDATE clientes
SET Nombre = 'Juan Perez', 
    Edad = 27, 
	Ciudad = 'Ciudad Gotica'
WHERE IdCliente = 2;

Update clientes
SET nombre = 'Cliente Premium'
WHERE Nombre like 'A%';

UPDATE clientes
SET nombre = 'silver customer'
where nombre like '%er%';

UPDATE clientes
SET edad = (edad * 2)
WHERE edad >=30 and ciudad = 'metropoli';

/*
   =============== Eliminar Datos ============ */

SELECT 
*
FROM clientes;


DELETE FROM clientes
WHERE edad BETWEEN 25 AND 30;

DELETE clientes
WHERE Nombre LIKE '%r';

TRUNCATE TABLE clientes;
Go
/* 
  =========== Store Procedures de Update, Delete, Select
*/

-- Modificar los datos por id
CREATE OR ALTER PROC sp_update_customers
 @id int , @nombre nvarchar(100), 
 @edad int, @ciudad nvarchar(100)
AS
BEGIN
   UPDATE clientes
   SET Nombre = @nombre, 
       Edad = @edad, 
	   Ciudad = @ciudad
   WHERE IdCliente = @id;
END;

EXEC sp_update_customers 
7,'Benito kano', 24, 'Lima los pies'; 

SELECT 
*
FROM clientes;
GO

EXECUTE sp_update_customers 
@ciudad='Martinez de la Torre', 
@edad = 56,
@id = 3, 
@nombre = 'Toribio Trompudo';

-- Ejercicio completo donde se pueda insertar datos en una tabla 
-- principal (encabezado) y una tabla detalle utilizando un sp.

-- Tabla principal
CREATE TABLE ventas(
  IdVenta int IDENTITY (1,1) PRIMARY KEY, 
  FechaVenta DATETIME NOT NULL DEFAULT GETDATE(),
  Cliente NVARCHAR(100) NOT NULL, 
  Total DECIMAL (10,2) NULL
);
GO
-- Tabla detalle
CREATE TABLE DetalleVenta(
	IdDetalle INT IDENTITY (1,1) PRIMARY KEY, 
	IdVenta INT NOT NULL, 
	Producto NVARCHAR(100) NOT NULL, 
	Cantidad INT NOT NULL, 
	Precio DECIMAL(10,2) NOT NULL 
	CONSTRAINT pk_detalleVenta_venta
	FOREIGN KEY (IdVenta)
	REFERENCES Ventas(IdVenta)
);
GO
-- Crear un tipo de tabla (Table Type)

-- Este tipo de tabla servirá como estructura para enviar los 
-- detalles al sp

CREATE TYPE TipoDetalleVentas AS TABLE (
	Producto NVARCHAR(100), 
	Cantidad INT, 
	Precio DECIMAL(10,2)
);
GO
-- CREAR EL STORE PROCEDURE
-- El sp insertará el encabezado y luego todos los detalles
-- utilizando el tipo de tabla

CREATE OR ALTER PROCEDURE InsertarVentaConDetalle
 @Cliente nvarchar(100), 
 @Detalles TipoDetalleVentas READONLY
 AS
 BEGIN 
   SET NOCOUNT ON;

   DECLARE @IdVenta INT;

   BEGIN TRY
		BEGIN TRANSACTION;

		-- Insertar en la tabla principal
		INSERT INTO ventas (Cliente)
		VALUES(@Cliente);

		-- Obtener el ID recién generado
		SET @IdVenta = SCOPE_IDENTITY();

		-- INSERTAR LOS DETALLES (Tabla detalles)
		INSERT INTO DetalleVenta (IdVenta, Producto, Cantidad, precio)
		SELECT @IdVenta, producto, cantidad, precio
		FROM @Detalles;

		-- Calcular el total de venta
		UPDATE Ventas
		SET Total = (SELECT SUM(Cantidad * Precio) FROM @Detalles)
		WHERE IdVenta = @IdVenta;

		COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH
		ROLLBACK TRANSACTION;
		THROW;
	END CATCH;	
 END;
 GO
 -- Ejecutar el SP con datos de prueba

 -- Declarar una variable tipo tabla  
 DECLARE @MisDetalles AS TipoDetalleVentas

 -- Insertar productos en el Type Table
 INSERT INTO @MisDetalles (Producto, Cantidad, Precio)
 VALUES
 ('Laptop', 1, 15000), 
 ('Mouse', 2, 300),
 ('Teclado', 1, 500), 
 ('Pantalla', 5, 4500);


 -- Ejecutar el SP
 EXEC InsertarVentaConDetalle @Cliente='Uriel Edgar', @Detalles=@MisDetalles;
 GO                          
      

 Select * from ventas;
 Select * from DetalleVenta;

 -- Funciones Integradas (Built-in Functions)

 -- Funciones
 SELECT
 Nombre AS [Nombre Fuente],
 LTRIM(UPPER(Nombre)) AS Mayusculas, 
 LOWER(Nombre) AS Minusculas,
 LEN(Nombre) AS Longitud, 
 SUBSTRING(Nombre, 1,3) AS Prefijo, 
 LTRIM(Nombre) AS [Sin Espacios Izquierda],
 CONCAT(Nombre, ' - ', Edad) AS [Nombre Edad], 
 UPPER(REPLACE(TRIM(Ciudad), 'Chapulhucan', 'Chapu')) AS [Ciudad Normal]
 FROM clientes;

 SELECT * FROM clientes
 
 INSERT INTO clientes(IdCliente, Nombre, Edad, Ciudad)
 VALUES (8, 'Luis López', 45, 'Achichilco');

 INSERT INTO clientes(IdCliente, Nombre, Edad, Ciudad)
 VALUES (9, ' German Galindo', 32, 'Achichilco2  ');

  INSERT INTO clientes(IdCliente, Nombre, Edad, Ciudad)
 VALUES (10, ' Jaen Porfirio ', 19, 'Achichilco3  ');

   INSERT INTO clientes(IdCliente, Nombre, Edad, Ciudad)
 VALUES (11, ' Roberto Estrada  ', 19, 'chapulhuacan  ');

 -- Crear una tabla a partir de una consulta
 SELECT TOP 0
 idCliente,
 Nombre AS [Nombre Fuente],
 LTRIM(UPPER(Nombre)) AS Mayusculas, 
 LOWER(Nombre) AS Minusculas,
 LEN(Nombre) AS Longitud, 
 SUBSTRING(Nombre, 1,3) AS Prefijo, 
 LTRIM(Nombre) AS [Sin Espacios Izquierda],
 CONCAT(Nombre, ' - ', Edad) AS [Nombre Edad], 
 UPPER(REPLACE(TRIM(Ciudad), 'Chapulhucan', 'Chapu')) AS [Ciudad Normal]
 INTO stage_clientes
 FROM clientes;

 -- Agrega un constraint a la tabla (primary key)
 ALTER TABLE stage_clientes
 ADD CONSTRAINT pk_stage_clientes
 PRIMARY KEY(idCliente);

 SELECT * FROM 
 stage_clientes;

 -- Insertar datos a partir de una consulta (Insert - Select)
 INSERT INTO stage_clientes (IdCliente, 
                            [Nombre Fuente], 
							Mayusculas, 
							Minusculas, 
							Longitud, 
							Prefijo, 
							[Sin Espacios Izquierda], 
							[Nombre Edad], [Ciudad Normal])
 SELECT 
 idCliente,
 Nombre AS [Nombre Fuente],
 LTRIM(UPPER(Nombre)) AS Mayusculas, 
 LOWER(Nombre) AS Minusculas,
 LEN(Nombre) AS Longitud, 
 SUBSTRING(Nombre, 1,3) AS Prefijo, 
 LTRIM(Nombre) AS [Sin Espacios Izquierda],
 CONCAT(Nombre, ' - ', Edad) AS [Nombre Edad], 
 UPPER(REPLACE(TRIM(Ciudad), 'Chapulhucan', 'Chapu')) AS [Ciudad Normal]
 FROM clientes;

 SELECT * FROM clientes;

 -- Funciones de Fecha
 use NORTHWND;
 GO
 Select 
 OrderDate, 
 GETDATE() AS [Fecha Actual],
 DATEADD (Day, 10, OrderDate) AS [FechaMas10Dias], 
 DATEPART(quarter, OrderDate) AS [tRIMESTRE], 
 DATEPART(MONTH, orderDate) AS [MESCONNUMERO],
 DATENAME(month, OrderDate) AS [MESCONNOMBRE], 
 DATENAME(WEEKDAY, OrderDate) AS [NOMBREDIA], 
 DATEDIFF(DAY, OrderDate, GETDATE()) AS [DiasTranscurrido], 
 DATEDIFF(YEAR, OrderDate, GETDATE()) AS [AÑOSTRANSCURRIDOS], 
 DATEDIFF(Year, '2003-07-13', GETDATE()) AS [EdadJaen],
 DATEDIFF(Year, '1983-07-13', GETDATE()) AS [EdadJaen]
 from Orders;

 
 -- Manejo de Valores Nulos
 CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY,
    FirstName NVARCHAR(50),
    LastName NVARCHAR(50),
    Email NVARCHAR(100),
    SecondaryEmail NVARCHAR(100),
    Phone NVARCHAR(20),
    Salary DECIMAL(10,2),
    Bonus DECIMAL(10,2)
);

INSERT INTO Employees (EmployeeID, FirstName, LastName, Email, SecondaryEmail,
                       phone, Salary, Bonus)
VALUES(1, 'Ana', 'Lopez', 'ana.lopez@empresa.com',NULL,'555-2345', 12000, 100),
      (2, 'Carlos', 'Ramirez', NULL, 'c.ramirez@empresa.com', NULL, 9500, NULL),
      (3, 'Laura', 'Gomez', NULL, NULL, '555-8900', 0, 500),
      (4, 'Jorge', 'Diaz', 'jorge.diaz@empresa.com', NULL, NULL, 15000, 0);

-- Ejercicio1 - ISNULL
-- Mostrar el nombre completo del empleado junto con su número de telefono, 
-- Sino tiene telefono, mostrar el texto "No disponible"

SELECT CONCAT(FirstName, ' ', LastName) AS [FULLNAME],
       ISNULL(phone, 'No Disponible') AS [PHONE] 
FROM Employees;

-- Ejercicio 2. Mostrar el nombre del empleado y su correo de contactato
SELECT CONCAT(FirstName, ' ', LastName) AS [Nombre Completo],
email, 
secondaryEmail,
COALESCE(email, secondaryEmail, 'Sin Correo') AS Correo_Contacto
from Employees;

-- Ejercicio 3. NULLIF
-- Mostrar el nombre del empleado, su salario y el resultado de 
-- NULLIF(salary, 0) para detectar quien tiene salario cero

SELECT 
       CONCAT(FirstName, ' ', LastName) AS [NombreCompleto],
       Salary, 
	   NULLIF(salary, 0) AS [SalarioEvaluable]
FROM Employees;

-- Evita error de division por cero:

SELECT FirstName, 
       Bonus, 
       (Bonus/NULLIF(salary, 0)) AS Bonus_Salario
FROM Employees;


-- Expresiones condicionales Case

-- Permite crear condiciones dentro de una consulta

-- Sintaxis

SELECT
     UPPER(CONCAT(FirstName, ' ', LastName)) AS [FULLNAME],
	 ROUND(salary,2) AS [SALARIO], 
	 CASE 
		WHEN ROUND(salary,2) >= 10000 THEN 'Alto'
		WHEN ROUND(salary,2) BETWEEN 5000 AND 9999 THEN 'Medio'
		ELSE 'Bajo'
     END AS [Nivel Salarial]
FROM Employees;


-- Combinar Funciones y CASE

-- Seleccioanr el nombre del producto, fecha de la orden, telefono
-- Nombre del Cliente el mayusculas, validar si el telefono
-- es null, poner la palabra, no disponible,
-- comprobar la fecha de la orden restando los dias de la fecha de orden
-- con respecto a la fecha de hoy, si estos dias son menores a 30 entonces,
-- mostrar la Palabra reciente y sino Antiguo, el campo debe llamarse Estado de
-- pedido, utiliza la bd northwind

use NORTHWND

SELECT UPPER(c.CompanyName) AS [Nombre Cliente], 
ISNULL(c.Phone, 'No Disponible') AS [Telefono],
p.ProductName,
CASE 
	WHEN DATEDIFF(day, o.OrderDate, GETDATE()) <  30 THEN 'Reciente'
	ELSE 'Antiguo'
END AS [Estado del Pedido]
FROM ( Select customerId, companyName, Phone From Customers) AS c
INNER JOIN ( SELECT OrderID, CustomerID ,OrderDate FROM Orders) AS o
ON c.CustomerID = o.CustomerID
INNER JOIN ( SELECT ProductID, OrderID FROM [Order Details] ) AS od
ON o.OrderID = od.OrderID
INNER JOIN ( SELECT ProductID, ProductName FROM Products) AS p
ON p.ProductID = od.ProductID;


-- Create tabla a partir de esta consulta

SELECT UPPER(c.CompanyName) AS [Nombre Cliente], 
ISNULL(c.Phone, 'No Disponible') AS [Telefono],
p.ProductName,
CASE 
	WHEN DATEDIFF(day, o.OrderDate, GETDATE()) <  30 THEN 'Reciente'
	ELSE 'Antiguo'
END AS [Estado del Pedido]
INTO tablaformateada
FROM ( Select customerId, companyName, Phone From Customers) AS c
INNER JOIN ( SELECT OrderID, CustomerID ,OrderDate FROM Orders) AS o
ON c.CustomerID = o.CustomerID
INNER JOIN ( SELECT ProductID, OrderID FROM [Order Details] ) AS od
ON o.OrderID = od.OrderID
INNER JOIN ( SELECT ProductID, ProductName FROM Products) AS p
ON p.ProductID = od.ProductID;


-- Crear una vista
CREATE OR ALTER VIEW v_pedidosAntiguos
AS

SELECT [Nombre Cliente], ProductName, [Estado del Pedido] 
FROM tablaformateada
WHERE [Estado del Pedido] = 'Antiguo';


SELECT * FROM v_pedidosAntiguos;

-- Seleccionar el nombre completo del empleado, seleccionar el correo disponible
-- utilizando un coalesce, comprobar si el telefono esta null, si es asi
-- poner la palabra no disponible, validar el bonus si es null obligarlo
-- a ser cero y si es cero poner la palabra sin bono, y sino es cero
-- concatenar el bonus anteponiendo el simbolo $