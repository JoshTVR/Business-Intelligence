# Documentación Técnica Completa — Proyecto BI Northwind

Este documento explica **cada archivo, cada línea de código, cada concepto y cada decisión de diseño** del proyecto. Está pensado para poder releer el proyecto desde cero y entender todo sin necesidad de consultar otra fuente.

---

## Tabla de Contenidos

1. [Conceptos Fundamentales](#1-conceptos-fundamentales)
2. [Arquitectura del Proyecto](#2-arquitectura-del-proyecto)
3. [La Fuente de Datos: NORTHWND](#3-la-fuente-de-datos-northwnd)
4. [Script: init_database.sql](#4-script-init_databasesql)
5. [Script: Script_Northwind_Metadata.sql](#5-script-script_northwind_metadatasql)
6. [Script: init_datamart_northwind.sql](#6-script-init_datamart_northwindsql)
7. [Script: 01-load_northwind_employee.sql](#7-script-01-load_northwind_employeesql)
8. [Script: scriptfactventas.sql](#8-script-scriptfactventassql)
9. [Paquetes SSIS](#9-paquetes-ssis)
10. [Power BI](#10-power-bi)
11. [Configuración Docker](#11-configuración-docker)
12. [Tópicos SQL — script_topicos_sql.sql](#12-tópicos-sql--script_topicos_sqlsql)

---

## 1. Conceptos Fundamentales

Antes de entrar al código, es necesario entender los conceptos que guían todo el proyecto.

### 1.1 ¿Qué es Business Intelligence (BI)?

Business Intelligence es el conjunto de procesos, tecnologías y herramientas que transforman datos crudos en información útil para tomar decisiones de negocio. El flujo típico es:

```
Datos crudos  →  Limpieza y transformación  →  Almacenamiento analítico  →  Visualización  →  Decisión
```

En este proyecto:
- **Datos crudos** = base de datos Northwind (sistema transaccional)
- **Limpieza y transformación** = capas Load y Stage con SSIS
- **Almacenamiento analítico** = Datamart_Northwind (modelo estrella)
- **Visualización** = Power BI

### 1.2 ¿Qué es la Metodología Kimball?

Ralph Kimball es el autor del enfoque más usado en BI. Su metodología propone construir **datamarts** (almacenes de datos temáticos) usando un **modelo dimensional** en forma de estrella o copo de nieve.

Los principios clave de Kimball aplicados en este proyecto:

**a) Modelado Dimensional en Estrella**
El modelo estrella tiene dos tipos de tablas:
- **Tabla de hechos (Fact Table)**: contiene los eventos del negocio que se quieren medir (ventas, en este caso). Tiene métricas numéricas (cantidades, montos) y claves foráneas hacia las dimensiones.
- **Tablas de dimensión (Dimension Tables)**: describen el contexto de los hechos (quién compró, qué producto, cuándo, quién vendió). Contienen atributos descriptivos.

**b) Claves surrogadas (Surrogate Keys)**
En el datamart no se usan las claves originales de la fuente (llamadas *claves naturales* o *natural keys*). En su lugar, se crean claves propias (enteros autoincrementales). Esto permite:
- Independencia de los sistemas fuente
- Manejo del historial (SCD)
- Rendimiento en joins

En el código se identifican con el sufijo `_nk` para la clave natural y `_key` para la surrogada. Por ejemplo en `dim_customer`:
```sql
customer_key   INT IDENTITY(1,1) PRIMARY KEY  -- clave surrogada (generada por el datamart)
customerid_nk  NVARCHAR(10) NOT NULL           -- clave natural (viene de NORTHWND)
```

**c) Dimensión de Fecha**
Kimball considera obligatorio tener una dimensión de fecha (`dim_date`) con atributos precalculados (día, mes, trimestre, año, nombre del mes, etc.). Esto hace que las consultas de Power BI sean mucho más rápidas y flexibles que hacer `DATEPART()` en tiempo de consulta.

**d) Grano de la Fact Table**
El "grano" define qué representa exactamente una fila en la tabla de hechos. En este proyecto el grano es: **una línea de pedido** (una fila = un producto dentro de un pedido). Esto es importante porque un pedido puede tener múltiples productos, y cada combinación pedido-producto es una fila separada en `fact_sales`.

### 1.3 ¿Qué es un SCD (Slowly Changing Dimension)?

Las dimensiones "cambian lentamente" — los datos de un cliente, por ejemplo, pueden cambiar (cambia de dirección, de nombre de empresa, etc.). El SCD define cómo se maneja ese cambio.

**SCD Tipo 1 — Sobreescribir**
El valor viejo se reemplaza con el nuevo. No hay historial. Se usa cuando el cambio no es relevante para el análisis histórico.

Ejemplo: si el cargo (`title`) de un empleado cambia de "Sales Representative" a "Sales Manager", simplemente se actualiza el registro. Las ventas pasadas quedarán asociadas al nuevo cargo, lo cual es aceptable si no nos importa analizar "cuánto vendió cuando era Representative".

Se aplica en: `dim_employee`, `dim_product`, `dim_shipper`.

**SCD Tipo 2 — Guardar historial**
Cuando el dato cambia, NO se modifica el registro existente. En su lugar:
1. El registro viejo se "cierra": se pone `end_date = hoy` e `is_current = 0`
2. Se inserta un registro nuevo con los datos actualizados, `start_date = hoy`, `end_date = NULL`, `is_current = 1`

Esto permite responder preguntas como: "¿qué dirección tenía el cliente cuando hizo este pedido?" El join en `fact_sales` busca la versión del cliente vigente en la fecha de la venta, no la versión actual.

Se aplica en: `dim_customer`, `dim_supplier`.

Visualización del SCD2 con un ejemplo:

```
| customer_key | customerid_nk | company_name    | city      | start_date | end_date   | is_current |
|--------------|---------------|-----------------|-----------|------------|------------|------------|
| 1            | ALFKI         | Alfreds Futter  | Berlin    | 1996-07-04 | 2023-01-15 | 0          |  ← versión vieja (cerrada)
| 92           | ALFKI         | Alfreds Futter  | Munich    | 2023-01-15 | NULL       | 1          |  ← versión actual
```

Cuando el cliente hizo pedidos entre 1996 y 2023, el `fact_sales` apunta al `customer_key = 1` (ciudad Berlin). Pedidos desde 2023 apuntan al `customer_key = 92` (ciudad Munich). El análisis histórico es correcto.

### 1.4 ¿Qué es ETL?

ETL = **E**xtract, **T**ransform, **L**oad

- **Extract (Extraer)**: leer los datos desde la fuente (NORTHWND en este caso)
- **Transform (Transformar)**: limpiar, unificar formatos, manejar nulos, calcular campos derivados
- **Load (Cargar)**: insertar los datos transformados en el destino (Datamart)

En este proyecto el ETL está implementado en **SSIS (SQL Server Integration Services)**, que es la herramienta de Microsoft para construir pipelines de datos visualmente.

### 1.5 ¿Qué es la Metadata del ETL?

La metadata del ETL es el registro de auditoría de cada ejecución. Saber cuándo se ejecutó un paquete, cuántos registros procesó, si hubo errores — esto es esencial en producción para diagnosticar problemas y tener trazabilidad.

En este proyecto, cada vez que un paquete SSIS corre:
1. Inserta una fila en `Northwind_Metadata.dbo.ETLExecution` y obtiene el ID generado
2. Ese ID se almacena en la columna `ETLExecution` de cada fila que carga en `Load_Northwind`
3. Así siempre se puede saber qué paquete cargó qué dato y cuándo

### 1.6 ¿Qué es SSIS?

SQL Server Integration Services es la herramienta de ETL de Microsoft, incluida en SQL Server. Permite crear "paquetes" (.dtsx) que son flujos de trabajo visuales para mover y transformar datos.

Un paquete SSIS típico en este proyecto hace lo siguiente:
1. Ejecuta una query SQL para registrar la ejecución en la metadata
2. Lee datos de la fuente (NORTHWND o Load_Northwind)
3. Aplica transformaciones (limpieza de nulos, cálculos)
4. Carga los datos en el destino (Load_Northwind, Stage_Northwind o Datamart_Northwind)

Los parámetros en las queries SSIS se escriben con `?` (signo de interrogación). SSIS sustituye esos `?` por valores en tiempo de ejecución.

---

## 2. Arquitectura del Proyecto

### 2.1 Las 5 Bases de Datos

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SQL SERVER                                   │
│                                                                      │
│  ┌──────────┐    ┌────────────────┐    ┌─────────────────┐          │
│  │  NORTHWND │    │ Load_Northwind │    │ Stage_Northwind │          │
│  │ (fuente) │───►│ (aterrizaje)   │───►│ (transformación)│          │
│  │          │    │                │    │                 │          │
│  └──────────┘    └────────────────┘    └─────────────────┘          │
│                           │                      │                  │
│                           ▼                      ▼                  │
│                  ┌─────────────────────────────────┐                │
│                  │      Datamart_Northwind          │                │
│                  │      (modelo estrella)           │───► Power BI  │
│                  └─────────────────────────────────┘                │
│                                                                      │
│  ┌──────────────────────┐                                           │
│  │  Northwind_Metadata  │ ◄─── todos los paquetes SSIS escriben aquí│
│  │  (auditoría ETL)     │                                           │
│  └──────────────────────┘                                           │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 ¿Por qué no ir directo de NORTHWND al Datamart?

Es una pregunta válida. La respuesta es resiliencia y trazabilidad:

**Sin capas intermedias:**
- Si NORTHWND cambia de estructura, el ETL se rompe directamente
- Si hay un error de transformación, no hay forma de "volver atrás" a los datos originales
- No hay forma de saber qué datos se procesaron en cada ejecución

**Con la capa Load:**
- Siempre hay una copia cruda de lo que llegó de la fuente
- Se puede re-procesar desde Load sin volver a tocar NORTHWND
- Cada fila sabe exactamente en qué ejecución ETL fue cargada (columna `ETLExecution`)

**Con la capa Stage:**
- La transformación está separada de la carga
- Se pueden hacer múltiples transformaciones sin afectar la fuente ni el datamart

### 2.3 Orden de Ejecución

El orden correcto para configurar el entorno desde cero:

```
1. init_database.sql                              → crea las 4 BDs
2. Script_Northwind_Metadata.sql                  → crea la tabla ETLExecution
3. init_datamart_northwind.sql                    → crea el modelo dimensional
4. scriptfactventas.sql (solo secciones DDL)      → crea tablas en Load y Stage
5. Paquetes SSIS (CargaMaster.dtsx)               → ejecuta el ETL completo
```

---

## 3. La Fuente de Datos: NORTHWND

Northwind es una base de datos de ejemplo creada por Microsoft para SQL Server. Representa una empresa ficticia que vende alimentos y bebidas. Las tablas relevantes para este proyecto son:

| Tabla | Descripción |
|---|---|
| `Customers` | Clientes de la empresa. PK: `CustomerID` (char 5, ej. 'ALFKI') |
| `Employees` | Empleados que procesan pedidos. PK: `EmployeeID` (int) |
| `Products` | Productos vendidos. PK: `ProductID` (int) |
| `Categories` | Categorías de productos. PK: `CategoryID` (int) |
| `Suppliers` | Proveedores de productos. PK: `SupplierID` (int) |
| `Shippers` | Empresas transportistas. PK: `ShipperID` (int) |
| `Orders` | Encabezados de pedidos. PK: `OrderID` (int). FK a Customers, Employees, Shippers |
| `[Order Details]` | Líneas de pedido. PK compuesta: `OrderID + ProductID`. Tiene precio, cantidad y descuento |

La relación más importante para entender el grano del datamart:

```
Orders (1) ──────── (N) [Order Details] (N) ──────── (1) Products
   │                                                         │
   ├── CustomerID ──── (1) Customers                         └── CategoryID, SupplierID
   ├── EmployeeID ──── (1) Employees
   └── ShipVia ─────── (1) Shippers
```

Un pedido (`Orders`) tiene múltiples líneas (`Order Details`). Cada línea tiene un producto, una cantidad y un precio/descuento. **Esa línea es el grano del datamart** — una fila en `fact_sales` = una fila en `[Order Details]`.

---

## 4. Script: init_database.sql

**Ubicación:** [ArquitecturaDM/init_database.sql](ArquitecturaDM/init_database.sql)

**Propósito:** Crear las 4 bases de datos del proyecto si aún no existen. Es el primer script que se ejecuta al configurar el entorno.

### Código completo con explicación línea a línea

```sql
/* ======================================================
DataMart de Ventas (Northwind) - DDL Inicio de Base de Datos
Databases: Datamart_Northwind, Northwind_Metadata,
          Stage_Northwind, Load_Northwind
Autor: José Luis Herrera Gallardo
=========================================================*/
USE master;
GO
```

`USE master` — se conecta a la base de datos maestra del servidor. Las operaciones de creación de bases de datos deben hacerse desde `master`. No se puede crear una base de datos estando conectado a otra.

`GO` — no es una instrucción SQL. Es un separador de lotes que usa SQL Server Management Studio (SSMS). Indica que todo lo anterior debe enviarse al servidor como un bloque antes de continuar. Es necesario porque algunas instrucciones como `USE` deben ejecutarse solas antes de que las siguientes instrucciones puedan usarlas.

```sql
IF DB_ID('Northwind_Metadata') IS NULL
    BEGIN
        CREATE DATABASE Northwind_Metadata;
    END
GO
```

`DB_ID('Northwind_Metadata')` — función del sistema que devuelve el ID numérico de una base de datos si existe, o `NULL` si no existe. Es la forma correcta de comprobar si una BD ya existe antes de crearla. Sin esta guarda, si se ejecuta el script dos veces daría error porque no puedes crear una BD que ya existe.

Este mismo patrón se repite para las 4 bases de datos:

```sql
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
```

**¿Por qué no usa `IF NOT EXISTS` como en otros dialectos SQL?**
En T-SQL (el dialecto de SQL Server), la forma estándar de comprobar existencia de bases de datos es con `DB_ID()`. La sintaxis `IF NOT EXISTS (SELECT ...)` también funciona pero es más verbosa. `DB_ID()` es más concisa y es la convención preferida en SQL Server para este caso.

**¿Por qué no hay configuraciones de archivo, filegroups, collation, etc.?**
El script usa `CREATE DATABASE <nombre>` sin parámetros adicionales, lo que crea la BD con los valores por defecto del servidor (collation, tamaño inicial de archivos, ruta de datos). Para un proyecto de aprendizaje esto es suficiente. En producción se especificarían paths, tamaños de archivos y collation explícitamente.

---

## 5. Script: Script_Northwind_Metadata.sql

**Ubicación:** [ArquitecturaDM/Preparativo_datamart/Script_Northwind_Metadata.sql](ArquitecturaDM/Preparativo_datamart/Script_Northwind_Metadata.sql)

**Propósito:** Crear la tabla `ETLExecution` en la base de datos de metadata. Esta tabla es el registro de auditoría de todas las ejecuciones de paquetes SSIS.

### Código completo con explicación

```sql
USE master
GO
```

Se conecta a `master` porque va a crear o eliminar una base de datos.

```sql
IF EXISTS (SELECT name FROM SYS.databases WHERE NAME='NORTHWIND_METADATA2')
BEGIN
    DROP DATABASE NORTHWIND_METADATA
END
GO
```

> **BUG HEREDADO DE CLASE:** Esta condición comprueba si existe `NORTHWIND_METADATA2` pero en caso afirmativo elimina `NORTHWIND_METADATA` (sin el 2). Son nombres diferentes. Como `NORTHWIND_METADATA2` nunca existió, esta condición nunca se cumple y el DROP nunca se ejecuta. Es un error tipográfico de la clase que quedó en el código.

`SYS.databases` — es una vista del sistema en SQL Server que lista todas las bases de datos existentes en el servidor. Equivalente a la función `DB_ID()` pero aquí se usa una consulta SELECT porque el código original lo hizo así.

```sql
CREATE DATABASE NORTHWIND_METADATA
GO
```

Crea la base de datos de metadata. A diferencia del `init_database.sql`, aquí NO hay guarda `IF NOT EXISTS`, por lo que si se ejecuta dos veces dará error. Esto es parte del desorden del script original de clase.

```sql
USE NORTHWIND_METADATA2
go
```

> **BUG HEREDADO DE CLASE:** Intenta conectarse a `NORTHWIND_METADATA2` pero la BD creada arriba se llama `NORTHWIND_METADATA`. Esto haría fallar todo lo que viene después. En la práctica, durante las clases se corregía este nombre manualmente antes de ejecutar.

```sql
CREATE TABLE ETLExecution(
   Id INT IDENTITY(1,1) NOT NULL,
   UserName NVARCHAR(50),
   MachineName NVARCHAR(50),
   PackageName NVARCHAR(50),
   ETLLoad DATETIME,
   ETLCountRows BIGINT,
   ETLCountNewRegister BIGINT,
   ETLCountModifiedRegister BIGINT
);
GO
```

Esta es la tabla más importante del script. Explicación columna por columna:

| Columna | Tipo | Por qué |
|---|---|---|
| `Id` | `INT IDENTITY(1,1) NOT NULL` | Clave primaria autoincremental. Cada ejecución de paquete genera un ID único. SSIS recupera este ID para marcarlo en las filas que carga. |
| `UserName` | `NVARCHAR(50)` | Usuario de Windows que ejecutó el paquete SSIS. Permite saber quién lanzó cada carga. |
| `MachineName` | `NVARCHAR(50)` | Nombre del equipo desde donde se ejecutó. Útil en entornos donde múltiples personas pueden correr el ETL. |
| `PackageName` | `NVARCHAR(50)` | Nombre del paquete SSIS (ej. 'LoadEmployee', 'LoadCustomers'). Permite filtrar el historial por paquete. |
| `ETLLoad` | `DATETIME` | Fecha y hora de la ejecución. El paquete inserta `GETDATE()` aquí. |
| `ETLCountRows` | `BIGINT` | Total de filas procesadas (leídas de la fuente). |
| `ETLCountNewRegister` | `BIGINT` | Filas nuevas insertadas en el destino. |
| `ETLCountModifiedRegister` | `BIGINT` | Filas modificadas (updates). |

**¿Por qué `BIGINT` para los contadores y no `INT`?**
`INT` soporta hasta ~2.1 millones. `BIGINT` soporta hasta ~9.2 billones. Para una tabla pequeña como Northwind, `INT` sería suficiente, pero es buena práctica usar `BIGINT` para contadores de filas porque en producción con tablas grandes un `INT` puede desbordarse.

**¿Por qué `NVARCHAR` para los textos?**
`NVARCHAR` (National Variable Character) almacena Unicode, lo que soporta cualquier idioma y conjunto de caracteres. `VARCHAR` solo soporta ASCII extendido. En SQL Server es buena práctica usar `NVARCHAR` para cualquier texto que pueda contener nombres o texto en múltiples idiomas.

### ¿Cómo usa SSIS esta tabla?

El flujo dentro de cada paquete SSIS es:

**Paso 1** — Al inicio del paquete, se ejecuta este INSERT:
```sql
INSERT INTO ETLExecution (UserName, MachineName, PackageName, ETLLoad)
VALUES (?, ?, ?, GETDATE());
```
Los `?` son parámetros que SSIS llena con variables del sistema: el usuario de Windows, el nombre del equipo, y el nombre del paquete.

**Paso 2** — Inmediatamente después, se recupera el ID generado:
```sql
SELECT TOP 1 ID FROM ETLExecution
WHERE PackageName = ?
ORDER BY ID DESC
```
Este ID se guarda en una variable SSIS que se usará en el paso siguiente.

**Paso 3** — Cuando el paquete carga datos en `Load_Northwind`, cada fila recibe:
- `ETLLoad = GETDATE()` — la fecha/hora actual
- `ETLExecution = <el ID del paso 2>` — el ID de esta ejecución específica

Así, en cualquier momento se puede hacer esta consulta para ver qué datos cargó una ejecución específica:
```sql
SELECT * FROM Load_Northwind.dbo.Employees
WHERE ETLExecution = 42  -- el ID de esa ejecución
```

---

## 6. Script: init_datamart_northwind.sql

**Ubicación:** [ArquitecturaDM/DATAMART_NORTHWIND/init_datamart_northwind.sql](ArquitecturaDM/DATAMART_NORTHWIND/init_datamart_northwind.sql)

**Propósito:** Crear todas las tablas del modelo dimensional en `Datamart_Northwind`. Este es el script más importante del proyecto desde el punto de vista arquitectónico.

### Encabezado

```sql
USE Datamart_Northwind;
GO
```

Cambia el contexto a la BD del datamart. Todo lo que sigue se crea dentro de esta BD.

---

### 6.1 dim_customer (SCD Tipo 2)

```sql
IF OBJECT_ID('dim_customer') IS NULL
    BEGIN
        CREATE TABLE dim_customer (
            customer_key          INT IDENTITY(1,1) PRIMARY KEY,
            customerid_nk         NVARCHAR(10) NOT NULL,
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
```

**`OBJECT_ID('dim_customer') IS NULL`** — comprueba si la tabla ya existe antes de crearla. `OBJECT_ID()` devuelve el ID del objeto en la BD si existe, o `NULL` si no. Esto hace el script idempotente: se puede ejecutar muchas veces sin error.

**`customer_key INT IDENTITY(1,1) PRIMARY KEY`**
- `INT` — entero de 32 bits, suficiente para millones de registros
- `IDENTITY(1,1)` — valor autoincrementable: empieza en 1, incrementa de 1 en 1. SQL Server genera este valor automáticamente al hacer INSERT, no hay que especificarlo
- `PRIMARY KEY` — define esta columna como clave primaria, lo que crea automáticamente un índice único sobre ella

**`customerid_nk NVARCHAR(10) NOT NULL`**
- `_nk` = natural key. Es la clave que viene de NORTHWND (`CustomerID`, que es un char(5) como 'ALFKI')
- `NVARCHAR(10)` — se usa 10 en lugar del 5 original por holgura
- `NOT NULL` — siempre debe haber un valor; un cliente sin ID no tiene sentido

**`company_name NVARCHAR(40) NOT NULL`** — el nombre de la empresa es obligatorio; coincide exactamente con el tamaño del campo en NORTHWND.

**`contact_name NVARCHAR(30) NULL`** — el nombre de contacto puede ser nulo; en Northwind hay clientes sin contacto registrado.

**`[address] NVARCHAR(60) NULL`** — `address` va entre corchetes `[]` porque `ADDRESS` es una palabra reservada en T-SQL. Los corchetes "escapan" el nombre y lo tratan como identificador, no como palabra clave.

**`city NVARCHAR(15) NULL`** — ciudad; puede ser nula.

**`region NVARCHAR(15) NULL`** — región/estado; muchos clientes en Northwind no tienen región (especialmente los europeos), por eso es nullable. En la capa Stage se aplica `ISNULL(region, 'NO REGION')` para estandarizar.

**`start_date DATE NOT NULL`** — fecha desde la que es válida esta versión del registro. Para la carga inicial se pone `GETDATE()`. `DATE` (no `DATETIME`) es suficiente porque solo importa el día, no la hora.

**`end_date DATE NULL`** — fecha hasta la que fue válida. `NULL` significa que el registro está activo (es la versión actual). Cuando el cliente cambia, se pone aquí la fecha del cambio.

**`is_current BIT NOT NULL DEFAULT (1)`**
- `BIT` — tipo booleano de SQL Server (0 = falso, 1 = verdadero)
- `DEFAULT (1)` — al insertar un registro nuevo sin especificar este valor, SQL Server pone 1 automáticamente (el registro es "actual" por defecto)
- Junto con `end_date`, este campo permite filtrar fácilmente los registros vigentes: `WHERE is_current = 1`

---

### 6.2 dim_product (SCD Tipo 1)

```sql
IF OBJECT_ID ('dim_product') IS NULL
BEGIN
CREATE TABLE dim_product(
    product_key       INT IDENTITY(1,1) PRIMARY KEY,
    productid_nk      INT NOT NULL,
    product_name      NVARCHAR(40) NOT NULL,
    category_name     NVARCHAR(15) NOT NULL,
    supplier_name     NVARCHAR(40) NOT NULL,
    quantity_per_unit NVARCHAR(20) NOT NULL,
    discontinued      BIT NOT NULL
);
END
GO
```

**`productid_nk INT NOT NULL`** — la clave natural de productos en Northwind es un entero (`ProductID INT`), por eso aquí también es `INT`, a diferencia de `customerid_nk` que es `NVARCHAR`.

**`category_name NVARCHAR(15) NOT NULL`** — observar que en lugar de guardar el `CategoryID` (como está en Northwind), se desnormaliza el nombre de la categoría directamente. En el modelo dimensional esto es correcto y esperado: las dimensiones deben ser "planas" (sin relaciones entre sí), aun si eso implica repetir datos. La ventaja es que las consultas en Power BI son más simples y rápidas.

**`supplier_name NVARCHAR(40) NOT NULL`** — mismo caso: se trae el nombre del proveedor directamente en vez de guardar el ID. El join con `Suppliers` se hace una sola vez al cargar la dimensión, no en cada consulta analítica.

**`quantity_per_unit NVARCHAR(20) NOT NULL`** — descripción de la presentación del producto ("10 boxes x 20 bags", "24 - 12 oz bottles", etc.). Es un campo de texto libre en Northwind.

**`discontinued BIT NOT NULL`** — indica si el producto fue descontinuado. `BIT` = 0 (activo) o 1 (descontinuado).

**¿Por qué es SCD Tipo 1 y no Tipo 2?**
Para este proyecto se decidió que los cambios en los datos de productos (como cambio de nombre o categoría) no son relevantes para el análisis histórico. Si el nombre de un producto cambia, se sobreescribe y las ventas históricas del producto quedan asociadas al nombre nuevo. Esto es una decisión de diseño.

---

### 6.3 dim_employee (SCD Tipo 1)

```sql
IF OBJECT_ID ('dim_employee') IS NULL
BEGIN
CREATE TABLE dim_employee(
    employee_key  INT IDENTITY(1,1) PRIMARY KEY,
    employeeid_nk INT NOT NULL,
    full_name     NVARCHAR(61) NOT NULL,
    [title]       NVARCHAR(30) NULL,
    hire_date     DATE NULL
);
END
GO
```

**`full_name NVARCHAR(61) NOT NULL`** — en Northwind, el nombre se guarda en dos columnas: `FirstName NVARCHAR(10)` y `LastName NVARCHAR(20)`. En la dimensión se concatenan en un solo campo. El tamaño `61` viene de: 10 (FirstName) + 1 (espacio) + 20 (LastName) = 31... ¿por qué 61? Probablemente se usó el doble por holgura. No es un error, solo una estimación conservadora.

**`[title] NVARCHAR(30) NULL`** — título/cargo del empleado entre corchetes porque `TITLE` es una palabra reservada en T-SQL.

**`hire_date DATE NULL`** — fecha de contratación. Es nullable porque podría faltar en algún registro.

**¿Por qué tan pocos campos?**
Northwind tiene muchos campos en `Employees` (dirección, teléfono, foto, notas, etc.). En el datamart se incluyeron solo los que son relevantes para análisis de ventas. No tiene sentido llevar la foto del empleado a un datamart de ventas.

---

### 6.4 dim_shipper (SCD Tipo 1)

```sql
IF OBJECT_ID ('dim_shipper') IS NULL
BEGIN
CREATE TABLE dim_shipper(
    shipper_key  INT IDENTITY(1,1) PRIMARY KEY,
    shipperid_nk INT NOT NULL,
    company_name NVARCHAR(40) NOT NULL
);
END
GO
```

La dimensión más simple del modelo. Northwind solo tiene 3 transportistas, con pocos atributos relevantes. Solo se trae el nombre de la empresa.

---

### 6.5 dim_date (Dimensión Conformada)

```sql
IF OBJECT_ID ('dim_date') IS NULL
BEGIN
CREATE TABLE dim_date(
   date_key     INT NOT NULL PRIMARY KEY,
   [date]       DATE NOT NULL,
   [day]        TINYINT NOT NULL,
   [month]      TINYINT NOT NULL,
   month_name   VARCHAR(20) NOT NULL,
   [quarter]    TINYINT NOT NULL,
   [year]       SMALLINT NOT NULL,
   week_of_year TINYINT NOT NULL,
   is_weekend   BIT NOT NULL
);
END
GO
```

**`date_key INT NOT NULL PRIMARY KEY`** — la clave es un entero en formato `YYYYMMDD`. Por ejemplo, el 4 de julio de 1997 = `19970704`.

¿Por qué este formato? Porque:
1. Es legible como número (se puede ver en un resultado y entender la fecha)
2. Es ordenable: `ORDER BY date_key` ordena cronológicamente
3. Los filtros por rango son muy eficientes: `WHERE date_key BETWEEN 19970101 AND 19971231` (todo el año 1997)
4. Ocupa menos espacio que `DATE` o `DATETIME`

**`[date] DATE NOT NULL`** — el valor DATE real, para hacer joins con las tablas de staging donde las fechas son DATETIME. También va entre corchetes porque `DATE` es palabra reservada.

**`[day] TINYINT NOT NULL`** — día del mes (1–31). `TINYINT` ocupa 1 byte y soporta 0–255, perfectamente suficiente para valores del 1 al 31.

**`[month] TINYINT NOT NULL`** — número del mes (1–12).

**`month_name VARCHAR(20) NOT NULL`** — nombre del mes en texto ('January', 'February', etc.). Se usa `VARCHAR` aquí en lugar de `NVARCHAR` porque los nombres de meses en inglés son ASCII puro. Nótese que en este campo se usó `VARCHAR` en vez de `NVARCHAR` — es una inconsistencia menor del script original.

**`[quarter] TINYINT NOT NULL`** — trimestre (1–4).

**`[year] SMALLINT NOT NULL`** — año. `SMALLINT` ocupa 2 bytes y soporta -32,768 a 32,767. Suficiente para años dentro de un rango razonable.

**`week_of_year TINYINT NOT NULL`** — semana del año (1–52/53).

**`is_weekend BIT NOT NULL`** — 1 si es sábado o domingo, 0 si es día de semana. Útil para filtros rápidos en Power BI.

**"Dimensión Conformada"** — este término de Kimball significa que la misma `dim_date` puede (y debe) ser usada por múltiples fact tables en el datamart. Si en el futuro se agrega una `fact_purchases`, usaría la misma `dim_date`. Esto garantiza consistencia: el mismo `date_key` siempre representa la misma fecha en todo el sistema.

**¿Cómo se llena `dim_date`?**
Esta tabla no se llena con datos de NORTHWND. Se genera con un script separado que crea una fila por cada día del rango de fechas que cubre el datamart (típicamente desde la fecha del pedido más antiguo hasta la fecha más reciente, más algunos años hacia el futuro). Ese script generador no está incluido en el repositorio pero es un patrón estándar.

---

### 6.6 dim_supplier (SCD Tipo 2)

```sql
IF OBJECT_ID('dim_supplier') IS NULL
    BEGIN
        CREATE TABLE dim_supplier (
            supplier_key  INT IDENTITY(1,1) PRIMARY KEY,
            supplierid_nk INT NOT NULL,
            company_name  NVARCHAR(40) NOT NULL,
            contact_name  NVARCHAR(30) NULL,
            contact_title NVARCHAR(30) NULL,
            [address]     NVARCHAR(60) NULL,
            city          NVARCHAR(15) NULL,
            region        NVARCHAR(15) NULL,
            postal_code   NVARCHAR(10) NULL,
            country       NVARCHAR(15) NULL,
            start_date    DATE NOT NULL,
            end_date      DATE NULL,
            is_current    BIT NOT NULL DEFAULT (1)
        );
    END
GO
```

**`supplierid_nk INT NOT NULL`** — en Northwind, `SupplierID` es un entero, por eso aquí es `INT`. (Corrección aplicada: el script original usaba `NVARCHAR(10)` por error, ya que SupplierID es siempre un número entero.)

Esta dimensión tiene la misma estructura SCD Tipo 2 que `dim_customer` (start_date, end_date, is_current). Los proveedores también pueden cambiar de dirección o contacto, y ese historial puede ser relevante para análisis de compras.

---

### 6.7 fact_sales (Tabla de Hechos)

```sql
IF OBJECT_ID ('fact_sales') IS NULL
BEGIN
CREATE TABLE fact_sales(

    fact_sales_key BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Dimensiones
    order_date_key INT NOT NULL,
    customer_key   INT NOT NULL,
    product_key    INT NOT NULL,
    employee_key   INT NOT NULL,
    shipper_key    INT NOT NULL,
    supplier_key   INT NOT NULL,
    order_number   INT NOT NULL,

    -- Medidas
    order_qty     INT NOT NULL,
    unit_price    DECIMAL(19,4) NOT NULL,
    discount      DECIMAL(5,4) NOT NULL,
    extended_amount AS (CAST(order_qty * unit_price * (1 - discount) AS DECIMAL(19,4))) PERSISTED,

    -- Constraints de integridad
    CONSTRAINT chk_fact_sales_qty_positive   CHECK (order_qty > 0),
    CONSTRAINT chk_fact_sales_price_positive CHECK (unit_price > 0),
    CONSTRAINT chk_fact_sales_dicount_01     CHECK (discount >= 0 AND discount <= 1)
);
END
GO
```

**`fact_sales_key BIGINT IDENTITY(1,1) PRIMARY KEY`**
- `BIGINT` en lugar de `INT` porque la fact table puede crecer mucho (cada línea de cada pedido es una fila). `BIGINT` soporta ~9.2 billones de filas.

**Las 6 claves foráneas a dimensiones:**
- `order_date_key INT NOT NULL` — FK a `dim_date.date_key`
- `customer_key INT NOT NULL` — FK a `dim_customer.customer_key`
- `product_key INT NOT NULL` — FK a `dim_product.product_key`
- `employee_key INT NOT NULL` — FK a `dim_employee.employee_key`
- `shipper_key INT NOT NULL` — FK a `dim_shipper.shipper_key`
- `supplier_key INT NOT NULL` — FK a `dim_supplier.supplier_key`

Todas son `NOT NULL` porque cada venta debe tener un valor válido para cada dimensión. Una venta sin cliente, sin producto, sin fecha, etc. no tiene sentido analítico.

**`order_number INT NOT NULL`** — este no es una FK a una dimensión; es el `OrderID` de Northwind almacenado directamente como dato de degeneración (*degenerate dimension*). En Kimball, cuando un número de documento (factura, pedido) es necesario para análisis pero no justifica crear una dimensión completa, se guarda directamente en la fact table.

**Las métricas:**

`order_qty INT NOT NULL` — cantidad de unidades. Entero, porque no se venden fracciones de producto en Northwind.

`unit_price DECIMAL(19,4) NOT NULL` — precio por unidad.
- `DECIMAL(19,4)` = hasta 19 dígitos en total, 4 de ellos decimales. Esta precisión es estándar para valores monetarios en bases de datos financieras.
- `NOT NULL` porque toda venta tiene un precio.

`discount DECIMAL(5,4) NOT NULL` — descuento aplicado.
- `DECIMAL(5,4)` = 5 dígitos totales, 4 decimales. Esto permite valores como `0.0500` (5% de descuento), `0.2500` (25%), etc.
- El valor siempre está entre 0 y 1 (0% a 100%), enforceado por el CHECK constraint.

**`extended_amount AS (CAST(order_qty * unit_price * (1 - discount) AS DECIMAL(19,4))) PERSISTED`**

Esta es una **columna calculada persistida**. Merece explicación detallada:

- `AS (expresión)` — define una columna calculada. Su valor se calcula a partir de otras columnas.
- `CAST(... AS DECIMAL(19,4))` — convierte el resultado al tipo decimal con 4 decimales.
- La fórmula: `qty * unit_price * (1 - discount)` = monto total de la línea con descuento aplicado.
- `PERSISTED` — el valor calculado se almacena físicamente en el disco. Sin `PERSISTED`, se calcularía en cada lectura. Con `PERSISTED`, se calcula una sola vez al insertar/actualizar y se guarda. Esto hace las consultas de suma de ventas mucho más rápidas.

Ejemplo: si se vendieron 5 unidades a $20 con 10% de descuento:
```
extended_amount = 5 * 20 * (1 - 0.10) = 5 * 20 * 0.90 = 90.00
```

**Los CHECK constraints:**

```sql
CONSTRAINT chk_fact_sales_qty_positive   CHECK (order_qty > 0)
CONSTRAINT chk_fact_sales_price_positive CHECK (unit_price > 0)
CONSTRAINT chk_fact_sales_dicount_01     CHECK (discount >= 0 AND discount <= 1)
```

Los CHECK constraints son reglas de integridad a nivel de base de datos. Si alguien intenta insertar una fila con `order_qty = -5` o `discount = 1.5`, SQL Server lanza un error y rechaza el INSERT. Esto previene que datos inválidos lleguen al datamart.

- `qty > 0`: no puede haber una venta de cero o cantidad negativa
- `unit_price > 0`: no puede haber precio negativo o cero (las devoluciones se manejarían diferente)
- `discount >= 0 AND discount <= 1`: el descuento debe estar entre 0% y 100%

El nombre del constraint de descuento tiene un error de escritura: `chk_fact_sales_dicount_01` (falta una 's' en "discount"). Es un error menor heredado del código original que no afecta la funcionalidad.

---

### 6.8 Foreign Keys

Al final del script se agregan las restricciones de clave foránea:

```sql
ALTER TABLE fact_sales
ADD CONSTRAINT fk_fact_sales_dim_date
FOREIGN KEY (order_date_key)
REFERENCES dim_date (date_key)
GO
```

**¿Por qué las FKs se agregan con ALTER TABLE al final y no dentro del CREATE TABLE?**
Para que las tablas referenciadas (`dim_date`, `dim_customer`, etc.) ya existan cuando se crea la FK. Si se pusiera dentro del `CREATE TABLE fact_sales`, y las dimensiones aún no existieran, daría error. Al hacerlo con `ALTER TABLE` al final del script, cuando todas las tablas ya fueron creadas, evitamos el problema de orden de creación.

```sql
ALTER TABLE fact_sales
ADD CONSTRAINT fk_fact_sales_dim_product
FOREIGN KEY (product_key)
REFERENCES dim_product (product_key)
GO
```

Nótese que la FK referencia `dim_product` (no `dim_producto` — ese era el bug ya corregido).

```sql
ALTER TABLE fact_sales
ADD CONSTRAINT fk_fact_sales_dim_suplier
FOREIGN KEY (supplier_key)
REFERENCES dim_supplier (supplier_key)
GO
```

El nombre del constraint tiene un error tipográfico: `fk_fact_sales_dim_suplier` (le falta una 'p' en "supplier"). Es heredado del código original y no afecta la funcionalidad.

---

## 7. Script: 01-load_northwind_employee.sql

**Ubicación:** [ArquitecturaDM/Carga_Load_Northwind/01-load_northwind_employee.sql](ArquitecturaDM/Carga_Load_Northwind/01-load_northwind_employee.sql)

**Propósito:** Script de referencia que muestra la estructura de la tabla `Employees` en la capa `Load_Northwind` y las queries SQL que usa el paquete SSIS para el registro de metadata. Fue construido en clase para entender el patrón antes de implementarlo en SSIS.

> **Importante:** Este archivo NO está pensado para ejecutarse completo de una vez. Es una colección de scripts de referencia y consultas de verificación.

### DDL — Tabla Employees en Load_Northwind

```sql
use Load_Northwind
go

CREATE TABLE [dbo].[Employees](
    [EmployeeID]    [int] NOT NULL,
    [LastName]      [nvarchar](20) NOT NULL,
    [FirstName]     [nvarchar](10) NOT NULL,
    [Title]         [nvarchar](30) NULL,
    [TitleOfCourtesy] [nvarchar](25) NULL,
    [BirthDate]     [datetime] NULL,
    [HireDate]      [datetime] NULL,
    [Address]       [nvarchar](60) NULL,
    [City]          [nvarchar](15) NULL,
    [Region]        [nvarchar](15) NULL,
    [PostalCode]    [nvarchar](10) NULL,
    [Country]       [nvarchar](15) NULL,
    [HomePhone]     [nvarchar](24) NULL,
    [Extension]     [nvarchar](4) NULL,
    [Photo]         [image] NULL,
    [Notes]         [ntext] NULL,
    [ReportsTo]     [int] NULL,
    [PhotoPath]     [nvarchar](255) NULL,
    [ETLLoad]       datetime,
    [ETLExecution]  int
);
```

Esta tabla es una copia exacta de `NORTHWND.dbo.Employees` con dos columnas adicionales al final:
- `ETLLoad datetime` — cuándo fue cargada la fila por SSIS
- `ETLExecution int` — qué ejecución la cargó (FK implícita hacia `Northwind_Metadata.ETLExecution.Id`)

**`[Photo] [image] NULL`** — el tipo `image` es un tipo legacy de SQL Server para almacenar datos binarios grandes (BLOB). En versiones modernas se prefiere `VARBINARY(MAX)`, pero se mantiene igual que en la tabla original de Northwind por compatibilidad.

**`[Notes] [ntext] NULL`** — `ntext` también es legacy, versión de tipo `text` para Unicode. En versiones modernas se usa `NVARCHAR(MAX)`. Igual, se mantiene para espejo exacto de la fuente.

### Query de INSERT en ETLExecution (usada por SSIS)

```sql
INSERT INTO ETLExecution (UserName, MachineName, PackageName, ETLLoad)
VALUES (?,?,?,GETDATE());
```

Aquí los `?` son los parámetros de SSIS. En el editor de SSIS, a cada `?` se le asigna una variable del sistema:
- `?` #1 → `@[System::UserName]` — usuario de Windows actual
- `?` #2 → `@[System::MachineName]` — nombre del equipo
- `?` #3 → `@[System::PackageName]` — nombre del paquete SSIS

SSIS ejecuta esta query al inicio del paquete para registrar la ejecución.

### Query para recuperar el ID de la ejecución

```sql
SELECT TOP 1 ID FROM ETLExecution
WHERE PackageName = ?
ORDER BY ID DESC
```

Después de insertar el registro de ejecución, SSIS necesita saber qué ID se generó para ese INSERT. Esta query recupera el ID más reciente del paquete actual (`ORDER BY ID DESC` + `TOP 1`). El resultado se guarda en una variable SSIS que luego se usa para marcar los datos cargados.

**¿Por qué no usar `SCOPE_IDENTITY()` directamente?**
`SCOPE_IDENTITY()` devuelve el último `IDENTITY` generado en la sesión actual. Sería más elegante, pero en SSIS la forma más común de recuperar el ID generado es con una query separada. La query con `TOP 1 ... ORDER BY ID DESC` es una alternativa válida aunque ligeramente menos precisa en entornos de alta concurrencia (si dos paquetes del mismo nombre corren simultáneamente, podría recuperar el ID del otro). Para este proyecto de aprendizaje no es un problema.

### Consultas de verificación

```sql
TRUNCATE TABLE EMPLOYEES
```
Vacía la tabla antes de una nueva carga. SSIS llama esto al inicio para asegurar que la tabla de Load esté vacía antes de insertar los datos frescos.

```sql
SELECT * FROM Employees;
SELECT * FROM [Northwind_Metadata].dbo.ETLExecution;
SELECT * FROM NORTHWND.dbo.Products ORDER BY ProductID DESC;
SELECT * FROM Load_Northwind.dbo.Employees;
```
Consultas de verificación que se usaban durante el desarrollo para confirmar que los datos se cargaron correctamente. La referencia cruzada entre BDs (`Northwind_Metadata.dbo.ETLExecution`) funciona en SQL Server porque todos son bases de datos en el mismo servidor.

---

## 8. Script: scriptfactventas.sql

**Ubicación:** [ArquitecturaDM/scriptfactventas.sql](ArquitecturaDM/scriptfactventas.sql)

**Propósito:** El pipeline ETL completo documentado en SQL. Contiene el DDL de las capas Load y Stage, y el DML para cargar dimensiones, staging y la fact table. Está organizado en 5 secciones lógicas.

### Sección 1 — DDL Load_Northwind

```sql
IF OBJECT_ID('Load_Northwind.dbo.Customers') IS NULL
BEGIN
    CREATE TABLE Load_Northwind.dbo.Customers(
        [CustomerID]    [nchar](5)      NOT NULL,
        [CompanyName]   [nvarchar](40)  NOT NULL,
        ...
        ETLLoad         datetime,
        ETLExecution    int
    )
END
GO
```

**Referencia con nombre de 3 partes:** `Load_Northwind.dbo.Customers` = `<base_de_datos>.<schema>.<tabla>`. En SQL Server, el esquema por defecto es `dbo` (database owner). Esta notación de 3 partes permite hacer referencia a objetos en otras bases de datos del mismo servidor.

**`[CustomerID] [nchar](5)`** — nótese `nchar` en lugar de `nvarchar`. `nchar` es de longitud fija: siempre ocupa 5 caracteres, rellenando con espacios si es más corto. Se mantiene igual que en NORTHWND porque la capa Load es un espejo exacto de la fuente.

El mismo patrón se repite para `Shippers`, `Orders` y `[Order Details]`, todas con las columnas de auditoría `ETLLoad` y `ETLExecution` al final.

**`CREATE TABLE load_northwind.[dbo].[Order Details]`** — el nombre `Order Details` tiene un espacio, por lo que va entre corchetes `[]`. Este es el mismo nombre que en NORTHWND original.

---

### Sección 2 — DDL Stage_Northwind

```sql
IF OBJECT_ID('Stage_Northwind.dbo.Customers') IS NULL
BEGIN
    CREATE TABLE Stage_Northwind.dbo.Customers(
        [CustomerID]    [nchar](5)      NOT NULL,
        ...
        -- Sin columna Phone ni Fax (no se necesitan en Stage)
        ETLLoad         datetime,
        ETLExecution    int
    )
END
GO
```

La tabla Stage de Customers es similar a la de Load pero más reducida — ya no lleva `Phone` ni `Fax` porque no se usan en el análisis.

**`Stage_Northwind.dbo.Stage_Ventas`** — esta es la tabla más importante de la capa Stage:

```sql
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
```

Esta tabla consolida en una sola fila toda la información necesaria para cargar `fact_sales`. Elimina la necesidad de hacer joins complejos desde múltiples tablas en el momento de la carga al datamart.

Los nombres de columnas están en español porque así se crearon en clase. No hay un problema técnico — SQL Server no requiere que los nombres sean en ningún idioma en particular.

`[Ventas_Monto]` = monto calculado = `UnitPrice * Quantity * (1 - Discount)`. Esta columna se calcula en el INSERT desde Load, no se guarda en Load_Northwind.

`[Ventas_Unidades]` = cantidad de unidades (Quantity)
`[Ventas_PUnitario]` = precio unitario (UnitPrice)
`[Ventas_Descuento]` = descuento (Discount)

---

### Sección 3 — Carga de Dimensiones

```sql
INSERT INTO Datamart_Northwind.dbo.dim_shipper (shipperid_nk, company_name)
SELECT ShipperID, CompanyName
FROM NORTHWND.dbo.Shippers
GO
```

Carga inicial directa desde NORTHWND hacia la dimensión. Se usan los nombres de columna de NORTHWND en el SELECT y los de la dimensión en el INSERT. Solo hay 3 shippers en Northwind (Federal Shipping, Speedy Express, United Package).

```sql
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
```

Puntos importantes:

**`ISNULL(Region, 'NO REGION')`** — función que reemplaza valores NULL por un texto por defecto. En Northwind, muchos clientes europeos no tienen región (en Europa no se usa el mismo sistema de estados/provincias que en América). En lugar de dejar el NULL, se estandariza a 'NO REGION' para que los reportes en Power BI sean más limpios.

**`GETDATE() AS start_date`** — en la carga inicial, la fecha de inicio de vigencia es la fecha actual. En un escenario real se usaría la fecha del pedido más antiguo del cliente.

**`NULL AS end_date`** — NULL indica que el registro está activo (no tiene fecha de fin). Todos los registros nuevos empiezan con `end_date = NULL`.

**No se especifica `is_current`** — se omite porque tiene `DEFAULT (1)`, así SQL Server pone automáticamente `is_current = 1` al insertar.

---

### Sección 4 — Carga de Stage_Ventas

```sql
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
```

Esta query hace el JOIN entre `Orders` y `[Order Details]` para consolidar en una fila por línea de pedido.

**`(od.UnitPrice * od.Quantity * (1 - od.Discount)) AS Monto`** — el monto se calcula aquí para tenerlo disponible en Stage. Aunque `fact_sales` también tiene `extended_amount` como columna calculada, tener el monto en Stage permite verificar la suma en esa capa antes de cargar al datamart.

**`WHERE o.ETLExecution = ? AND od.ETLExecution = ?`** — los parámetros de SSIS filtran solo los registros de la ejecución actual. Si el paquete leyó registros con `ETLExecution = 42` en Load_Northwind, esta cláusula asegura que Stage_Ventas solo recibe las ventas nuevas de esa ejecución, no todo el histórico.

**¿Por qué hacer JOIN en Stage y no en el INSERT a fact_sales?**
Separar el JOIN en Stage tiene varias ventajas:
1. Si algo falla en la carga al datamart, se puede re-intentar desde Stage sin volver a leer desde Load
2. Se puede verificar la calidad de Stage_Ventas antes de cargar al datamart
3. El INSERT a fact_sales queda más limpio (un solo SELECT desde Stage en lugar de múltiples JOINs)

---

### Sección 5 — Carga Incremental de fact_sales

Esta es la parte más sofisticada del pipeline. Merece una explicación exhaustiva.

```sql
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
```

Se lee desde `Stage_Ventas` que ya tiene todo consolidado. Cada fila de Stage_Ventas corresponderá a una fila en fact_sales.

```sql
JOIN [Datamart_Northwind].dbo.dim_customer AS dc
    ON  sv.Cliente_Codigo   = dc.customerid_nk
    AND sv.Ventas_OrderDate >= dc.start_date
    AND sv.Ventas_OrderDate <  ISNULL(dc.end_date, '9999-12-31')
```

**Este es el JOIN SCD Tipo 2.** Es la parte más crítica de toda la carga.

- `sv.Cliente_Codigo = dc.customerid_nk` — empareja el código del cliente
- `sv.Ventas_OrderDate >= dc.start_date` — la fecha de la venta debe ser después del inicio de vigencia de esa versión del cliente
- `sv.Ventas_OrderDate < ISNULL(dc.end_date, '9999-12-31')` — la fecha de la venta debe ser antes del fin de vigencia. El `ISNULL(..., '9999-12-31')` maneja el caso del registro activo (`end_date = NULL`): si no tiene fin de vigencia, se asume que es válido hasta el año 9999.

Esto garantiza que si un cliente cambió de ciudad en 2020, las ventas anteriores a 2020 se asocian a la versión vieja (ciudad anterior) y las ventas desde 2020 se asocian a la versión nueva (ciudad nueva). El análisis histórico queda correcto.

```sql
JOIN Datamart_Northwind.[dbo].[dim_employee] AS de
    ON sv.Empleado_Codigo   = de.employeeid_nk
JOIN Datamart_Northwind.[dbo].[dim_product] AS dp
    ON sv.Producto_Codigo   = dp.productid_nk
```

Estos JOINs son simples (SCD Tipo 1) — solo se busca la clave natural, sin rango de fechas, porque estas dimensiones sobreescriben sus cambios.

```sql
JOIN [Datamart_Northwind].[dbo].[dim_date] AS dd
    ON dd.[date] = sv.Ventas_OrderDate
```

JOIN con la dimensión de fecha. `dim_date.date` es tipo `DATE` y `sv.Ventas_OrderDate` es tipo `DATETIME`. SQL Server hace la conversión implícitamente, pero solo funciona correctamente si la hora en `Ventas_OrderDate` es exactamente medianoche (00:00:00), que es el caso en Northwind donde las fechas de orden no tienen componente horario.

```sql
JOIN Datamart_Northwind.dbo.dim_shipper AS ds
    ON ds.shipperid_nk = sv.Transportista_codigo
```

JOIN simple para el transportista.

```sql
WHERE sv.Ventas_OrderDate >
    COALESCE(
        (SELECT MAX(d.[date])
         FROM Datamart_Northwind.dbo.fact_sales fs
         JOIN Datamart_Northwind.dbo.dim_date d
             ON fs.order_date_key = d.date_key),
        '19000101'
    )
```

**Este es el filtro de carga incremental.** Explicación detallada:

La subconsulta `(SELECT MAX(d.[date]) FROM fact_sales fs JOIN dim_date d ...)` encuentra la fecha más reciente que ya existe en `fact_sales`. Si el datamart ya tiene ventas hasta el 31 de diciembre de 1997, esta subconsulta devuelve `1997-12-31`.

`COALESCE(subconsulta, '19000101')` — si la subconsulta devuelve NULL (lo que ocurre cuando `fact_sales` está vacía, es decir, en la primera carga), se usa la fecha `'19000101'` (1 de enero de 1900) como valor por defecto. Esto garantiza que en la primera ejecución se carguen TODOS los datos, porque todas las fechas de Northwind son posteriores a 1900.

`WHERE sv.Ventas_OrderDate > <fecha_maxima>` — solo se insertan ventas con fecha posterior a la última ya cargada. Esto hace la carga incremental: en cada ejecución solo se procesan los datos nuevos.

**Limitación de este enfoque:** usa la fecha como criterio de incrementalidad. Si una venta tiene la misma fecha que la última cargada (por ejemplo, si hay dos ventas el mismo día y solo se cargó una), el segundo intento cargará la segunda. Pero si hay ventas muy antiguas que llegan tarde (lo que no ocurre en Northwind pero sí en sistemas reales), no serían procesadas.

```sql
ORDER BY
      dc.customer_key
    , de.employee_key
    , dp.product_key
    , ds.shipper_key
    , dd.date_key
    , sv.Ventas_NOrden;
```

El `ORDER BY` en un INSERT no tiene efecto en el orden de almacenamiento (SQL Server no garantiza orden físico), pero puede mejorar el rendimiento de la inserción si el índice clustered de `fact_sales` coincide con este orden. Aquí es más bien documentación de la intención que una optimización real.

---

## 9. Paquetes SSIS

Los paquetes SSIS (.dtsx) son archivos XML que describen flujos de trabajo de datos. Se abren y editan con **Visual Studio** con la extensión **SQL Server Data Tools (SSDT)**. Hay tres proyectos SSIS en el repositorio:

### 9.1 Stage_Nortwind — Proyecto 1 (versión inicial)

**Ubicación:** [ProyectoETL_DM_Kimball/Stage_Nortwind/](ProyectoETL_DM_Kimball/Stage_Nortwind/)

Este fue el primer proyecto construido. Su objetivo era cargar datos desde NORTHWND directamente a la capa Stage. Es la versión más simple — no tiene capa Load ni metadata de ejecución.

| Paquete | Flujo | Detalle |
|---|---|---|
| `CargaMaster.dtsx` | Orquestador | Contiene tareas de "Execute Package" que llaman a los demás paquetes en secuencia |
| `StageClientes.dtsx` | NORTHWND.Customers → Stage_Northwind.Customers | Aplica ISNULL en Region |
| `StageEmpleado.dtsx` | NORTHWND.Employees → Stage con campos básicos | |
| `StageProducto.dtsx` | NORTHWND.Products + Categories + Suppliers → Stage | Desnormaliza categoría y proveedor |
| `StageTransportistas.dtsx` | NORTHWND.Shippers → Stage_Northwind.Shippers | |
| `StageVentas.dtsx` | NORTHWND.Orders + [Order Details] → Stage_Ventas | Calcula Monto, construye Stage_Ventas |

### 9.2 Datamart_Nortwind — Proyecto 2 (versión media)

**Ubicación:** [ProyectoETL_DM_Kimball/Datamart_Nortwind/](ProyectoETL_DM_Kimball/Datamart_Nortwind/)

Segunda iteración. Añade la carga desde Stage al Datamart. Ya implementa lógica SCD.

| Paquete | Flujo | Detalle |
|---|---|---|
| `CargaMaster.dtsx` | Orquestador completo | Llama a Stage + Datamart en orden |
| `DimCustommers.dtsx` | Stage_Northwind → dim_customer | Implementa SCD Tipo 2 usando Lookup + Conditional Split |
| `DimEmpleado.dtsx` | Stage_Northwind → dim_employee | SCD Tipo 1: Lookup + UPDATE si existe, INSERT si no |
| `DimProducto.dtsx` | Stage_Northwind → dim_product | SCD Tipo 1 |
| `DimShippers.dtsx` | Stage_Northwind → dim_shipper | SCD Tipo 1 |
| `FactSales.dtsx` | Stage_Ventas → fact_sales | Carga incremental, JOINs con dimensiones para obtener surrogate keys |
| `Package1.dtsx` | Scratch | Paquete de prueba creado durante el desarrollo. No forma parte del flujo productivo. |

### 9.3 DatamartNorthwind — Proyecto 3 (versión final)

**Ubicación:** [ProyectoETL_DM_Kimball/DatamartNorthwind/](ProyectoETL_DM_Kimball/DatamartNorthwind/)

La versión más completa. Incorpora la capa Load_Northwind y la metadata de ejecución. Es el flujo correcto de 4 capas.

| Paquete | Flujo completo | Detalle |
|---|---|---|
| `CargaMaster.dtsx` | Orquestador maestro | Ejecuta todos los paquetes en el orden correcto: primero Load, luego Dims, luego Fact |
| `LoadEmployee.dtsx` | NORTHWND → Load → dim_employee | 1) Registra en metadata, 2) Copia a Load con ETLExecution, 3) Carga dim_employee |
| `LoadCustomers.dtsx` | NORTHWND → Load → dim_customer | Ídem + SCD Tipo 2 |
| `LoadProducts.dtsx` | NORTHWND → Load → dim_product | Ídem + desnormalización de Category y Supplier |
| `LoadShippers.dtsx` | NORTHWND → Load → dim_shipper | Ídem |
| `LoadOrders.dtsx` | NORTHWND → Load_Northwind.Orders | Solo carga a Load, el Stage_Ventas se hace en el siguiente paquete |
| `LoadOrderDetails.dtsx` | NORTHWND → Load.[Order Details] → Stage_Ventas → fact_sales | El paquete más complejo: carga Order Details, construye Stage_Ventas, luego carga fact_sales con la query incremental SCD2-aware |

### ¿Cómo funciona el SCD Tipo 2 dentro de SSIS?

El componente estándar en SSIS para SCD es **Slowly Changing Dimension Transform**, pero también se puede hacer con combinaciones de:
- **Lookup** — busca si la clave natural ya existe en la dimensión
- **Conditional Split** — separa los flujos en: "es nuevo", "cambió", "sin cambios"
- **OLE DB Command** — ejecuta UPDATE para cerrar el registro viejo (poner end_date y is_current = 0)
- **OLE DB Destination** — inserta el registro nuevo

En términos de SQL, lo que hace SSIS con SCD2 es equivalente a:
```sql
-- Cerrar el registro viejo
UPDATE dim_customer
SET end_date = CAST(GETDATE() AS DATE),
    is_current = 0
WHERE customerid_nk = 'ALFKI'
  AND is_current = 1;

-- Insertar el nuevo registro
INSERT INTO dim_customer (customerid_nk, company_name, ..., start_date, end_date, is_current)
VALUES ('ALFKI', 'Nuevo Nombre', ..., CAST(GETDATE() AS DATE), NULL, 1);
```

---

## 10. Power BI

**Archivo:** [PowerBi/Visualizacion_Datamart_Nortwind.pbix](PowerBi/Visualizacion_Datamart_Nortwind.pbix)

El archivo `.pbix` es el formato nativo de Power BI Desktop. Contiene el modelo de datos, las consultas de conexión a SQL Server, y los reportes visuales.

### Conexión al Datamart

Power BI se conecta directamente a `Datamart_Northwind` en el SQL Server. Para que el reporte funcione al abrirlo:

1. SQL Server debe estar corriendo (el contenedor Docker debe estar activo)
2. El datamart debe tener datos (los paquetes SSIS deben haberse ejecutado al menos una vez)
3. Al abrir el .pbix, Power BI pedirá las credenciales de SQL Server

### ¿Por qué Power BI se conecta al Datamart y no a NORTHWND directamente?

Esta es la razón de existir de todo el pipeline:

- **NORTHWND es un sistema transaccional (OLTP)**: optimizado para muchas transacciones pequeñas (insertar pedidos, actualizar stocks). Los queries analíticos (ventas por mes, por cliente, por producto) son lentos porque requieren joins complejos y agregaciones sobre millones de filas.
- **Datamart_Northwind es analítico (OLAP)**: optimizado para queries de agregación. El modelo estrella con dimensiones desnormalizadas y la fact table con datos precalculados hacen que Power BI pueda calcular KPIs en milisegundos.

---

## 11. Configuración Docker

### 11.1 SQL Server

**Archivo:** [sgbd-docker/sqlserver/docker-compose.yaml](sgbd-docker/sqlserver/docker-compose.yaml)

```yaml
services:
  sqlserverBI:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: sqlserverBI
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_SA_PASSWORD=P@ssw0rd
    ports:
      - "1422:1433"
    volumes:
      - sqlserver-volume:/var/opt/mssql
      - "C:\\proyectodatawarehouse\\datasource:/var/opt/mssql/datasets"
    restart: always

volumes:
  sqlserver-volume:
    external: true
```

**`image: mcr.microsoft.com/mssql/server:2022-latest`** — imagen oficial de SQL Server 2022 publicada por Microsoft en su propio registro de contenedores (mcr.microsoft.com).

**`ACCEPT_EULA=Y`** — acepta el acuerdo de licencia de usuario final de SQL Server. Sin esta variable de entorno, el contenedor no inicia.

**`MSSQL_SA_PASSWORD=P@ssw0rd`** — contraseña del usuario `sa` (system administrator). SQL Server requiere que la contraseña cumpla requisitos de complejidad: al menos 8 caracteres, mayúsculas, minúsculas, números y caracteres especiales.

**`ports: "1422:1433"`** — mapea el puerto 1422 del host (tu computadora) al puerto 1433 interno del contenedor (puerto estándar de SQL Server). Se usa 1422 en lugar de 1433 para no conflictuar si ya hay otra instancia de SQL Server instalada localmente en el puerto estándar.

Para conectarse desde SSMS o Power BI: `localhost,1422` (nótese la coma, no dos puntos, en la notación de SQL Server).

**`volumes:`**
- `sqlserver-volume:/var/opt/mssql` — volumen Docker para persistencia. Los datos de las bases de datos se guardan aquí. Sin este volumen, al eliminar el contenedor se perderían todos los datos.
- `"C:\\proyectodatawarehouse\\datasource:/var/opt/mssql/datasets"` — bind mount que conecta la carpeta local de Windows `C:\proyectodatawarehouse\datasource` con la carpeta `/var/opt/mssql/datasets` dentro del contenedor. Útil para importar archivos de datos (CSV, Excel) al contenedor.

**`restart: always`** — el contenedor se reinicia automáticamente si se detiene, o al reiniciar el sistema operativo.

**`external: true`** en volumes — indica que el volumen `sqlserver-volume` debe crearse manualmente antes de usar docker-compose. Si no existe, docker-compose fallará. Por eso el primer paso es `docker volume create sqlserver-volume`.

**Comandos de setup:**
```bash
docker volume create sqlserver-volume
docker compose -f sgbd-docker/sqlserver/docker-compose.yaml up -d
```

El flag `-d` (detached) hace que el contenedor corra en segundo plano.

También hay un archivo de referencia con el comando `docker run` directo ([sgbd-docker/sqlserver/docker-sqlserver.md](sgbd-docker/sqlserver/docker-sqlserver.md)):
```bash
# Linux/Mac
docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Mipassw0rd123!" \
-p 1422:1433 --name sqlserverBI \
-v sqlserver-volume:/var/opt/mssql \
-d mcr.microsoft.com/mssql/server:2022-latest

# Windows (PowerShell)
docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Mipassw0rd123!" `
-p 1422:1433 --name sqlserverBI `
-v sqlserver-volume:/var/opt/mssql `
-d mcr.microsoft.com/mssql/server:2022-latest
```

En PowerShell, el backtick `` ` `` es el carácter de continuación de línea (equivalente al `\` de bash).

---

### 11.2 PostgreSQL + pgAdmin

**Archivo:** [sgbd-docker/postgres/docker-compose.yaml](sgbd-docker/postgres/docker-compose.yaml)

```yaml
services:
  db:
    container_name: postgres_database
    image: postgres:15.1
    volumes:
      - postgres-db:/var/lib/postgresql/data
    environment:
      - POSTGRES_PASSWORD=123456
    ports:
      - "5432:5432"
    restart: always

  pgAdmin:
    depends_on:
      - db
    image: dpage/pgadmin4:6.17
    volumes:
      - pgadmin-data:/var/lib/pgadmin
    ports:
      - "8080:80"
    restart: always
    environment:
      - PGADMIN_DEFAULT_PASSWORD=123456
      - PGADMIN_DEFAULT_EMAIL=gallardo@google.com

volumes:
  postgres-db:
    external: true
  pgadmin-data:
    external: true
```

**`image: postgres:15.1`** — PostgreSQL versión 15.1, imagen oficial de Docker Hub.

**`POSTGRES_PASSWORD=123456`** — contraseña del superusuario `postgres`. A diferencia de SQL Server, PostgreSQL no requiere contraseña compleja para el usuario root.

**`ports: "5432:5432"`** — mapeo directo del puerto estándar de PostgreSQL (5432).

**`depends_on: - db`** — pgAdmin espera a que el contenedor `db` (PostgreSQL) esté levantado antes de iniciar. Sin esto, pgAdmin podría iniciarse antes de que la BD esté lista.

**`image: dpage/pgadmin4:6.17`** — pgAdmin 4 versión 6.17, la interfaz web de administración de PostgreSQL.

**`ports: "8080:80"`** — pgAdmin corre internamente en el puerto 80 (HTTP), que se mapea al 8080 del host. Se accede en `http://localhost:8080`.

**`PGADMIN_DEFAULT_EMAIL`** — el correo electrónico se usa como usuario de login en pgAdmin. Puede ser cualquier email, no tiene que ser real.

**Comandos de setup:**
```bash
docker volume create postgres-db
docker volume create pgadmin-data
docker compose -f sgbd-docker/postgres/docker-compose.yaml up -d
```

**Guía para conectar pgAdmin a PostgreSQL** ([sgbd-docker/postgres/docker-red-postgres-pgadmin.md](sgbd-docker/postgres/docker-red-postgres-pgadmin.md)):

El paso no obvio es que pgAdmin y PostgreSQL, aunque están en el mismo `docker-compose.yaml`, necesitan estar en la misma red Docker para comunicarse. El archivo docker-compose los pone automáticamente en la misma red por defecto, por lo que en la versión con docker-compose no es necesario crear la red manualmente.

Para conectar desde pgAdmin al servidor PostgreSQL, en la pestaña de conexión usar:
- Hostname: `postgres_database` (el nombre del contenedor, no `localhost`)
- Port: `5432`
- Username: `postgres`
- Password: `123456`

Usar el nombre del contenedor como hostname es clave — dentro de la red Docker, los contenedores se comunican por nombre, no por IP.

---

## 12. Tópicos SQL — script_topicos_sql.sql

**Ubicación:** [topicosSQL/script_topicos_sql.sql](topicosSQL/script_topicos_sql.sql)

Este script es material de estudio de T-SQL independiente del proyecto Northwind. Fue construido en clase para aprender las bases del lenguaje. A continuación se documenta cada sección con sus conceptos.

---

### 12.1 Creación de Base de Datos y Tablas

```sql
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'miniBD')
BEGIN
    CREATE DATABASE miniBD
    COLLATE Latin1_General_100_CI_AS_SC_UTF8;
END
GO
```

**`IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'miniBD')`** — alternativa a `DB_ID()` para comprobar si una BD existe. Aquí se usa una subconsulta en `sys.databases`. El resultado es el mismo, pero esta forma es más explícita.

**`N'miniBD'`** — el prefijo `N` delante de un string indica que es Unicode (nchar/nvarchar). Es buena práctica usarlo cuando se busca en columnas `nvarchar` como `sys.databases.name`.

**`COLLATE Latin1_General_100_CI_AS_SC_UTF8`** — la collation define las reglas de comparación y ordenamiento de texto:
- `Latin1_General_100` — conjunto base de caracteres Latin1 versión 100
- `CI` — Case Insensitive (no distingue mayúsculas/minúsculas: 'Ana' = 'ana')
- `AS` — Accent Sensitive (sí distingue acentos: 'é' ≠ 'e')
- `SC` — Supplementary Characters (soporte para caracteres Unicode fuera del plano básico)
- `UTF8` — almacena datos `VARCHAR`/`CHAR` en formato UTF-8

---

```sql
USE miniBD;
GO
```

Cambia el contexto a la nueva BD. Todo lo que sigue se ejecuta dentro de `miniBD`.

---

```sql
IF OBJECT_ID('clientes', 'U') IS NOT NULL DROP TABLE clientes;

CREATE TABLE clientes(
  IdCliente INT NOT NULL,
  Nombre    NVARCHAR(100),
  Edad      INT,
  Ciudad    NVARCHAR(100),
  CONSTRAINT pk_clientes PRIMARY KEY (idcliente)
);
GO
```

**`IF OBJECT_ID('clientes', 'U') IS NOT NULL DROP TABLE clientes`** — antes de crear la tabla, la elimina si ya existe. El segundo parámetro `'U'` especifica que se busca un objeto de tipo 'U' (User table). Esto es útil en scripts de desarrollo donde se recrea la tabla frecuentemente. En producción esta práctica sería peligrosa.

**`CONSTRAINT pk_clientes PRIMARY KEY (idcliente)`** — forma de nombrar explícitamente el constraint de clave primaria. Nombrar los constraints es buena práctica porque cuando hay un error de violación de PK, el mensaje de error muestra el nombre del constraint, facilitando el diagnóstico.

**`Nombre NVARCHAR(100)`** — sin `NOT NULL`, lo que significa que acepta valores NULL por defecto. En tablas reales, los campos importantes como el nombre deberían ser `NOT NULL`.

---

### 12.2 INSERT — Diferentes Formas

```sql
-- Forma 1: INSERT sin especificar columnas (todas las columnas en orden)
INSERT INTO clientes
VALUES (1, 'Ana Torres', 25, 'Ciudad de México');
```

Esta forma es frágil: si alguien añade una columna a la tabla, el INSERT puede fallar o insertar datos en el orden incorrecto.

```sql
-- Forma 2: INSERT especificando columnas (recomendada)
INSERT INTO clientes (IdCliente, Nombre, Edad, Ciudad)
VALUES(2, 'Luis Perez', 34, 'Guadalajara');
```

La forma recomendada. Se especifica explícitamente qué va a cada columna. Robusto ante cambios en la estructura de la tabla.

```sql
-- Forma 3: INSERT con columnas en diferente orden
INSERT INTO clientes (IdCliente, Edad, Nombre, Ciudad)
VALUES (3, 29, 'Soyla Vaca', NULL);
```

Las columnas no tienen que estar en el mismo orden que en la tabla — solo deben coincidir con el orden de los valores en `VALUES`.

```sql
-- Forma 4: INSERT con columna omitida (se inserta NULL)
INSERT INTO clientes (IdCliente, Nombre, Edad)
VALUES (4, 'Natacha', 41);
```

Si se omite `Ciudad`, se inserta `NULL` en esa columna (siempre que la columna lo permita).

```sql
-- Forma 5: INSERT múltiple (varios registros en un solo INSERT)
INSERT INTO clientes (IdCliente, Nombre, Edad, Ciudad)
VALUES (5, 'Sofía Lopez', 19, 'Chapulhuacan'),
       (6, 'Laura Hernandez', 38, NULL),
       (7, 'Victor Trujillo', 25, 'Zacualtipan');
```

Más eficiente que hacer tres INSERTs separados — envía un solo batch al servidor.

---

### 12.3 Store Procedures

```sql
CREATE OR ALTER PROCEDURE sp_add_customer
 @Id INT, @Nombre NVARCHAR(100), @edad INT, @ciudad NVARCHAR(100)
AS
BEGIN
    INSERT INTO clientes (IdCliente, Nombre, Edad, Ciudad)
    VALUES (@Id, @Nombre, @edad, @ciudad);
END;
GO
```

**`CREATE OR ALTER PROCEDURE`** — sintaxis moderna (SQL Server 2016+) que crea el procedimiento si no existe, o lo modifica si ya existe. Antes de esta sintaxis se tenía que escribir `IF EXISTS ... DROP PROCEDURE ... GO ... CREATE PROCEDURE`.

**`@Id INT`** — los parámetros de entrada se declaran con `@` seguido del nombre. Cada parámetro tiene un tipo.

**`AS BEGIN ... END`** — el cuerpo del procedimiento. Puede contener cualquier instrucción T-SQL.

**Ejecución:**
```sql
EXEC sp_add_customer 8, 'Carlos Ruiz', 41, 'Monterrey';
```
Se pasan los valores en el mismo orden que los parámetros.

```sql
EXECUTE sp_update_customers
@ciudad='Martinez de la Torre',
@edad = 56,
@id = 3,
@nombre = 'Toribio Trompudo';
```
Con parámetros nombrados, el orden no importa. `EXEC` y `EXECUTE` son sinónimos.

---

### 12.4 SELECT con Funciones Escalares

```sql
SELECT UPPER(Nombre) AS [Cliente], edad, UPPER(ciudad) AS [Ciudad]
FROM clientes
ORDER BY edad DESC;
```

**`UPPER()`** — convierte a mayúsculas. Aquí se usa para presentación en el resultado, sin modificar los datos almacenados.

**`AS [Cliente]`** — alias de columna. Los corchetes permiten usar espacios y palabras reservadas en los alias.

**`ORDER BY edad DESC`** — ordena por edad de mayor a menor. `ASC` (ascendente) es el valor por defecto si no se especifica.

---

### 12.5 Filtros WHERE

```sql
WHERE Ciudad = 'Guadalajara'                    -- igualdad exacta
WHERE edad >= 30                                -- mayor o igual
WHERE ciudad IS NULL                            -- comprobar nulos (nunca usar = NULL)
WHERE edad BETWEEN 20 AND 35 AND Ciudad IN ('Guadalajara', 'Chapulhuacan')
```

**`IS NULL`** — la forma correcta de comprobar nulos en SQL. `ciudad = NULL` siempre es FALSE, incluso si ciudad es NULL, porque NULL no es igual a nada (ni siquiera a otro NULL). Siempre usar `IS NULL` o `IS NOT NULL`.

**`BETWEEN`** — inclusivo en ambos extremos: `edad BETWEEN 20 AND 35` = `edad >= 20 AND edad <= 35`.

**`IN`** — comprueba si el valor está en una lista. Más legible que múltiples `OR`.

---

### 12.6 UPDATE

```sql
UPDATE clientes
SET ciudad = 'Xochitlan'
WHERE IdCliente = 5;
```

La forma básica de actualizar. El `WHERE` es crítico — sin él, actualiza TODAS las filas.

```sql
UPDATE clientes
SET ciudad = 'Sin Ciudad'
WHERE ciudad IS NULL;
```

Se puede usar `IS NULL` en el `WHERE` de un UPDATE para reemplazar nulos en masa.

```sql
UPDATE clientes
SET Nombre = 'Juan Perez',
    Edad = 27,
    Ciudad = 'Ciudad Gotica'
WHERE IdCliente = 2;
```

Actualizar múltiples columnas en un solo UPDATE.

```sql
UPDATE clientes
SET nombre = 'Cliente Premium'
WHERE Nombre LIKE 'A%';
```

**`LIKE 'A%'`** — patrón de búsqueda:
- `%` = cualquier cantidad de caracteres cualquiera
- `_` = exactamente un carácter cualquiera
- `'A%'` = empieza con A
- `'%er%'` = contiene 'er' en cualquier posición
- `'%r'` = termina en 'r'

```sql
UPDATE clientes
SET edad = (edad * 2)
WHERE edad >= 30 AND ciudad = 'metropoli';
```

Se puede usar el valor actual de la columna en el SET (calcular el nuevo valor basado en el viejo).

---

### 12.7 DELETE y TRUNCATE

```sql
DELETE FROM clientes
WHERE edad BETWEEN 25 AND 30;
```

**`DELETE`** — elimina filas que cumplen la condición. Registra cada eliminación en el log de transacciones (es reversible con ROLLBACK si está dentro de una transacción). Sin `WHERE` elimina todas las filas.

```sql
TRUNCATE TABLE clientes;
```

**`TRUNCATE`** — vacía la tabla completamente. Es más rápido que `DELETE` sin `WHERE` porque no registra cada fila en el log (registra solo la desasignación de páginas). No se puede usar con `WHERE`. Reinicia los contadores `IDENTITY`. No se puede hacer ROLLBACK en muchos casos.

**Diferencias clave DELETE vs TRUNCATE:**

| Aspecto | DELETE | TRUNCATE |
|---|---|---|
| Velocidad | Lento en tablas grandes | Muy rápido |
| Log de transacciones | Registra cada fila | Registra solo las páginas |
| WHERE | Sí permite filtrar | No, siempre vacía todo |
| IDENTITY | No reinicia el contador | Sí reinicia a 1 |
| Triggers | Dispara triggers DELETE | No dispara triggers |
| Rollback | Sí, si está en transacción | Limitado |

---

### 12.8 Store Procedure Complejo — Venta con Detalle

Este es el ejercicio más avanzado del script. Demuestra el patrón de insertar una transacción con encabezado y detalle usando un Store Procedure y Table Types.

**Creación del schema:**

```sql
CREATE TABLE ventas(
  IdVenta    INT IDENTITY (1,1) PRIMARY KEY,
  FechaVenta DATETIME NOT NULL DEFAULT GETDATE(),
  Cliente    NVARCHAR(100) NOT NULL,
  Total      DECIMAL (10,2) NULL
);

CREATE TABLE DetalleVenta(
    IdDetalle INT IDENTITY (1,1) PRIMARY KEY,
    IdVenta   INT NOT NULL,
    Producto  NVARCHAR(100) NOT NULL,
    Cantidad  INT NOT NULL,
    Precio    DECIMAL(10,2) NOT NULL
    CONSTRAINT pk_detalleVenta_venta
    FOREIGN KEY (IdVenta)
    REFERENCES Ventas(IdVenta)
);
```

**`DEFAULT GETDATE()`** — si no se especifica FechaVenta al insertar, SQL Server pone automáticamente la fecha/hora actual.

**`Total DECIMAL(10,2) NULL`** — el total empieza como NULL y se calcula después dentro del SP usando los detalles.

**`CONSTRAINT pk_detalleVenta_venta FOREIGN KEY (...)`** — la FK garantiza que no se pueden insertar detalles para una venta que no existe. Si se intenta `INSERT INTO DetalleVenta (IdVenta=999, ...)` y no existe una venta con ID 999, SQL Server lanza un error.

**Creación del Table Type:**

```sql
CREATE TYPE TipoDetalleVentas AS TABLE (
    Producto NVARCHAR(100),
    Cantidad INT,
    Precio DECIMAL(10,2)
);
```

Un **Table Type** (tipo de tabla) es una estructura de tabla reutilizable que puede pasarse como parámetro a un Store Procedure. Permite enviar múltiples filas de datos de una vez a un SP. Es el equivalente SQL de enviar una lista como argumento a una función.

**El Store Procedure:**

```sql
CREATE OR ALTER PROCEDURE InsertarVentaConDetalle
 @Cliente NVARCHAR(100),
 @Detalles TipoDetalleVentas READONLY
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IdVenta INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1) Insertar encabezado
        INSERT INTO ventas (Cliente)
        VALUES(@Cliente);

        -- 2) Capturar el ID generado
        SET @IdVenta = SCOPE_IDENTITY();

        -- 3) Insertar detalles usando el ID recién creado
        INSERT INTO DetalleVenta (IdVenta, Producto, Cantidad, precio)
        SELECT @IdVenta, producto, cantidad, precio
        FROM @Detalles;

        -- 4) Calcular y guardar el total
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
```

**`@Detalles TipoDetalleVentas READONLY`** — el parámetro es del tipo de tabla creado antes. `READONLY` es obligatorio para parámetros de tipo tabla — no se puede modificar el parámetro dentro del SP.

**`SET NOCOUNT ON`** — suprime los mensajes "N row(s) affected" que SQL Server envía después de cada DML. Mejora el rendimiento y evita que aplicaciones cliente malinterpreten esos mensajes como resultsets.

**`DECLARE @IdVenta INT`** — declara una variable local para guardar el ID de la venta recién insertada.

**`BEGIN TRY / BEGIN CATCH`** — manejo de errores en T-SQL. Si cualquier instrucción dentro del `TRY` falla, el control salta al `CATCH`. Sin este bloque, si el INSERT de detalles falla, el encabezado quedaría insertado sin detalles (datos inconsistentes).

**`BEGIN TRANSACTION / COMMIT TRANSACTION`** — define una transacción explícita. Todas las operaciones dentro (INSERT encabezado + INSERT detalles + UPDATE total) son atómicas: o todas se completan (COMMIT) o ninguna se aplica (ROLLBACK).

**`SCOPE_IDENTITY()`** — devuelve el último valor IDENTITY generado en la sesión y scope actual. Es más seguro que `@@IDENTITY` que devuelve el último IDENTITY generado en la sesión sin importar el scope (podría retornar el ID de un trigger, por ejemplo).

**`ROLLBACK TRANSACTION`** — en el CATCH, deshace todas las operaciones de la transacción. La BD queda como estaba antes del BEGIN TRANSACTION.

**`THROW`** — relanza el error original. Sin esto, el error quedaría silenciado y la aplicación no sabría que algo falló.

**Ejecución del SP:**

```sql
DECLARE @MisDetalles AS TipoDetalleVentas

INSERT INTO @MisDetalles (Producto, Cantidad, Precio)
VALUES
 ('Laptop', 1, 15000),
 ('Mouse', 2, 300),
 ('Teclado', 1, 500),
 ('Pantalla', 5, 4500);

EXEC InsertarVentaConDetalle @Cliente='Uriel Edgar', @Detalles=@MisDetalles;
```

Se declara una variable del tipo tabla, se llenan los datos, y se pasa al SP. El SP inserta la venta 'Uriel Edgar' con Total = (1×15000) + (2×300) + (1×500) + (5×4500) = 38,100.

---

### 12.9 Funciones de Cadena

```sql
SELECT
 Nombre AS [Nombre Fuente],
 LTRIM(UPPER(Nombre)) AS Mayusculas,
 LOWER(Nombre) AS Minusculas,
 LEN(Nombre) AS Longitud,
 SUBSTRING(Nombre, 1, 3) AS Prefijo,
 LTRIM(Nombre) AS [Sin Espacios Izquierda],
 CONCAT(Nombre, ' - ', Edad) AS [Nombre Edad],
 UPPER(REPLACE(TRIM(Ciudad), 'Chapulhucan', 'Chapu')) AS [Ciudad Normal]
FROM clientes;
```

| Función | Lo que hace | Ejemplo |
|---|---|---|
| `UPPER(texto)` | Todo a mayúsculas | `UPPER('ana')` → `'ANA'` |
| `LOWER(texto)` | Todo a minúsculas | `LOWER('ANA')` → `'ana'` |
| `LTRIM(texto)` | Elimina espacios izquierda | `LTRIM(' hola')` → `'hola'` |
| `RTRIM(texto)` | Elimina espacios derecha | `RTRIM('hola ')` → `'hola'` |
| `TRIM(texto)` | Elimina espacios ambos lados | `TRIM(' hola ')` → `'hola'` |
| `LEN(texto)` | Longitud sin contar espacios finales | `LEN('SQL ')` → `3` |
| `SUBSTRING(texto, inicio, largo)` | Extrae substring | `SUBSTRING('SQLServer', 1, 3)` → `'SQL'` |
| `CONCAT(v1, v2, ...)` | Une valores | `CONCAT('Ana', ' ', 25)` → `'Ana 25'` |
| `REPLACE(texto, buscar, reemplazar)` | Reemplaza texto | `REPLACE('hello', 'l', 'r')` → `'herro'` |

**Funciones compuestas:** se pueden anidar. `UPPER(REPLACE(TRIM(Ciudad), 'Chapulhucan', 'Chapu'))` primero quita espacios, luego reemplaza el texto, luego convierte a mayúsculas.

---

### 12.10 SELECT INTO (Crear tabla a partir de consulta)

```sql
SELECT TOP 0
 idCliente,
 UPPER(Nombre) AS Mayusculas,
 LOWER(Nombre) AS Minusculas,
 ...
INTO stage_clientes
FROM clientes;
```

**`SELECT ... INTO tabla_nueva`** — crea una nueva tabla con la estructura definida por el SELECT y la llena con los datos del SELECT. Si la tabla ya existe, da error.

**`TOP 0`** — selecciona cero filas. El truco de `SELECT TOP 0 ... INTO` crea la tabla con la estructura correcta pero vacía. Luego se puede añadir constraints y cargar los datos por separado con INSERT.

**`ALTER TABLE stage_clientes ADD CONSTRAINT pk_stage_clientes PRIMARY KEY(idCliente)`** — como `SELECT INTO` no copia los constraints de la tabla origen, se agregan manualmente con `ALTER TABLE`.

---

### 12.11 INSERT-SELECT

```sql
INSERT INTO stage_clientes (IdCliente, [Nombre Fuente], Mayusculas, ...)
SELECT
 idCliente,
 Nombre AS [Nombre Fuente],
 LTRIM(UPPER(Nombre)) AS Mayusculas,
 ...
FROM clientes;
```

Insertar datos a partir de una consulta. Es el patrón más usado en ETL: `INSERT INTO destino SELECT ... FROM origen`. Mucho más eficiente que hacer el SELECT primero, traer los datos a la aplicación, y luego hacer INSERTs uno por uno.

---

### 12.12 Funciones de Fecha

```sql
use NORTHWND;
GO
SELECT
 OrderDate,
 GETDATE() AS [Fecha Actual],
 DATEADD(Day, 10, OrderDate) AS [FechaMas10Dias],
 DATEPART(quarter, OrderDate) AS [Trimestre],
 DATEPART(MONTH, OrderDate) AS [MesConNumero],
 DATENAME(month, OrderDate) AS [MesConNombre],
 DATENAME(WEEKDAY, OrderDate) AS [NombreDia],
 DATEDIFF(DAY, OrderDate, GETDATE()) AS [DiasTranscurridos],
 DATEDIFF(YEAR, OrderDate, GETDATE()) AS [AniosTranscurridos],
 DATEDIFF(Year, '2003-07-13', GETDATE()) AS [EdadPersona1],
 DATEDIFF(Year, '1983-07-13', GETDATE()) AS [EdadPersona2]
FROM Orders;
```

| Función | Descripción | Ejemplo |
|---|---|---|
| `GETDATE()` | Fecha y hora actual del servidor | `2026-03-18 14:30:00` |
| `DATEADD(parte, n, fecha)` | Añade n unidades a la fecha | `DATEADD(Day, 10, '2024-01-01')` → `'2024-01-11'` |
| `DATEPART(parte, fecha)` | Extrae una parte como número | `DATEPART(month, '2024-07-04')` → `7` |
| `DATENAME(parte, fecha)` | Extrae una parte como nombre | `DATENAME(month, '2024-07-04')` → `'July'` |
| `DATEDIFF(parte, fecha1, fecha2)` | Diferencia entre fechas | `DATEDIFF(day, '2024-01-01', '2024-02-01')` → `31` |

**Partes de fecha comunes:** `Year`, `Quarter`, `Month`, `Day`, `Hour`, `Minute`, `Second`, `Weekday`, `Week`

**Truco para calcular edad:**
```sql
DATEDIFF(Year, '1983-07-13', GETDATE())
```
Esto calcula cuántos años han transcurrido desde la fecha de nacimiento. No es 100% preciso (puede estar desfasado por un año dependiendo del día del año), pero para análisis básico es suficiente.

El uso de NORTHWND en este ejercicio muestra cómo aplicar estas funciones a datos reales: calcular cuántos días hace que se hizo un pedido, en qué trimestre se hizo, etc. Estas son exactamente las transformaciones que se usarían para poblar `dim_date`.

---

### 12.13 Manejo de Valores Nulos

```sql
CREATE TABLE Employees (
   EmployeeID     INT PRIMARY KEY,
   FirstName      NVARCHAR(50),
   LastName       NVARCHAR(50),
   Email          NVARCHAR(100),
   SecondaryEmail NVARCHAR(100),
   Phone          NVARCHAR(20),
   Salary         DECIMAL(10,2),
   Bonus          DECIMAL(10,2)
);
```

Tabla de práctica con campos nullable, datos de empleados ficticios con nulos intencionales:
- Empleado 2: no tiene Email pero sí SecondaryEmail, no tiene Phone
- Empleado 3: no tiene ningún Email, Salary = 0
- Empleado 4: no tiene SecondaryEmail, no tiene Phone

**Ejercicio 1 — ISNULL:**
```sql
SELECT CONCAT(FirstName, ' ', LastName) AS [FULLNAME],
       ISNULL(phone, 'No Disponible') AS [PHONE]
FROM Employees;
```

`ISNULL(expresión, valor_si_nulo)` — si `phone` es NULL, devuelve 'No Disponible'. Solo acepta dos argumentos.

**Ejercicio 2 — COALESCE:**
```sql
SELECT CONCAT(FirstName, ' ', LastName) AS [Nombre Completo],
       COALESCE(email, secondaryEmail, 'Sin Correo') AS Correo_Contacto
FROM Employees;
```

`COALESCE(expr1, expr2, expr3, ...)` — devuelve el primer valor no-NULL de la lista. Más flexible que ISNULL porque acepta múltiples alternativas. Aquí: si tiene email primario lo usa, si no tiene pero sí secundario lo usa, si no tiene ninguno devuelve 'Sin Correo'.

**Ejercicio 3 — NULLIF:**
```sql
SELECT CONCAT(FirstName, ' ', LastName) AS [NombreCompleto],
       Salary,
       NULLIF(salary, 0) AS [SalarioEvaluable]
FROM Employees;
```

`NULLIF(expr1, expr2)` — devuelve NULL si los dos valores son iguales, o expr1 si son diferentes. Útil para convertir valores "especiales" (como 0 en un campo numérico) en NULL para que las funciones de agregación los ignoren.

**Uso práctico — evitar división por cero:**
```sql
SELECT FirstName,
       Bonus,
       (Bonus / NULLIF(salary, 0)) AS Bonus_Salario
FROM Employees;
```

Sin `NULLIF`: si Salary = 0, `Bonus / 0` lanza un error de división por cero.
Con `NULLIF(salary, 0)`: si Salary = 0, `NULLIF` devuelve NULL, y `Bonus / NULL` = NULL (no hay error). El empleado con Salary=0 aparece con NULL en la columna Bonus_Salario en vez de causar un error.

---

### 12.14 Expresiones CASE

**CASE simple:**
```sql
SELECT
     UPPER(CONCAT(FirstName, ' ', LastName)) AS [FULLNAME],
     ROUND(salary, 2) AS [SALARIO],
     CASE
        WHEN ROUND(salary, 2) >= 10000 THEN 'Alto'
        WHEN ROUND(salary, 2) BETWEEN 5000 AND 9999 THEN 'Medio'
        ELSE 'Bajo'
     END AS [Nivel Salarial]
FROM Employees;
```

`CASE WHEN condición THEN resultado ... ELSE resultado_default END` — permite crear lógica condicional dentro de un SELECT. Evalúa las condiciones en orden y devuelve el resultado de la primera que se cumpla. Si ninguna se cumple, devuelve el valor del `ELSE` (que es NULL si no se especifica).

`ROUND(salary, 2)` — redondea a 2 decimales. No cambia el resultado aquí porque el salario ya tiene 2 decimales, pero demuestra el uso de la función.

**CASE con múltiples funciones combinadas (usando NORTHWND):**
```sql
SELECT UPPER(c.CompanyName) AS [Nombre Cliente],
       ISNULL(c.Phone, 'No Disponible') AS [Telefono],
       p.ProductName,
       CASE
           WHEN DATEDIFF(day, o.OrderDate, GETDATE()) < 30 THEN 'Reciente'
           ELSE 'Antiguo'
       END AS [Estado del Pedido]
FROM ( SELECT customerId, companyName, Phone FROM Customers) AS c
INNER JOIN ( SELECT OrderID, CustomerID, OrderDate FROM Orders) AS o
    ON c.CustomerID = o.CustomerID
INNER JOIN ( SELECT ProductID, OrderID FROM [Order Details]) AS od
    ON o.OrderID = od.OrderID
INNER JOIN ( SELECT ProductID, ProductName FROM Products) AS p
    ON p.ProductID = od.ProductID;
```

Este ejercicio combina:
- `UPPER()` para formatear nombres
- `ISNULL()` para manejar teléfonos nulos
- `DATEDIFF()` para calcular días transcurridos
- `CASE WHEN` para categorizar el pedido como Reciente/Antiguo
- **Subqueries en el FROM** — cada tabla se envuelve en una subconsulta que selecciona solo las columnas necesarias. Esto es una técnica para ser explícito sobre qué columnas se usan de cada tabla, aunque no es necesaria la subconsulta en sí.

**`SELECT ... INTO tablaformateada`** — el mismo SELECT anterior con `INTO tablaformateada` crea una tabla física con los resultados. Esta tabla se usa luego para crear una vista.

---

### 12.15 Vistas

```sql
CREATE OR ALTER VIEW v_pedidosAntiguos
AS
SELECT [Nombre Cliente], ProductName, [Estado del Pedido]
FROM tablaformateada
WHERE [Estado del Pedido] = 'Antiguo';

SELECT * FROM v_pedidosAntiguos;
```

Una **vista** es una consulta guardada que se puede usar como si fuera una tabla. Ventajas:
- **Reutilización**: en lugar de escribir el WHERE y el SELECT complejo cada vez, se consulta la vista
- **Abstracción**: los usuarios de la vista no necesitan saber la estructura interna
- **Seguridad**: se puede dar acceso a una vista sin dar acceso a las tablas subyacentes

`CREATE OR ALTER VIEW` — crea o reemplaza la vista, igual que con los SPs.

La vista `v_pedidosAntiguos` filtra solo los pedidos con estado 'Antiguo'. Nótese que como todos los pedidos de Northwind tienen fechas de los años 90-2000, todos serán 'Antiguo' cuando se ejecute hoy (2026). Esto es un efecto del dataset de práctica.

---

*Documentación generada a partir del análisis completo del repositorio. Última actualización: marzo 2026.*
