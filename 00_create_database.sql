/* =========================================================================
   Creacion de la base de datos. Se ejecuta antes que 01_create_table.sql,
   que arranca directamente con USE [COSTO_LABOR] y falla si no existe.

   La intercalacion se toma de BD_SPRING (o del servidor, si BD_SPRING no
   existe). Los procedimientos cruzan textos de COSTO_LABOR con columnas de
   BD_SPRING y con tablas temporales, que usan la intercalacion del servidor;
   si difieren, SQL Server corta la consulta con el error 468 (conflicto de
   intercalacion). En AMSAC ambas son SQL_Latin1_General_CP1_CI_AS.

   Ademas debe ser CI (Case Insensitive): el sistema compara nombres sin
   distinguir mayusculas de minusculas -por ejemplo, el indice unico
   UX_TMD_PARAMETRO_ATRIBUTO_NOMBRE y la validacion de atributos repetidos de
   la HU-004-, y con una intercalacion CS esa regla dejaria pasar duplicados.
   ========================================================================= */

IF DB_ID('COSTO_LABOR') IS NULL
BEGIN
    DECLARE @intercalacion sysname = COALESCE(
        CONVERT(sysname, DATABASEPROPERTYEX('BD_SPRING', 'Collation')),
        CONVERT(sysname, SERVERPROPERTY('Collation')));

    IF @intercalacion NOT LIKE '%[_]CI[_]%'
        THROW 50000, 'La intercalacion de BD_SPRING/servidor no es CI: revisar antes de crear COSTO_LABOR.', 1;

    EXEC (N'CREATE DATABASE COSTO_LABOR COLLATE ' + @intercalacion);
END
GO
