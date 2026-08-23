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

/* =========================================================================
   1. CREACIÓN CONDICIONAL DE ESQUEMAS
   ========================================================================= */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'general')
    EXEC('CREATE SCHEMA general');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'registro')
    EXEC('CREATE SCHEMA registro');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'proceso')
    EXEC('CREATE SCHEMA proceso');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'seguridad')
    EXEC('CREATE SCHEMA seguridad');
GO

/* =========================================================================
   2. ESQUEMA: general
   ========================================================================= */

-- general.TG_CONFIGURACION
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[general].[TG_CONFIGURACION]') AND type in (N'U'))
BEGIN
    CREATE TABLE general.TG_CONFIGURACION(
        ideConfiguracion bigint IDENTITY(1,1) NOT NULL,
        txtCodigoConfiguracion varchar(30) NOT NULL,
        numParametro int NULL,
        txtParametro varchar(100) NULL,
        numMinimo int NULL,
        numMaximo int NULL,
        txtDescripcion varchar(200) NULL,
        flgEstado int NULL CONSTRAINT DF_TG_CONFIGURACION_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TG_CONFIGURACION_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TG_CONFIGURACION PRIMARY KEY CLUSTERED (ideConfiguracion ASC),
        CONSTRAINT UQ_TG_CONFIGURACION_CODIGO UNIQUE (txtCodigoConfiguracion)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Tabla maestra de configuraciones globales y parámetros del sistema', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único de la configuración', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'ideConfiguracion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código mnemónico único de la configuración', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'txtCodigoConfiguracion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Valor numérico del parámetro', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'numParametro';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Valor de texto del parámetro', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'txtParametro';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Límite numérico mínimo permitido', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'numMinimo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Límite numérico máximo permitido', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'numMaximo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Descripción funcional de la configuración', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'txtDescripcion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado del registro (1: Vigente/Activo, 0: Eliminado/Inactivo)', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha y hora de creación del registro', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario que creó el registro', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha y hora de la última modificación', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario que realizó la última modificación', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_CONFIGURACION', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

-- general.TG_AUDITORIA
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[general].[TG_AUDITORIA]') AND type in (N'U'))
BEGIN
    CREATE TABLE general.TG_AUDITORIA(
        ideAuditoria bigint IDENTITY(1,1) NOT NULL,
        txtUsuario varchar(30) NULL,
        txtOpcion varchar(50) NULL,
        txtEvento text NULL, 
        txtResultado varchar(10) NULL,
        txtDireccionIp varchar(25) NULL,
        ideRegistroAsociado bigint NULL,
        fecha_evento datetime NULL CONSTRAINT DF_TG_AUDITORIA_fecha_evento DEFAULT (GETDATE()),
        CONSTRAINT PK_TG_AUDITORIA PRIMARY KEY CLUSTERED (ideAuditoria ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Pista de auditoría para registro de eventos y seguridad', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del registro de auditoría', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA', @level2type=N'COLUMN',@level2name=N'ideAuditoria';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador del usuario que ejecutó la acción', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA', @level2type=N'COLUMN',@level2name=N'txtUsuario';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Módulo u opción del sistema involucrada', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA', @level2type=N'COLUMN',@level2name=N'txtOpcion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Detalle o payload del evento auditado', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA', @level2type=N'COLUMN',@level2name=N'txtEvento';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Resultado de la operación (EXITOSO / FALLIDO)', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA', @level2type=N'COLUMN',@level2name=N'txtResultado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Dirección IP del cliente', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA', @level2type=N'COLUMN',@level2name=N'txtDireccionIp';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID del registro modificado o consultado', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA', @level2type=N'COLUMN',@level2name=N'ideRegistroAsociado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Marca temporal del evento', @level0type=N'SCHEMA',@level0name=N'general', @level1type=N'TABLE',@level1name=N'TG_AUDITORIA', @level2type=N'COLUMN',@level2name=N'fecha_evento';
END
GO

/* =========================================================================
   3. ESQUEMA: registro
   ========================================================================= */

-- registro.TG_TIPO_DATO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TG_TIPO_DATO]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TG_TIPO_DATO(
        ideTipoDato bigint IDENTITY(1,1) NOT NULL,
        codTipoDato varchar(30) NULL,
        nomTipodato varchar(30) NULL,
        flgEstado int NULL CONSTRAINT DF_TG_TIPO_DATO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TG_TIPO_DATO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TG_TIPO_DATO PRIMARY KEY CLUSTERED (ideTipoDato ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Catálogo de tipos de datos dinámicos permitidos para atributos', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del tipo de dato', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO', @level2type=N'COLUMN',@level2name=N'ideTipoDato';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código técnico (VARCHAR, NUMBER, DATE, etc.)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO', @level2type=N'COLUMN',@level2name=N'codTipoDato';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre descriptivo del tipo de dato', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO', @level2type=N'COLUMN',@level2name=N'nomTipodato';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado del registro (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TG_TIPO_DATO', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

-- registro.TMC_PARAMETRO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMC_PARAMETRO]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMC_PARAMETRO(
        ideParametro bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        flgRegActividad int NULL,
        flgRegComentarioxActividad int NULL,
        flgRegTareaxActividad int NULL,
        flgRegObservacionxTarea int NULL,
        flgRegObservacionxProyecto int NULL,
        flgRegObservacionxPeriodo int NULL,
        flgRegOtrosAtributos int NULL,
        flgEstado int NULL CONSTRAINT DF_TMC_PARAMETRO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMC_PARAMETRO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMC_PARAMETRO PRIMARY KEY CLUSTERED (ideParametro ASC),
        CONSTRAINT UQ_TMC_PARAMETRO_ANIO_MES UNIQUE (numAnio, numMes)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Parámetros y flags de configuración de captura por periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del registro de parámetro', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'ideParametro';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Año de vigencia del parámetro', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'numAnio';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Mes de vigencia del parámetro', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'numMes';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Habilita registro por actividad (1: Sí, 0: No)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'flgRegActividad';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Habilita comentarios por actividad (1: Sí, 0: No)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'flgRegComentarioxActividad';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Habilita tareas por actividad (1: Sí, 0: No)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'flgRegTareaxActividad';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Habilita observaciones en tareas (1: Sí, 0: No)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'flgRegObservacionxTarea';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Habilita observaciones por proyecto (1: Sí, 0: No)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'flgRegObservacionxProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Habilita observaciones globales por periodo (1: Sí, 0: No)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'flgRegObservacionxPeriodo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Habilita atributos dinámicos adicionales (1: Sí, 0: No)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'flgRegOtrosAtributos';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado del registro (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PARAMETRO', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

-- registro.TMD_PARAMETRO_ATRIBUTO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_PARAMETRO_ATRIBUTO]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_PARAMETRO_ATRIBUTO(
        ideParametroAtributo bigint IDENTITY(1,1) NOT NULL,
        ideParametro bigint NULL,
        nomAtributo varchar(50) NULL,
        ideTipoDato bigint NULL,
        numTamanio int NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_PARAMETRO_ATRIBUTO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_PARAMETRO_ATRIBUTO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_PARAMETRO_ATRIBUTO PRIMARY KEY CLUSTERED (ideParametroAtributo ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Detalle de atributos dinámicos configurables', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del atributo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'ideParametroAtributo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre del atributo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'nomAtributo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de referencia al tipo de dato', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'ideTipoDato';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Longitud o tamaño del atributo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'numTamanio';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PARAMETRO_ATRIBUTO', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_PARAMETRO_ATRIBUTO_PARAMETRO]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_PARAMETRO_ATRIBUTO]'))
BEGIN
    ALTER TABLE registro.TMD_PARAMETRO_ATRIBUTO 
    ADD CONSTRAINT FK_PARAMETRO_ATRIBUTO_PARAMETRO FOREIGN KEY(ideParametro)
    REFERENCES registro.TMC_PARAMETRO(ideParametro);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_PARAMETRO_ATRIBUTO_IDE]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_PARAMETRO_ATRIBUTO]'))
BEGIN
    ALTER TABLE registro.TMD_PARAMETRO_ATRIBUTO 
    ADD CONSTRAINT FK_PARAMETRO_ATRIBUTO_IDE FOREIGN KEY(ideTipoDato)
    REFERENCES registro.TG_TIPO_DATO(ideTipoDato);
END
GO

-- registro.TMC_PERIODO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMC_PERIODO]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMC_PERIODO(
        idePeriodo bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        fecProcesamiento datetime NULL,
        txtUsuarioProcesamiento varchar(30) NULL,
        flgEstado int NULL CONSTRAINT DF_TMC_PERIODO_flgEstado DEFAULT (1), -- 2=Cerrado, 1=Activo, 0=Inactivo
        fecCreacion datetime NULL CONSTRAINT DF_TMC_PERIODO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMC_PERIODO PRIMARY KEY CLUSTERED (idePeriodo ASC),
        CONSTRAINT UQ_TMC_PERIODO_ANIO_MES UNIQUE (numAnio, numMes)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Maestro de periodos mensuales de costeo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'idePeriodo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Año del periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'numAnio';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Mes del periodo (1 al 12)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'numMes';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha y hora de ejecución del procesamiento', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'fecProcesamiento';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario que procesó el periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'txtUsuarioProcesamiento';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado del periodo (2: Cerrado, 1: Activo/Abierto, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMC_PERIODO', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

-- registro.TMD_PERIODO_PROYECTO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_PERIODO_PROYECTO]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_PERIODO_PROYECTO(
        idePeriodoProyecto bigint IDENTITY(1,1) NOT NULL,
        idePeriodo bigint NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        codProyecto varchar(30) NOT NULL,
        nomProyecto varchar(200) NOT NULL,
        ideEmpleado bigint NOT NULL,
        nomEmpleado varchar(200) NOT NULL,
        txtObservaciones varchar(250) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_PERIODO_PROYECTO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_PERIODO_PROYECTO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_PERIODO_PROYECTO PRIMARY KEY CLUSTERED (idePeriodoProyecto ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Asignación de proyectos y empleados habilitados por periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del registro', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'idePeriodoProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Referencia al periodo principal', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'idePeriodo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Año del periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'numAnio';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Mes del periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'numMes';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código del proyecto', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'codProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre completo del proyecto', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'nomProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador del empleado asignado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'ideEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre del empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'nomEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Observaciones del registro', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'txtObservaciones';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_PROYECTO', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_PERIODO_PROYECTO_PERIODO]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_PERIODO_PROYECTO]'))
BEGIN
    ALTER TABLE registro.TMD_PERIODO_PROYECTO 
    ADD CONSTRAINT FK_TMD_PERIODO_PROYECTO_PERIODO FOREIGN KEY(idePeriodo)
    REFERENCES registro.TMC_PERIODO(idePeriodo);
END
GO

-- registro.TMD_PERIODO_EMPLEADO
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_PERIODO_EMPLEADO]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_PERIODO_EMPLEADO(
        idePeriodoEmpleado bigint IDENTITY(1,1) NOT NULL,
        idePeriodo bigint NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        ideEmpleado bigint NOT NULL,
        nomEmpleado varchar(200) NOT NULL,
        txtObservaciones varchar(250) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_PERIODO_EMPLEADO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_PERIODO_EMPLEADO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_PERIODO_EMPLEADO PRIMARY KEY CLUSTERED (idePeriodoEmpleado ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Maestro de empleados habilitados para costeo por periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del registro', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'idePeriodoEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Referencia al periodo principal', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'idePeriodo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Año del periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'numAnio';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Mes del periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'numMes';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID del empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'ideEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre completo del empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'nomEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Observaciones registradas', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'txtObservaciones';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_PERIODO_EMPLEADO', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_PERIODO_EMPLEADO_PERIODO]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_PERIODO_EMPLEADO]'))
BEGIN
    ALTER TABLE registro.TMD_PERIODO_EMPLEADO 
    ADD CONSTRAINT FK_TMD_PERIODO_EMPLEADO_PERIODO FOREIGN KEY(idePeriodo)
    REFERENCES registro.TMC_PERIODO(idePeriodo);
END
GO

-- registro.TMD_REGISTRO_HORADIA
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORADIA]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_REGISTRO_HORADIA(
        ideRegistroHoradia bigint IDENTITY(1,1) NOT NULL,
        idePeriodo bigint NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        numDia int NOT NULL,
        codProyecto varchar(30) NOT NULL,
        nomProyecto varchar(200) NOT NULL,
        ideEmpleado bigint NOT NULL,
        nomEmpleado varchar(200) NOT NULL,
        fecLabor date NOT NULL,	
        numHoras decimal(5,2) NOT NULL,
        txtJsonAtributos nvarchar(max) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_REGISTRO_HORADIA_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_HORADIA_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_REGISTRO_HORADIA PRIMARY KEY CLUSTERED (ideRegistroHoradia ASC),
        CONSTRAINT CK_TMD_REGISTRO_HORADIA_JSON CHECK (ISJSON(txtJsonAtributos) = 1 OR txtJsonAtributos IS NULL)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Cabecera del registro diario de horas laboradas por proyecto y empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del registro de horas por día', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'ideRegistroHoradia';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de referencia al periodo mensual', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'idePeriodo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Año de labor', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'numAnio';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Mes de labor', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'numMes';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Día del mes de labor', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'numDia';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código del proyecto asignado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'codProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre descriptivo del proyecto', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'nomProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID del empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'ideEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre completo del empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'nomEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha exacta de la labor', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'fecLabor';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Cantidad de horas registradas', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'numHoras';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Atributos dinámicos en formato JSON', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'txtJsonAtributos';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_REGISTRO_HORADIA_PERIODO]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORADIA]'))
BEGIN
    ALTER TABLE registro.TMD_REGISTRO_HORADIA 
    ADD CONSTRAINT FK_TMD_REGISTRO_HORADIA_PERIODO FOREIGN KEY(idePeriodo)
    REFERENCES registro.TMC_PERIODO(idePeriodo);
END
GO

-- registro.TMD_REGISTRO_HORADIA_VALIDACION
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORADIA_VALIDACION]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_REGISTRO_HORADIA_VALIDACION(
        ideRegistroHoradiaValidacion bigint IDENTITY(1,1) NOT NULL,
        ideRegistroHoradia bigint NULL,
        flgConforme int NULL, -- 1=Conforme o 0=Observado
        flgSubsanado int NULL, -- 1=Subsanado o 0=Pendiente
        txtComentario varchar(250) NULL,
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_HORADIA_VALIDACION_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_REGISTRO_HORADIA_VALIDACION PRIMARY KEY CLUSTERED (ideRegistroHoradiaValidacion ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Control de conformidad y subsanación del registro diario de horas', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único de la validación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'ideRegistroHoradiaValidacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID del registro diario asociado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'ideRegistroHoradia';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado de conformidad (1: Conforme, 0: Observado)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'flgConforme';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado de subsanación (1: Subsanado, 0: Pendiente)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'flgSubsanado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Comentario u observación del validador', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'txtComentario';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario que realizó la validación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_VALIDACION', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_REGISTRO_HORADIA_VALIDACION_HORA]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORADIA_VALIDACION]'))
BEGIN
    ALTER TABLE registro.TMD_REGISTRO_HORADIA_VALIDACION 
    ADD CONSTRAINT FK_TMD_REGISTRO_HORADIA_VALIDACION_HORA FOREIGN KEY(ideRegistroHoradia)
    REFERENCES registro.TMD_REGISTRO_HORADIA(ideRegistroHoradia);
END
GO

-- registro.TMD_REGISTRO_HORADIA_ACT
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORADIA_ACT]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_REGISTRO_HORADIA_ACT(
        ideRegistroHoradiaAct bigint IDENTITY(1,1) NOT NULL,
        ideRegistroHoradia bigint NULL,
        numHoras decimal(5,2) NOT NULL,
        txtComentarios varchar(250) NULL,
        txtObservaciones varchar(250) NULL,
        txtJsonAtributos nvarchar(max) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_REGISTRO_HORADIA_ACT_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_HORADIA_ACT_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_REGISTRO_HORADIA_ACT PRIMARY KEY CLUSTERED (ideRegistroHoradiaAct ASC),
        CONSTRAINT CK_TMD_REGISTRO_HORADIA_ACT_JSON CHECK (ISJSON(txtJsonAtributos) = 1 OR txtJsonAtributos IS NULL)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Desglose por actividad del registro diario de horas', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador de la actividad diaria', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'ideRegistroHoradiaAct';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de la cabecera diaria asociada', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'ideRegistroHoradia';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Horas dedicadas a la actividad', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'numHoras';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Comentarios de la actividad', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'txtComentarios';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Observaciones adicionales', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'txtObservaciones';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Atributos dinámicos en formato JSON', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'txtJsonAtributos';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACT', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_REGISTRO_HORADIA_ACT_HORA]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORADIA_ACT]'))
BEGIN
    ALTER TABLE registro.TMD_REGISTRO_HORADIA_ACT 
    ADD CONSTRAINT FK_TMD_REGISTRO_HORADIA_ACT_HORA FOREIGN KEY(ideRegistroHoradia)
    REFERENCES registro.TMD_REGISTRO_HORADIA(ideRegistroHoradia);
END
GO

-- registro.TMD_REGISTRO_HORADIA_ACTTAREA
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORADIA_ACTTAREA]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_REGISTRO_HORADIA_ACTTAREA(
        ideRegistroHoradiaActtarea bigint IDENTITY(1,1) NOT NULL,
        ideRegistroHoradiaAct bigint NOT NULL,
        numHoras decimal(5,2) NOT NULL,
        txtObservaciones varchar(250) NULL,
        txtJsonAtributos nvarchar(max) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_REGISTRO_HORADIA_ACTTAREA_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_HORADIA_ACTTAREA_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_REGISTRO_HORADIA_ACTTAREA PRIMARY KEY CLUSTERED (ideRegistroHoradiaActtarea ASC),
        CONSTRAINT CK_TMD_REGISTRO_HORADIA_ACTTAREA_JSON CHECK (ISJSON(txtJsonAtributos) = 1 OR txtJsonAtributos IS NULL)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Detalle específico de tareas realizadas dentro de cada actividad diaria', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único de la tarea diaria', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'ideRegistroHoradiaActtarea';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de la actividad asociada', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'ideRegistroHoradiaAct';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Horas invertidas en la tarea', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'numHoras';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Observaciones detalladas de la tarea', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'txtObservaciones';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Atributos dinámicos en formato JSON', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'txtJsonAtributos';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_REGISTRO_HORADIA_ACTTAREA_ACT]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORADIA_ACTTAREA]'))
BEGIN
    ALTER TABLE registro.TMD_REGISTRO_HORADIA_ACTTAREA 
    ADD CONSTRAINT FK_TMD_REGISTRO_HORADIA_ACTTAREA_ACT FOREIGN KEY(ideRegistroHoradiaAct)
    REFERENCES registro.TMD_REGISTRO_HORADIA_ACT(ideRegistroHoradiaAct);
END
GO

-- registro.TMD_REGISTRO_HORAMES
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORAMES]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_REGISTRO_HORAMES(
        ideRegistroHorames bigint IDENTITY(1,1) NOT NULL,
        idePeriodo bigint NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        numHoras decimal(5,2) NOT NULL,
        codProyecto varchar(30) NOT NULL,
        nomProyecto varchar(200) NOT NULL,
        ideEmpleado bigint NOT NULL,
        nomEmpleado varchar(200) NOT NULL,
        txtJsonAtributos nvarchar(max) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_REGISTRO_HORAMES_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_HORAMES_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_REGISTRO_HORAMES PRIMARY KEY CLUSTERED (ideRegistroHorames ASC),
        CONSTRAINT CK_TMD_REGISTRO_HORAMES_JSON CHECK (ISJSON(txtJsonAtributos) = 1 OR txtJsonAtributos IS NULL)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Cabecera del registro mensual de horas consolidadas por proyecto y empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del registro mensual', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'ideRegistroHorames';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de referencia al periodo', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'idePeriodo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Año de registro', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'numAnio';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Mes de registro', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'numMes';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Total de horas mensuales registradas', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'numHoras';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código del proyecto', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'codProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre descriptivo del proyecto', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'nomProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID del empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'ideEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre del empleado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'nomEmpleado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Atributos dinámicos en formato JSON', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'txtJsonAtributos';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_REGISTRO_HORAMES_PERIODO]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORAMES]'))
BEGIN
    ALTER TABLE registro.TMD_REGISTRO_HORAMES 
    ADD CONSTRAINT FK_TMD_REGISTRO_HORAMES_PERIODO FOREIGN KEY(idePeriodo)
    REFERENCES registro.TMC_PERIODO(idePeriodo);
END
GO

-- registro.TMD_REGISTRO_HORAMES_VALIDACION
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORAMES_VALIDACION]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_REGISTRO_HORAMES_VALIDACION(
        ideRegistroHoramesValidacion bigint IDENTITY(1,1) NOT NULL,
        ideRegistroHorames bigint NULL,
        flgConforme int NULL,
        flgSubsanado int NULL,
        txtComentario varchar(250) NULL,
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_HORAMES_VALIDACION_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_REGISTRO_HORAMES_VALIDACION PRIMARY KEY CLUSTERED (ideRegistroHoramesValidacion ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Control de validación y observaciones para registros mensuales de horas', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único de la validación mensual', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'ideRegistroHoramesValidacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID del registro mensual asociado', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'ideRegistroHorames';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado de conformidad (1: Conforme, 0: Observado)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'flgConforme';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado de subsanación (1: Subsanado, 0: Pendiente)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'flgSubsanado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Comentario u observación del validador', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'txtComentario';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_VALIDACION', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_REGISTRO_HORAMES_VALIDACION_HORA]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORAMES_VALIDACION]'))
BEGIN
    ALTER TABLE registro.TMD_REGISTRO_HORAMES_VALIDACION 
    ADD CONSTRAINT FK_TMD_REGISTRO_HORAMES_VALIDACION_HORA FOREIGN KEY(ideRegistroHorames)
    REFERENCES registro.TMD_REGISTRO_HORAMES(ideRegistroHorames);
END
GO

-- registro.TMD_REGISTRO_HORAMES_ACT
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORAMES_ACT]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_REGISTRO_HORAMES_ACT(
        ideRegistroHoramesAct bigint IDENTITY(1,1) NOT NULL,
        ideRegistroHorames bigint NULL,
        numHoras decimal(5,2) NOT NULL,
        txtComentarios varchar(250) NULL,
        txtObservaciones varchar(250) NULL,
        txtJsonAtributos nvarchar(max) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_REGISTRO_HORAMES_ACT_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_HORAMES_ACT_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_REGISTRO_HORAMES_ACT PRIMARY KEY CLUSTERED (ideRegistroHoramesAct ASC),
        CONSTRAINT CK_TMD_REGISTRO_HORAMES_ACT_JSON CHECK (ISJSON(txtJsonAtributos) = 1 OR txtJsonAtributos IS NULL)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Desglose por actividad de las horas mensuales', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único de la actividad mensual', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'ideRegistroHoramesAct';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de la cabecera mensual asociada', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'ideRegistroHorames';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Horas mensuales dedicadas a la actividad', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'numHoras';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Comentarios de la actividad', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'txtComentarios';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Observaciones adicionales', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'txtObservaciones';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Atributos dinámicos en formato JSON', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'txtJsonAtributos';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACT', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_REGISTRO_HORAMES_ACT_HORA]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORAMES_ACT]'))
BEGIN
    ALTER TABLE registro.TMD_REGISTRO_HORAMES_ACT 
    ADD CONSTRAINT FK_TMD_REGISTRO_HORAMES_ACT_HORA FOREIGN KEY(ideRegistroHorames)
    REFERENCES registro.TMD_REGISTRO_HORAMES(ideRegistroHorames);
END
GO

-- registro.TMD_REGISTRO_HORAMES_ACTTAREA
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORAMES_ACTTAREA]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_REGISTRO_HORAMES_ACTTAREA(
        ideRegistroHoramesActtarea bigint IDENTITY(1,1) NOT NULL,
        ideRegistroHoramesAct bigint NOT NULL,
        numHoras decimal(5,2) NOT NULL,
        txtObservaciones varchar(250) NULL,
        txtJsonAtributos nvarchar(max) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_REGISTRO_HORAMES_ACTTAREA_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_HORAMES_ACTTAREA_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_REGISTRO_HORAMES_ACTTAREA PRIMARY KEY CLUSTERED (ideRegistroHoramesActtarea ASC),
        CONSTRAINT CK_TMD_REGISTRO_HORAMES_ACTTAREA_JSON CHECK (ISJSON(txtJsonAtributos) = 1 OR txtJsonAtributos IS NULL)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Detalle específico de tareas realizadas dentro de la actividad mensual', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador de la tarea mensual', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'ideRegistroHoramesActtarea';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de la actividad mensual asociada', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'ideRegistroHoramesAct';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Horas mensuales de la tarea', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'numHoras';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Observaciones registradas', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'txtObservaciones';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Atributos dinámicos en formato JSON', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'txtJsonAtributos';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_REGISTRO_HORAMES_ACTTAREA', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_REGISTRO_HORAMES_ACTTAREA_ACT]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_REGISTRO_HORAMES_ACTTAREA]'))
BEGIN
    ALTER TABLE registro.TMD_REGISTRO_HORAMES_ACTTAREA 
    ADD CONSTRAINT FK_TMD_REGISTRO_HORAMES_ACTTAREA_ACT FOREIGN KEY(ideRegistroHoramesAct)
    REFERENCES registro.TMD_REGISTRO_HORAMES_ACT(ideRegistroHoramesAct);
END
GO

-- registro.TMD_DISTRIBUCION_GIP
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_DISTRIBUCION_GIP]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_DISTRIBUCION_GIP(
        ideDistribucionGip bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        codProyecto varchar(30) NOT NULL,
        nomProyecto varchar(200) NOT NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_DISTRIBUCION_GIP_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_DISTRIBUCION_GIP_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_DISTRIBUCION_GIP PRIMARY KEY CLUSTERED (ideDistribucionGip ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Cabecera de porcentaje de distribución anual de GIP por proyecto', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único de la distribución GIP', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'ideDistribucionGip';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Año de la distribución', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'numAnio';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código del proyecto', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'codProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre descriptivo del proyecto', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'nomProyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

-- registro.TMD_DISTRIBUCION_GIP_DETALLE
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[registro].[TMD_DISTRIBUCION_GIP_DETALLE]') AND type in (N'U'))
BEGIN
    CREATE TABLE registro.TMD_DISTRIBUCION_GIP_DETALLE(
        ideDistribucionGipDetalle bigint IDENTITY(1,1) NOT NULL,
        ideDistribucionGip bigint NULL,
        txtActividad varchar(500) NULL,
        primerTrimestre decimal(5,2) NOT NULL,
        segundoTrimestre decimal(5,2) NOT NULL,
        tercerTrimestre decimal(5,2) NOT NULL,
        cuartoTrimestre decimal(5,2) NOT NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_DISTRIBUCION_GIP_DETALLE_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_DISTRIBUCION_GIP_DETALLE_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_DISTRIBUCION_GIP_DETALLE PRIMARY KEY CLUSTERED (ideDistribucionGipDetalle ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Detalle trimestral de porcentaje de distribución GIP por actividad', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del detalle GIP', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'ideDistribucionGipDetalle';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de cabecera de distribución GIP', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'ideDistribucionGip';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre o glosa de la actividad', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'txtActividad';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Porcentaje de distribución del 1er trimestre', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'primerTrimestre';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Porcentaje de distribución del 2do trimestre', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'segundoTrimestre';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Porcentaje de distribución del 3er trimestre', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'tercerTrimestre';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Porcentaje de distribución del 4to trimestre', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'cuartoTrimestre';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'registro', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_GIP_DETALLE', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[registro].[FK_TMD_DISTRIBUCION_GIP_DETALLE]') AND parent_object_id = OBJECT_ID(N'[registro].[TMD_DISTRIBUCION_GIP_DETALLE]'))
BEGIN
    ALTER TABLE registro.TMD_DISTRIBUCION_GIP_DETALLE 
    ADD CONSTRAINT FK_TMD_DISTRIBUCION_GIP_DETALLE FOREIGN KEY(ideDistribucionGip)
    REFERENCES registro.TMD_DISTRIBUCION_GIP(ideDistribucionGip);
END
GO

/* =========================================================================
   4. ESQUEMA: proceso
   ========================================================================= */

-- proceso.TMD_GASTO_PERSONAL
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[proceso].[TMD_GASTO_PERSONAL]') AND type in (N'U'))
BEGIN
    CREATE TABLE proceso.TMD_GASTO_PERSONAL(
        ideGastoPersonal bigint IDENTITY(1,1) NOT NULL,
        idePeriodo bigint NULL,
        voucherno varchar(30) NULL,
        txtTipoGasto varchar(30) NULL,
        voucherline int NULL,
        vendor int NULL,
        status varchar(10) NULL,
        txtLocalName varchar(500) NULL,	
        localamount decimal(10,2) NOT NULL,
        idePersona int NULL,
        txtNombreCompleto varchar(250) NULL,
        account varchar(30) NULL,
        Documento varchar(30) NULL,
        Area varchar(200) NULL,
        Departamento varchar(200) NULL,
        Cargo varchar(200) NULL,
        CostCenter varchar(10) NULL,
        CentroCostos varchar(10) NULL,
        period varchar(10) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_GASTO_PERSONAL_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_GASTO_PERSONAL_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_GASTO_PERSONAL PRIMARY KEY CLUSTERED (ideGastoPersonal ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Registro de gastos de personal y planilla importados para el cálculo de costo de labor', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del gasto de personal', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'ideGastoPersonal';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID del periodo contable asociado', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'idePeriodo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Número de voucher contable', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'voucherno';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Tipo de gasto de personal', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'txtTipoGasto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Línea de detalle del voucher', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'voucherline';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código del proveedor o entidad', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'vendor';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado del comprobante en ERP', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'status';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre descriptivo local del concepto', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'txtLocalName';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Monto en moneda local', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'localamount';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID de la persona / colaborador', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'idePersona';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Nombre completo del colaborador', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'txtNombreCompleto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Cuenta contable asignada', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'account';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Número de documento de identidad', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'Documento';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Área organizacional', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'Area';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Departamento', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'Departamento';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Cargo o puesto de trabajo', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'Cargo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código de Centro de Costos', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'CostCenter';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Descripción del Centro de Costos', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'CentroCostos';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Periodo contable (AAAAMM)', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'period';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_GASTO_PERSONAL', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[proceso].[FK_TMD_GASTO_PERSONAL_PERIODO]') AND parent_object_id = OBJECT_ID(N'[proceso].[TMD_GASTO_PERSONAL]'))
BEGIN
    ALTER TABLE proceso.TMD_GASTO_PERSONAL 
    ADD CONSTRAINT FK_TMD_GASTO_PERSONAL_PERIODO FOREIGN KEY(idePeriodo)
    REFERENCES registro.TMC_PERIODO(idePeriodo);
END
GO

-- proceso.TMD_DISTRIBUCION_COMPENSACION
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[proceso].[TMD_DISTRIBUCION_COMPENSACION]') AND type in (N'U'))
BEGIN
    CREATE TABLE proceso.TMD_DISTRIBUCION_COMPENSACION(
        ideDistribucionCompensacion bigint IDENTITY(1,1) NOT NULL,
        idePeriodo bigint NULL,
        period varchar(10) NULL,
        DescripcionLocal varchar(200) NULL,
        Proyecto varchar(30) NULL,
        Monto decimal(10,2) NOT NULL,
        englishname varchar(200) NULL,
        txtCategoria varchar(30) NULL,
        Account varchar(10) NULL,
        voucherno varchar(10) NULL,
        vendor int NULL,
        invoice varchar(30) NULL,
        flgEstado int NULL CONSTRAINT DF_TMD_DISTRIBUCION_COMPENSACION_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_DISTRIBUCION_COMPENSACION_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMD_DISTRIBUCION_COMPENSACION PRIMARY KEY CLUSTERED (ideDistribucionCompensacion ASC)
    );

    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Cálculo y distribución final de compensaciones y costos por proyecto', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Identificador único del registro de distribución', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'ideDistribucionCompensacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'ID del periodo contable', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'idePeriodo';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Periodo contable (AAAAMM)', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'period';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Descripción en español del concepto', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'DescripcionLocal';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código del proyecto de destino', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'Proyecto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Monto calculado y asignado al proyecto', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'Monto';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Descripción en inglés del concepto', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'englishname';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Categoría de la compensación', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'txtCategoria';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Cuenta contable', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'Account';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Número de comprobante contable', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'voucherno';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Código de proveedor', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'vendor';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Número de factura asociada', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'invoice';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Estado (1: Activo, 0: Inactivo)', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'flgEstado';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de creación', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'fecCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de creación', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'txtUsuarioCreacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Fecha de actualización', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'fecActualizacion';
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Usuario de actualización', @level0type=N'SCHEMA',@level0name=N'proceso', @level1type=N'TABLE',@level1name=N'TMD_DISTRIBUCION_COMPENSACION', @level2type=N'COLUMN',@level2name=N'txtUsuarioActualizacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[proceso].[FK_TMD_DISTRIBUCION_COMPENSACION_PERIODO]') AND parent_object_id = OBJECT_ID(N'[proceso].[TMD_DISTRIBUCION_COMPENSACION]'))
BEGIN
    ALTER TABLE proceso.TMD_DISTRIBUCION_COMPENSACION 
    ADD CONSTRAINT FK_TMD_DISTRIBUCION_COMPENSACION_PERIODO FOREIGN KEY(idePeriodo)
    REFERENCES registro.TMC_PERIODO(idePeriodo);
END
GO