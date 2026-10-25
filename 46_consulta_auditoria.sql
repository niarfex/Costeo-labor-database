/* =========================================================================
   46 - Consulta de auditorias

   El Administrador consulta general.TG_AUDITORIA por usuario, opcion,
   evento, IP y rango de fechas, y exporta el resultado a Excel.

   El evento es la primera palabra de txtEvento (el tipo, por ejemplo
   CONSULTA_REPORTE); lo que sigue es el detalle. Usuario e IP se buscan por
   contenido.

   Un indice por fecha evita recorrer toda la tabla, que crece con cada
   accion del sistema.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Indice por fecha
   ------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TG_AUDITORIA_FECHA' AND object_id = OBJECT_ID('general.TG_AUDITORIA'))
    CREATE NONCLUSTERED INDEX IX_TG_AUDITORIA_FECHA
        ON general.TG_AUDITORIA (fecha_evento DESC)
        INCLUDE (txtUsuario, txtOpcion, txtResultado, txtDireccionIp, ideRegistroAsociado);
GO

/* -------------------------------------------------------------------------
   2. Consulta

   Con @numTamanioPagina nulo devuelve todo (hasta @numMaximo filas), para la
   exportacion. numTotalRegistros es el total que cumple los filtros.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE general.usp_Auditoria_Consultar
    @txtUsuario       varchar(100) = NULL,
    @txtOpcion        varchar(50)  = NULL,
    @txtEvento        varchar(100) = NULL,
    @txtDireccionIp   varchar(50)  = NULL,
    @fecInicio        date,
    @fecFin           date,
    @numPagina        int = 1,
    @numTamanioPagina int = 20,
    @numMaximo        int = 50000
AS
BEGIN
    SET NOCOUNT ON;

    IF @numPagina IS NULL OR @numPagina < 1 SET @numPagina = 1;

    DECLARE @desde datetime = CAST(@fecInicio AS datetime);
    -- La fecha de fin cuenta completa.
    DECLARE @hasta datetime = DATEADD(DAY, 1, CAST(@fecFin AS datetime));
    DECLARE @usuario varchar(102) = '%' + NULLIF(TRIM(@txtUsuario), '') + '%';
    DECLARE @ip varchar(52) = '%' + NULLIF(TRIM(@txtDireccionIp), '') + '%';
    DECLARE @evento varchar(100) = NULLIF(TRIM(@txtEvento), '');
    DECLARE @opcion varchar(50) = NULLIF(TRIM(@txtOpcion), '');

    WITH filtradas AS (
        SELECT a.ideAuditoria, a.fecha_evento, a.txtUsuario, a.txtOpcion,
               CAST(a.txtEvento AS varchar(max)) AS txtEvento,
               a.txtResultado, a.txtDireccionIp, a.ideRegistroAsociado
        FROM general.TG_AUDITORIA a
        WHERE a.fecha_evento >= @desde AND a.fecha_evento < @hasta
          AND (@usuario IS NULL OR a.txtUsuario LIKE @usuario)
          AND (@ip IS NULL OR a.txtDireccionIp LIKE @ip)
          AND (@opcion IS NULL OR a.txtOpcion = @opcion)
          -- El tipo es la primera palabra: CONSULTA_REPORTE no debe traer CONSULTA_REPORTE_X.
          AND (@evento IS NULL OR a.txtEvento LIKE @evento OR a.txtEvento LIKE @evento + ' %')
    )
    SELECT ideAuditoria, fecha_evento, txtUsuario, txtOpcion, txtEvento, txtResultado,
           txtDireccionIp, ideRegistroAsociado, COUNT(*) OVER () AS numTotalRegistros
    FROM filtradas
    ORDER BY fecha_evento DESC, ideAuditoria DESC
    OFFSET CASE WHEN @numTamanioPagina IS NULL THEN 0 ELSE (@numPagina - 1) * @numTamanioPagina END ROWS
    FETCH NEXT ISNULL(@numTamanioPagina, @numMaximo) ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* -------------------------------------------------------------------------
   3. Opciones con auditoria, para el filtro
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE general.usp_Auditoria_ListarOpciones
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT a.txtOpcion
    FROM general.TG_AUDITORIA a
    WHERE a.txtOpcion IS NOT NULL
    ORDER BY a.txtOpcion;
END
GO

/* -------------------------------------------------------------------------
   4. Opcion de menu, solo para el Administrador

   Igual que los scripts 33 y 36: idempotente y sin filtrar por flgEstado.
   ------------------------------------------------------------------------- */

SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'CONSULTA_AUDITORIA', 'Consulta de auditorías', '/seguridad/auditorias',
       'bi bi-journal-text', p.ideOpcion, 2, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'SEGURIDAD'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'CONSULTA_AUDITORIA');

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('ADMINISTRADOR', 'SEGURIDAD'), ('ADMINISTRADOR', 'CONSULTA_AUDITORIA')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
