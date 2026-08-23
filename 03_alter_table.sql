/* Correcciones estructurales sobre 01_create_table.sql - HU-004 */

USE [COSTO_LABOR];
GO

-- Valores por defecto, mismo criterio ya aplicado en general.TG_CONFIGURACION
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TG_TIPO_DATO_fecCreacion')
    ALTER TABLE registro.TG_TIPO_DATO
        ADD CONSTRAINT DF_TG_TIPO_DATO_fecCreacion DEFAULT (GETDATE()) FOR fecCreacion;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TMC_PARAMETRO_fecCreacion')
    ALTER TABLE registro.TMC_PARAMETRO
        ADD CONSTRAINT DF_TMC_PARAMETRO_fecCreacion DEFAULT (GETDATE()) FOR fecCreacion;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TMC_PARAMETRO_flgEstado')
    ALTER TABLE registro.TMC_PARAMETRO
        ADD CONSTRAINT DF_TMC_PARAMETRO_flgEstado DEFAULT (1) FOR flgEstado;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TMD_PARAMETRO_ATRIBUTO_fecCreacion')
    ALTER TABLE registro.TMD_PARAMETRO_ATRIBUTO
        ADD CONSTRAINT DF_TMD_PARAMETRO_ATRIBUTO_fecCreacion DEFAULT (GETDATE()) FOR fecCreacion;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TMD_PARAMETRO_ATRIBUTO_flgEstado')
    ALTER TABLE registro.TMD_PARAMETRO_ATRIBUTO
        ADD CONSTRAINT DF_TMD_PARAMETRO_ATRIBUTO_flgEstado DEFAULT (1) FOR flgEstado;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_TMC_PARAMETRO_MES')
    ALTER TABLE registro.TMC_PARAMETRO
        ADD CONSTRAINT CK_TMC_PARAMETRO_MES CHECK (numMes BETWEEN 1 AND 12);
GO
