/* =========================================================================
   ATENCION: ESTE SCRIPT BORRA DATOS.

   Elimina todas las tablas del sistema. Se separo de 01_create_table.sql
   porque alli se ejecutaba siempre: bastaba con volver a correr el script
   de creacion para perder los datos de Desarrollo o Calidad.

   Ejecutarlo solo de forma deliberada, para rehacer una base desde cero.
   El nombre empieza con guion bajo para que quede fuera de la secuencia
   numerada 01..99 y no se corra por accidente al aplicar los scripts.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* =========================================================================
   0. LIMPIEZA PREVIA DE OBJETOS EXISTENTES (Orden por dependencias FK)
   ========================================================================= */

-- 0.1 Eliminar Tablas del Esquema PROCESO
DROP TABLE IF EXISTS proceso.TMD_DISTRIBUCION_COMPENSACION;
DROP TABLE IF EXISTS proceso.TMD_GASTO_PERSONAL;
GO

-- 0.2 Eliminar Tablas del Esquema REGISTRO (Hijas primero, luego padres)
DROP TABLE IF EXISTS registro.TMD_DISTRIBUCION_GIP_DETALLE;
DROP TABLE IF EXISTS registro.TMD_DISTRIBUCION_GIP;
DROP TABLE IF EXISTS registro.TMD_REGISTRO_HORAMES_ACTTAREA;
DROP TABLE IF EXISTS registro.TMD_REGISTRO_HORAMES_ACT;
DROP TABLE IF EXISTS registro.TMD_REGISTRO_HORAMES_VALIDACION;
DROP TABLE IF EXISTS registro.TMD_REGISTRO_HORAMES;
DROP TABLE IF EXISTS registro.TMD_REGISTRO_HORADIA_ACTTAREA;
DROP TABLE IF EXISTS registro.TMD_REGISTRO_HORADIA_ACT;
DROP TABLE IF EXISTS registro.TMD_REGISTRO_HORADIA_VALIDACION;
DROP TABLE IF EXISTS registro.TMD_REGISTRO_HORADIA;
DROP TABLE IF EXISTS registro.TMD_PERIODO_EMPLEADO;
DROP TABLE IF EXISTS registro.TMD_PERIODO_PROYECTO;
DROP TABLE IF EXISTS registro.TMC_PERIODO;
DROP TABLE IF EXISTS registro.TMD_PARAMETRO_ATRIBUTO;
DROP TABLE IF EXISTS registro.TMC_PARAMETRO;
DROP TABLE IF EXISTS registro.TG_TIPO_DATO;
GO

-- 0.2 Eliminar Tablas del Esquema GENERAL
DROP TABLE IF EXISTS general.TG_AUDITORIA;
DROP TABLE IF EXISTS general.TG_CONFIGURACION;
GO

