
/* ======================================================
DataMart de Ventas (Northwind) - DDL Inicio de Base de Datos
Databases: Datamart_Northwind, Northwind_Metadata, 
          Stage_Northwind, Load_Northwind
Autor: José Luis Herrera Gallardo
=========================================================*/
USE master;
GO

-- 1) Crear Bases de Datos

IF DB_ID('Northwind_Metadata') IS NULL
    BEGIN
        CREATE DATABASE Northwind_Metadata;
    END
GO

IF DB_ID('Load_Northwind') IS NULL
    BEGIN
        CREATE DATABASE Load_Northwind;
    END
GO

IF DB_ID('Stage_Northwind') IS NULL
    BEGIN
        CREATE DATABASE Stage_Northwind;
    END
GO

IF DB_ID('Datamart_Northwind') IS NULL
    BEGIN
        CREATE DATABASE Datamart_Northwind;
    END
GO



