/* =========================================================================
   30 - HU-008 CA-01: fecha y usuario de la aprobacion del periodo

   "Al confirmar, actualizara el periodo a estado Cerrado, registrando la
   fecha/usuario". Hasta aqui solo quedaban en fecActualizacion, que tambien
   escriben el procesamiento y la reapertura, asi que no se podia saber quien
   cerro el periodo ni cuando.

   registro.TMC_PERIODO.fecAprobacion / txtUsuarioAprobacion
                                   se llenan al aprobar y se limpian al
                                   reaperturar: describen el cierre vigente.
                                   El historial completo queda en TG_AUDITORIA.
   usp_Periodo_ObtenerEstado       devuelve tambien ambas columnas.
   usp_Periodo_Aprobar             las registra.
   usp_Periodo_Reaperturar         las limpia.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('registro.TMC_PERIODO', 'fecAprobacion') IS NULL
    ALTER TABLE registro.TMC_PERIODO ADD fecAprobacion datetime NULL;
GO

IF COL_LENGTH('registro.TMC_PERIODO', 'txtUsuarioAprobacion') IS NULL
    ALTER TABLE registro.TMC_PERIODO ADD txtUsuarioAprobacion varchar(30) NULL;
GO

CREATE OR ALTER PROCEDURE proceso.usp_Periodo_ObtenerEstado
    @numAnio int,
    @numMes int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.idePeriodo,
        @numAnio AS numAnio,
        @numMes AS numMes,
        ISNULL(p.flgEstado, 1) AS flgEstado,
        p.fecProcesamiento,
        p.txtUsuarioProcesamiento,
        p.fecAprobacion,
        p.txtUsuarioAprobacion,
        ISNULL((SELECT COUNT(*) FROM proceso.TMD_GASTO_PERSONAL g
                WHERE g.idePeriodo = p.idePeriodo AND g.flgEstado = 1), 0) AS numGastoPersonal,
        ISNULL((SELECT COUNT(*) FROM proceso.TMD_DISTRIBUCION_COMPENSACION c
                WHERE c.idePeriodo = p.idePeriodo AND c.flgEstado = 1), 0) AS numCompensacion
    FROM (SELECT 1 AS uno) AS fija
    LEFT JOIN registro.TMC_PERIODO p
           ON p.numAnio = @numAnio AND p.numMes = @numMes;
END
GO

CREATE OR ALTER PROCEDURE proceso.usp_Periodo_Aprobar
    @numAnio int,
    @numMes int,
    @txtUsuario varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo bigint, @flgEstado int, @fecProcesamiento datetime;

    SELECT @idePeriodo = idePeriodo, @flgEstado = flgEstado, @fecProcesamiento = fecProcesamiento
    FROM registro.TMC_PERIODO
    WHERE numAnio = @numAnio AND numMes = @numMes;

    IF @idePeriodo IS NULL OR @fecProcesamiento IS NULL
        THROW 50012, 'No se puede aprobar un periodo que todavia no ha sido procesado.', 1;

    IF @flgEstado = 2
        THROW 50013, 'El periodo ya esta cerrado.', 1;

    UPDATE registro.TMC_PERIODO
    SET flgEstado = 2,
        fecAprobacion = GETDATE(),
        txtUsuarioAprobacion = @txtUsuario,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE idePeriodo = @idePeriodo;

    EXEC proceso.usp_Periodo_ObtenerEstado @numAnio = @numAnio, @numMes = @numMes;
END
GO

CREATE OR ALTER PROCEDURE proceso.usp_Periodo_Reaperturar
    @numAnio int,
    @numMes int,
    @txtUsuario varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo bigint, @flgEstado int;

    SELECT @idePeriodo = idePeriodo, @flgEstado = flgEstado
    FROM registro.TMC_PERIODO
    WHERE numAnio = @numAnio AND numMes = @numMes;

    IF @idePeriodo IS NULL OR @flgEstado <> 2
        THROW 50014, 'Solo se puede reaperturar un periodo cerrado.', 1;

    UPDATE registro.TMC_PERIODO
    SET flgEstado = 1,
        fecAprobacion = NULL,
        txtUsuarioAprobacion = NULL,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE idePeriodo = @idePeriodo;

    EXEC proceso.usp_Periodo_ObtenerEstado @numAnio = @numAnio, @numMes = @numMes;
END
GO
