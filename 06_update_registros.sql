/* Correccion de tildes de la semilla cargada por 02_insert_registros.sql */
/* Se arma el texto con NCHAR para no depender de la codificacion con que se guarde este archivo */

USE [COSTO_LABOR];
GO

/* Obligatorio: las tablas con indices filtrados rechazan cualquier DML y
   cualquier procedimiento compilado sin estas opciones. SQL Server las
   guarda al crear el objeto, asi que si el despliegue se hace con una
   herramienta que no las active, el procedimiento se crea bien pero
   falla al ejecutarse. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- NCHAR(218) = U, NCHAR(243) = o
UPDATE registro.TG_TIPO_DATO
SET nomTipodato = CONCAT('N', NCHAR(218), 'MERO')
WHERE codTipoDato = 'NUMERO';
GO

UPDATE general.TG_CONFIGURACION
SET txtDescripcion = CONCAT('Tiempo de bloqueo de inicio de sesi', NCHAR(243), 'n en minutos')
WHERE txtCodigoConfiguracion = 'TIEMPO_BLOQUEO_INICIO_SESION';
GO

