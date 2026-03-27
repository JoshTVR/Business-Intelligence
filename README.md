<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0f766e,50:0891b2,100:2563eb&height=180&section=header&text=Business%20Intelligence&fontSize=46&fontAlignY=38&animation=fadeIn&desc=Kimball%20DM%20·%20ETL%20Pipeline%20·%20Power%20BI%20·%20SQL%20Server%20+%20PostgreSQL&descAlignY=60&descSize=14&fontColor=ffffff"/>

<br/>

[![SQL Server](https://img.shields.io/badge/SQL%20Server-T--SQL-CC2927?style=for-the-badge&logo=microsoftsqlserver&logoColor=white)](https://learn.microsoft.com/en-us/sql/sql-server)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Docker-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://postgresql.org)
[![Power BI](https://img.shields.io/badge/Power%20BI-Dashboards-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)](https://powerbi.microsoft.com)
[![Docker](https://img.shields.io/badge/Docker-Containers-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docker.com)

</div>

---

## About

A complete **Business Intelligence solution** built on the classic Northwind database.

This project implements dimensional modeling using **Kimball's methodology** — from raw OLTP data to a full data warehouse with star schema, ETL pipeline, and interactive Power BI dashboards. Built as an end-to-end BI project covering architecture, transformation, and visualization.

---

## What's Inside

| Folder                    | Description                                         |
| ------------------------- | --------------------------------------------------- |
| `ProyectoETL_DM_Kimball/` | Full ETL pipeline + dimensional model (star schema) |
| `PowerBi/`                | Power BI dashboard files (.pbix)                    |
| `ArquitecturaDM/`         | Data mart architecture diagrams                     |
| `topicosSQL/`             | T-SQL examples and advanced topics                  |
| `sgbd-docker/`            | Docker setup for SQL Server + PostgreSQL            |
| `DOCS.md`                 | Full technical documentation                        |

---

## Tech Stack

<div align="center">

[![SQL Server](https://skillicons.dev/icons?i=sqlserver)](https://learn.microsoft.com/en-us/sql/sql-server)
[![PostgreSQL](https://skillicons.dev/icons?i=postgres)](https://postgresql.org)
[![Docker](https://skillicons.dev/icons?i=docker)](https://docker.com)

</div>

**Additional tools:** Power BI Desktop · SQL Server Integration Services (SSIS) · Azure Data Studio

---

## Architecture

```
OLTP Source (Northwind)
        ↓
   ETL Pipeline (SSIS / T-SQL)
        ↓
  Data Warehouse (Star Schema / Kimball)
   ├── Fact tables
   └── Dimension tables (DimCliente, DimProducto, DimTiempo…)
        ↓
  Power BI Dashboards
```

---

## Local Setup

### Run databases with Docker

```bash
git clone https://github.com/JoshTVR/Business-Intelligence.git
cd Business-Intelligence/sgbd-docker
docker-compose up -d
```

Then follow the setup guide in `instalacion-postgres-docker.md`.

---

<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:2563eb,50:0891b2,100:0f766e&height=100&section=footer&animation=fadeIn"/>

</div>
