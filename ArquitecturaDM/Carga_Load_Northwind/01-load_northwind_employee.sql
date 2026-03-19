use Load_Northwind
go

select * from Employees
-- CREAR LA TABLA EMPLOYEES
CREATE TABLE [dbo].[Employees](
	[EmployeeID] [int] NOT NULL,
	[LastName] [nvarchar](20) NOT NULL,
	[FirstName] [nvarchar](10) NOT NULL,
	[Title] [nvarchar](30) NULL,
	[TitleOfCourtesy] [nvarchar](25) NULL,
	[BirthDate] [datetime] NULL,
	[HireDate] [datetime] NULL,
	[Address] [nvarchar](60) NULL,
	[City] [nvarchar](15) NULL,
	[Region] [nvarchar](15) NULL,
	[PostalCode] [nvarchar](10) NULL,
	[Country] [nvarchar](15) NULL,
	[HomePhone] [nvarchar](24) NULL,
	[Extension] [nvarchar](4) NULL,
	[Photo] [image] NULL,
	[Notes] [ntext] NULL,
	[ReportsTo] [int] NULL,
	[PhotoPath] [nvarchar](255) NULL,
	[ETLLoad] datetime, 
	[ETLExecution] int);

GO

TRUNCATE TABLE EMPLOYEES

-- Consultar la Tabla Employees
SELECT *
FROM Employees;

-- Consultar La tabla ETLExecution
SELECT *
FROM [Northwind_Metadata].dbo.ETLExecution;

-- INSERTAR REGISTROS EN LA TABLA ETLEXECUTION

INSERT INTO ETLExecution (UserName, MachineName, PackageName, ETLLoad)
VALUES (?,?,?,GETDATE());

-- Seleccionar el ultimo ID
SELECT TOP 1 ID FROM ETLExecution
WHERE PackageName = ?
Order by ID Desc

use NORTHWND

SELECT 
ProductID
FROM Products
ORDER BY ProductID DESC;


SElect * from Northwind_Metadata.dbo.ETLExecution
select * from Load_Northwind.dbo.Employees

SELECT TOP 1 ID FROM ETLExecution
WHERE PackageName = 'LoadEmployee'
Order by ID Desc