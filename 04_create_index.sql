/* Indices unicos de negocio y de apoyo - HU-004 */

USE [COSTO_LABOR];
GO

-- Opciones exigidas por SQL Server para crear indices filtrados
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- Un solo periodo vigente por parametrizacion; el filtro permite reusar un periodo eliminado logicamente
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_TMC_PARAMETRO_PERIODO'
                 AND object_id = OBJECT_ID('registro.TMC_PARAMETRO'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMC_PARAMETRO_PERIODO
        ON registro.TMC_PARAMETRO (numAnio ASC, numMes ASC)
        WHERE flgEstado = 1;
GO

-- Nombre de atributo unico dentro de una misma parametrizacion
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_TMD_PARAMETRO_ATRIBUTO_NOMBRE'
                 AND object_id = OBJECT_ID('registro.TMD_PARAMETRO_ATRIBUTO'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_PARAMETRO_ATRIBUTO_NOMBRE
        ON registro.TMD_PARAMETRO_ATRIBUTO (ideParametro ASC, nomAtributo ASC)
        WHERE flgEstado = 1;
GO

-- Apoyo al listado paginado ordenado por periodo descendente
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMC_PARAMETRO_LISTADO'
                 AND object_id = OBJECT_ID('registro.TMC_PARAMETRO'))
    CREATE NONCLUSTERED INDEX IX_TMC_PARAMETRO_LISTADO
        ON registro.TMC_PARAMETRO (flgEstado ASC, numAnio DESC, numMes DESC);
GO

-- Codigo unico para el combo Tipo de dato
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_TG_TIPO_DATO_CODIGO'
                 AND object_id = OBJECT_ID('registro.TG_TIPO_DATO'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TG_TIPO_DATO_CODIGO
        ON registro.TG_TIPO_DATO (codTipoDato ASC)
        WHERE flgEstado = 1;
GO
