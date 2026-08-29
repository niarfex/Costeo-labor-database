/* =========================================================================
   Creacion de la base de datos. Se ejecuta antes que 01_create_table.sql,
   que arranca directamente con USE [COSTO_LABOR] y falla si no existe.

   La intercalacion se fija de forma explicita y no se deja al valor por
   defecto de cada instalacion de SQL Server. El sistema compara nombres sin
   distinguir mayusculas de minusculas -por ejemplo, el indice unico
   UX_TMD_PARAMETRO_ATRIBUTO_NOMBRE y la validacion de atributos repetidos de
   la HU-004-, y con una intercalacion CS esa regla dejaria pasar duplicados.
   El sufijo _CI_AS significa Case Insensitive y Accent Sensitive.
   ========================================================================= */

IF DB_ID('COSTO_LABOR') IS NULL
    CREATE DATABASE COSTO_LABOR COLLATE Modern_Spanish_CI_AS;
GO
