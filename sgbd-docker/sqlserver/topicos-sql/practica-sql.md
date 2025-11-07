## Ejercicio completo donde podrás insertar datos en una tabla principal (encabezado) y en una tabla detalle utilizando un Stored Procedure (SP) en SQL Server.

-- Tabla principal
CREATE TABLE Ventas (
    IdVenta INT IDENTITY(1,1) PRIMARY KEY,
    FechaVenta DATETIME NOT NULL DEFAULT GETDATE(),
    Cliente NVARCHAR(100) NOT NULL,
    Total DECIMAL(10,2) NULL
);

-- Tabla detalle
CREATE TABLE DetalleVenta (
    IdDetalle INT IDENTITY(1,1) PRIMARY KEY,
    IdVenta INT NOT NULL,
    Producto NVARCHAR(100) NOT NULL,
    Cantidad INT NOT NULL,
    Precio DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (IdVenta) REFERENCES Ventas(IdVenta)
);


2️⃣ Crear el tipo de tabla (TABLE TYPE)

Este tipo de tabla servirá como estructura para enviar los detalles al procedimiento.

CREATE TYPE TipoDetalleVenta AS TABLE (
    Producto NVARCHAR(100),
    Cantidad INT,
    Precio DECIMAL(10,2)
);

3️⃣ Crear el procedimiento almacenado
El SP insertará el encabezado y luego todos los detalles utilizando el tipo de tabla.

CREATE PROCEDURE InsertarVentaConDetalle
    @Cliente NVARCHAR(100),
    @Detalles TipoDetalleVenta READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IdVenta INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Insertar en la tabla principal
        INSERT INTO Ventas (Cliente)
        VALUES (@Cliente);

        -- Obtener el ID recién generado
        SET @IdVenta = SCOPE_IDENTITY();

        -- Insertar los detalles
        INSERT INTO DetalleVenta (IdVenta, Producto, Cantidad, Precio)
        SELECT @IdVenta, Producto, Cantidad, Precio
        FROM @Detalles;

        -- Calcular el total de la venta
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


4️⃣ Ejecutar el SP con datos de prueba

Primero declaramos una variable del tipo TipoDetalleVenta y luego la llenamos con los productos.

-- Declarar variable tipo tabla
DECLARE @MisDetalles AS TipoDetalleVenta;

-- Insertar productos en el tipo tabla
INSERT INTO @MisDetalles (Producto, Cantidad, Precio)
VALUES 
('Laptop', 1, 15000),
('Mouse', 2, 300),
('Teclado', 1, 500);

-- Ejecutar el procedimiento
EXEC InsertarVentaConDetalle 
    @Cliente = 'Carlos Ramírez',
    @Detalles = @MisDetalles;


Funciones integradas (Built-in Functions)

Concepto

Las funciones integradas permiten realizar cálculos o transformaciones sobre los datos dentro de una consulta SQL.

🔤 Funciones de texto

SELECT 
    Nombre,
    UPPER(Nombre) AS Mayusculas,
    LOWER(Nombre) AS Minusculas,
    LEN(Nombre) AS Longitud,
    SUBSTRING(Nombre, 1, 3) AS Prefijo
FROM Clientes;

| Función                               | Descripción                                      | Ejemplo                                            |
| ------------------------------------- | ------------------------------------------------ | -------------------------------------------------- |
| `LEN(cadena)`                         | Longitud del texto (sin contar espacios finales) | `LEN('SQL Server ') → 10`                          |
| `LTRIM(cadena)`                       | Elimina espacios a la izquierda                  | `'  Hola' → 'Hola'`                                |
| `RTRIM(cadena)`                       | Elimina espacios a la derecha                    | `'Hola  ' → 'Hola'`                                |
| `LOWER(cadena)`                       | Convierte a minúsculas                           | `'HOLA' → 'hola'`                                  |
| `UPPER(cadena)`                       | Convierte a mayúsculas                           | `'hola' → 'HOLA'`                                  |
| `SUBSTRING(cadena, inicio, longitud)` | Extrae una parte del texto                       | `SUBSTRING('SQLServer', 4, 6) → 'Server'`          |
| `LEFT(cadena, n)`                     | Devuelve los primeros *n* caracteres             | `LEFT('SQLServer', 3) → 'SQL'`                     |
| `RIGHT(cadena, n)`                    | Devuelve los últimos *n* caracteres              | `RIGHT('SQLServer', 6) → 'Server'`                 |
| `CHARINDEX(subcadena, cadena)`        | Devuelve la posición de una subcadena            | `CHARINDEX('S', 'SQL Server') → 1`                 |
| `REPLACE(cadena, buscar, reemplazo)`  | Reemplaza texto                                  | `REPLACE('SQL 2022', '2022', '2025') → 'SQL 2025'` |
| `REVERSE(cadena)`                     | Invierte el texto                                | `REVERSE('SQL') → 'LQS'`                           |
| `CONCAT(val1, val2, ...)`             | Une varios valores en una sola cadena            | `CONCAT('Cliente ', Nombre)`                       |
| `CONCAT_WS(sep, val1, val2, ...)`     | Une valores con un separador                     | `CONCAT_WS('-', 'MX', '001') → 'MX-001'`           |

SELECT 
    Nombre,
    CONCAT(Nombre, ' (', Ciudad, ')') AS ClienteCompleto,
    LEFT(Nombre, 3) AS Iniciales,
    LEN(Nombre) AS Longitud,
    REPLACE(Ciudad, 'México', 'CDMX') AS CiudadNormalizada
FROM Clientes;


🔢 Funciones numéricas

SELECT 
    Monto,
    ROUND(Monto, 1) AS Redondeo1Decimal,
    CEILING(Monto) AS HaciaArriba,
    FLOOR(Monto) AS HaciaAbajo
FROM Pedidos;

| Función     | Descripción                       |
| ----------- | --------------------------------- |
| `ROUND()`   | Redondea a un número de decimales |
| `CEILING()` | Redondea hacia arriba             |
| `FLOOR()`   | Redondea hacia abajo              |


📅 Funciones de fecha

SELECT 
    FechaPedido,
    GETDATE() AS FechaActual,
    DATEDIFF(DAY, FechaPedido, GETDATE()) AS DiasTranscurridos,
    DATEADD(DAY, 10, FechaPedido) AS FechaMas10Dias
FROM Pedidos;

| Función                               | Descripción                        |
| ------------------------------------- | ---------------------------------- |
| `GETDATE()`                           | Devuelve la fecha y hora actual    |
| `DATEADD(intervalo, cantidad, fecha)` | Suma o resta unidades de tiempo    |
| `DATEDIFF(intervalo, fecha1, fecha2)` | Calcula la diferencia entre fechas |



Funciones de agregación y agrupamiento

Concepto

Las funciones de agregación operan sobre conjuntos de datos para devolver un único resultado.

| Función   | Descripción      |
| --------- | ---------------- |
| `COUNT()` | Cuenta registros |
| `SUM()`   | Suma valores     |
| `AVG()`   | Promedio         |
| `MIN()`   | Valor mínimo     |
| `MAX()`   | Valor máximo     |

SELECT 
    IdCliente,
    COUNT(IdPedido) AS TotalPedidos,
    SUM(Monto) AS TotalGastado,
    AVG(Monto) AS Promedio,
    MAX(Monto) AS PedidoMayor
FROM Pedidos
GROUP BY IdCliente;

Filtrar grupos con HAVING

HAVING se usa junto con GROUP BY para filtrar resultados agregados (a diferencia de WHERE que filtra registros individuales).

SELECT IdCliente, SUM(Monto) AS TotalGastado
FROM Pedidos
GROUP BY IdCliente
HAVING SUM(Monto) > 5000;


Uniones entre tablas (JOINS)

Concepto

Un JOIN permite combinar datos de dos o más tablas relacionadas por una clave común.

🔗 INNER JOIN (Solo registros coincidentes)

SELECT C.Nombre, P.IdPedido, P.Monto
FROM Clientes AS C
INNER JOIN Pedidos AS P
ON C.IdCliente = P.IdCliente;

LEFT JOIN (Todos los de la izquierda, aunque no haya coincidencia)

SELECT C.Nombre, P.IdPedido, P.Monto
FROM Clientes AS C
LEFT JOIN Pedidos AS P
ON C.IdCliente = P.IdCliente;

🔗 RIGHT JOIN (Todos los de la derecha)

SELECT C.Nombre, P.IdPedido, P.Monto
FROM Clientes AS C
RIGHT JOIN Pedidos AS P
ON C.IdCliente = P.IdCliente;

🔗 FULL JOIN (Todos los registros de ambas tablas)

SELECT C.Nombre, P.IdPedido, P.Monto
FROM Clientes AS C
FULL JOIN Pedidos AS P
ON C.IdCliente = P.IdCliente;



# 🧠 Práctica SQL Server: `UPDATE` y `DELETE` con `JOIN`

## 📘 Objetivo
Practicar cómo actualizar (`UPDATE`) y eliminar (`DELETE`) registros en **SQL Server** utilizando **JOINs**, para modificar datos relacionados entre varias tablas.

---

## 🧱 1️⃣ Creación de Tablas y Datos de Prueba

```sql
DROP TABLE IF EXISTS Empleados;
DROP TABLE IF EXISTS Departamentos;

CREATE TABLE Departamentos (
    id_depto INT PRIMARY KEY,
    nombre_depto NVARCHAR(50)
);

CREATE TABLE Empleados (
    id_empleado INT PRIMARY KEY,
    nombre NVARCHAR(50),
    salario DECIMAL(10,2),
    id_depto INT,
    fecha_ingreso DATE
);

INSERT INTO Departamentos VALUES
(1, 'Ventas'),
(2, 'TI'),
(3, 'Finanzas'),
(4, 'Recursos Humanos');

INSERT INTO Empleados VALUES
(101, 'Ana', 10000, 1, '2018-05-10'),
(102, 'Luis', 12000, 2, '2020-01-15'),
(103, 'Carla', 11000, 3, '2019-03-20'),
(104, 'Miguel', 9500, 1, '2021-06-05'),
(105, 'Sofía', 13000, 2, '2022-09-12'),
(106, 'Pedro', 12500, 3, '2017-11-30'),
(107, 'Laura', 9000, 4, '2023-02-01');

-- 🔍 Verificar los datos iniciales
SELECT e.id_empleado, e.nombre, e.salario, d.nombre_depto, e.fecha_ingreso
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
ORDER BY d.nombre_depto, e.nombre;


🧠 Ejercicio 1

Aumenta en 5% el salario de los empleados del departamento de Ventas.

UPDATE e
SET e.salario = e.salario * 1.05
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Ventas';

-- ✅ Verificar resultado
SELECT e.nombre, e.salario, d.nombre_depto
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Ventas';


Ejercicio 2

Establece el salario mínimo de los empleados del departamento de Finanzas en $11,500.

UPDATE e
SET e.salario = 11500
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Finanzas' AND e.salario < 11500;

-- ✅ Verificar resultado
SELECT e.nombre, e.salario, d.nombre_depto
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Finanzas';

🧠 Ejercicio 3

Aumenta en 10% el salario de los empleados que ingresaron antes de 2020 y pertenecen a TI.

UPDATE e
SET e.salario = e.salario * 1.10
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'TI' AND e.fecha_ingreso < '2020-01-01';

-- ✅ Verificar resultado
SELECT e.nombre, e.salario, d.nombre_depto, e.fecha_ingreso
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'TI';

🧨 3️⃣ Ejercicios de DELETE con JOIN

🧠 Ejercicio 4

Elimina los empleados que pertenecen al departamento de Recursos Humanos.

DELETE e
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Recursos Humanos';

-- ✅ Verificar resultado
SELECT * FROM Empleados WHERE id_depto = 4;

🧠 Ejercicio 5

Elimina los empleados del departamento de Finanzas cuyo salario sea menor a 12,000.

DELETE e
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Finanzas' AND e.salario < 12000;

-- ✅ Verificar resultado
SELECT e.nombre, e.salario, d.nombre_depto
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Finanzas';

🧠 Ejercicio 6 (Nivel Avanzado)

Elimina a los empleados de Ventas que ingresaron después del 1 de enero de 2020.

DELETE e
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Ventas' AND e.fecha_ingreso > '2020-01-01';

-- ✅ Verificar resultado
SELECT e.nombre, e.salario, d.nombre_depto, e.fecha_ingreso
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
WHERE d.nombre_depto = 'Ventas';


✅ 4️⃣ Consulta Final (Ver Todos los Datos Restantes)

SELECT e.id_empleado, e.nombre, e.salario, d.nombre_depto, e.fecha_ingreso
FROM Empleados e
JOIN Departamentos d ON e.id_depto = d.id_depto
ORDER BY d.nombre_depto, e.nombre;


🧾 Conclusiones

UPDATE con JOIN permite modificar registros basándose en relaciones entre tablas.

DELETE con JOIN elimina registros dependientes de condiciones en otra tabla.

Siempre valida con un SELECT antes de ejecutar cambios definitivos.

Usa transacciones (BEGIN TRAN, ROLLBACK, COMMIT) si estás trabajando con datos reales.