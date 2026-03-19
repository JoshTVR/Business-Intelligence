# INTELIGENCIA DE NEGOCIOS - Proyecto Northwind

Proyecto completo de **Business Intelligence** construido sobre la base de datos Northwind, siguiendo la **metodología Kimball** (modelado dimensional en estrella). Cubre desde la configuración del entorno hasta la visualización final en Power BI.

> Para la documentación técnica completa ver [DOCS.md](DOCS.md)

![Inteligencia de Negocios](./img/BI.jpg)

---

## ¿Qué hace este proyecto?

Toma la base de datos **NORTHWND** (base de datos de ventas de ejemplo de Microsoft) como fuente y construye un **Datamart de Ventas** que permite analizar ventas por cliente, producto, empleado, transportista y fecha.

```
[NORTHWND]  ──►  [Load_Northwind]  ──►  [Stage_Northwind]  ──►  [Datamart_Northwind]  ──►  [Power BI]
  Fuente          Capa de aterrizaje      Transformación          Modelo estrella           Dashboard
```

---

## Herramientas

| Categoría | Herramienta |
|---|---|
| Base de Datos | Microsoft SQL Server 2022 |
| Base de Datos | PostgreSQL 15 |
| ETL | SQL Server Integration Services (SSIS) |
| Visualización | Microsoft Power BI |
| Contenedores | Docker Desktop / Docker Compose |

---

## Estructura del Repositorio

```
inteligenciax/
├── ArquitecturaDM/               # Scripts SQL: creación de BDs, tablas y carga ETL
│   ├── init_database.sql         # Crea las 4 bases de datos
│   ├── DATAMART_NORTHWIND/       # DDL del modelo dimensional (dims + fact)
│   ├── Carga_Load_Northwind/     # Scripts de referencia para la capa Load
│   ├── Preparativo_datamart/     # Crea la BD de metadata ETL
│   └── scriptfactventas.sql      # Pipeline ETL completo (DDL + DML)
├── ProyectoETL_DM_Kimball/       # Paquetes SSIS
│   ├── Stage_Nortwind/           # Proyecto 1: carga a Stage (versión inicial)
│   ├── Datamart_Nortwind/        # Proyecto 2: carga al Datamart (versión media)
│   └── DatamartNorthwind/        # Proyecto 3: pipeline completo (versión final)
├── PowerBi/                      # Reporte Power BI (.pbix)
├── sgbd-docker/                  # Docker Compose para SQL Server y PostgreSQL
│   ├── sqlserver/
│   └── postgres/
└── topicosSQL/                   # Material de estudio T-SQL (independiente del proyecto)
```

---

## Inicio Rápido

**1. Levantar SQL Server**
```bash
docker volume create sqlserver-volume
docker compose -f sgbd-docker/sqlserver/docker-compose.yaml up -d
```

**2. Ejecutar los scripts en orden**
```
1. ArquitecturaDM/init_database.sql
2. ArquitecturaDM/Preparativo_datamart/Script_Northwind_Metadata.sql
3. ArquitecturaDM/DATAMART_NORTHWIND/init_datamart_northwind.sql
4. ArquitecturaDM/scriptfactventas.sql  (secciones DDL)
```

**3. Correr los paquetes SSIS**
Abrir el proyecto `ProyectoETL_DM_Kimball/DatamartNorthwind/` en Visual Studio y ejecutar `CargaMaster.dtsx`.

**4. Abrir el reporte**
Abrir `PowerBi/Visualizacion_Datamart_Nortwind.pbix` en Power BI Desktop.
