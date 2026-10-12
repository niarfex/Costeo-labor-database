/* =========================================================================
   38 - Reportes de horas: consolidado (HU-011), detallado por trabajador por
   dia (HU-013) y por mes (HU-014)

   Los tres consultan solo periodos cerrados (registro.TMC_PERIODO.flgEstado
   = 2). El departamento del trabajador es el de su periodo
   (registro.TMD_PERIODO_EMPLEADO); quien no pertenece a un departamento de la
   Gerencia de Operaciones sale como OTROS.

   Las horas del detalle van al nivel mas fino registrado: la tarea si la hay,
   si no la actividad, si no el proyecto. El comentario sigue el mismo orden.
   El consolidado suma registro.TMD_REGISTRO_HORAMES, que junta las dos
   modalidades de registro (por dia y por mes).

   Errores nuevos:
     50043  el periodo no esta cerrado

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Departamento del reporte

   Codigo de filtro, nombre que se muestra y orden. Sin departamento: OTROS.
   ------------------------------------------------------------------------- */

CREATE OR ALTER FUNCTION registro.ufn_DepartamentoReporte (@codDepartamento varchar(10))
RETURNS TABLE
AS
RETURN
    SELECT CASE WHEN @codDepartamento IN ('DGO', 'DIP', 'DPCM', 'RRCC', 'GO') THEN @codDepartamento ELSE 'OTROS' END AS codDepartamento,
           CASE @codDepartamento
               WHEN 'DGO'  THEN 'DGO'
               WHEN 'DIP'  THEN 'DIP'
               WHEN 'DPCM' THEN 'POST CIERRE'
               WHEN 'RRCC' THEN 'RELACIONES COMUNITARIAS'
               WHEN 'GO'   THEN 'GERENCIA DE OPERACIONES'
               ELSE 'OTROS'
           END AS nomDepartamento,
           CASE @codDepartamento
               WHEN 'DGO' THEN 1 WHEN 'DIP' THEN 2 WHEN 'DPCM' THEN 3 WHEN 'RRCC' THEN 4 WHEN 'GO' THEN 5
               ELSE 6
           END AS numOrden;
GO

/* -------------------------------------------------------------------------
   2. Periodos cerrados, para los combos de anio y mes
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_ReporteHoras_ListarPeriodosCerrados
AS
BEGIN
    SET NOCOUNT ON;

    SELECT numAnio, numMes
    FROM registro.TMC_PERIODO
    WHERE flgEstado = 2
    ORDER BY numAnio DESC, numMes DESC;
END
GO

/* -------------------------------------------------------------------------
   3. HU-011: horas del mes por departamento y trabajador
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_ReporteHoras_Consolidado
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                   WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50043, 'El periodo no esta cerrado: solo se reportan periodos cerrados.', 1;

    WITH horas AS (
        SELECT r.ideEmpleado, MAX(r.nomEmpleado) AS nomEmpleado, SUM(r.numHoras) AS numHoras
        FROM registro.TMD_REGISTRO_HORAMES r
        WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1
        GROUP BY r.ideEmpleado
        HAVING SUM(r.numHoras) > 0
    )
    SELECT d.codDepartamento, d.nomDepartamento,
           h.ideEmpleado, COALESCE(pe.nomEmpleado, h.nomEmpleado) AS nomEmpleado,
           CAST(h.numHoras AS decimal(10, 2)) AS numHoras
    FROM horas h
    OUTER APPLY (SELECT TOP (1) pe.codDepartamento, pe.nomEmpleado
                 FROM registro.TMD_PERIODO_EMPLEADO pe
                 WHERE pe.ideEmpleado = h.ideEmpleado AND pe.numAnio = @numAnio AND pe.numMes = @numMes
                   AND pe.flgEstado = 1) pe
    CROSS APPLY registro.ufn_DepartamentoReporte(pe.codDepartamento) d
    ORDER BY d.numOrden, nomEmpleado;
END
GO

/* -------------------------------------------------------------------------
   4. HU-013: detalle por trabajador por dia

   @codDepartamento nulo trae todos; 'OTROS' trae a quienes no tienen departamento.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_ReporteHoras_DetalleDia
    @numAnio         int,
    @numMes          int,
    @codDepartamento varchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                   WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50043, 'El periodo no esta cerrado: solo se reportan periodos cerrados.', 1;

    SELECT r.fecLabor,
           d.codDepartamento, d.nomDepartamento,
           COALESCE(pe.nomEmpleado, r.nomEmpleado) AS nomEmpleado,
           r.codProyecto, r.nomProyecto,
           a.txtActividad,
           t.txtTarea,
           CAST(COALESCE(t.numHoras, a.numHoras, r.numHoras) AS decimal(10, 2)) AS numHoras,
           COALESCE(NULLIF(t.txtObservaciones, ''), NULLIF(a.txtComentarios, ''), NULLIF(r.txtObservaciones, '')) AS txtComentario
    FROM registro.TMD_REGISTRO_HORADIA r
    LEFT JOIN registro.TMD_REGISTRO_HORADIA_ACT a
           ON a.ideRegistroHoradia = r.ideRegistroHoradia AND a.flgEstado = 1
    LEFT JOIN registro.TMD_REGISTRO_HORADIA_ACTTAREA t
           ON t.ideRegistroHoradiaAct = a.ideRegistroHoradiaAct AND t.flgEstado = 1
    OUTER APPLY (SELECT TOP (1) pe.codDepartamento, pe.nomEmpleado
                 FROM registro.TMD_PERIODO_EMPLEADO pe
                 WHERE pe.ideEmpleado = r.ideEmpleado AND pe.numAnio = @numAnio AND pe.numMes = @numMes
                   AND pe.flgEstado = 1) pe
    CROSS APPLY registro.ufn_DepartamentoReporte(pe.codDepartamento) d
    WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1
      AND (@codDepartamento IS NULL OR d.codDepartamento = @codDepartamento)
    ORDER BY r.fecLabor, d.numOrden, nomEmpleado, r.codProyecto,
             a.ideRegistroHoradiaAct, t.ideRegistroHoradiaActtarea;
END
GO

/* -------------------------------------------------------------------------
   5. HU-014: detalle por trabajador por mes

   Quien registra por dia tiene el consolidado mensual sin actividades: sale
   una fila por proyecto con sus horas.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_ReporteHoras_DetalleMes
    @numAnio         int,
    @numMes          int,
    @codDepartamento varchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                   WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50043, 'El periodo no esta cerrado: solo se reportan periodos cerrados.', 1;

    SELECT r.numAnio, r.numMes,
           d.codDepartamento, d.nomDepartamento,
           COALESCE(pe.nomEmpleado, r.nomEmpleado) AS nomEmpleado,
           r.codProyecto, r.nomProyecto,
           a.txtActividad,
           t.txtTarea,
           CAST(COALESCE(t.numHoras, a.numHoras, r.numHoras) AS decimal(10, 2)) AS numHoras,
           COALESCE(NULLIF(t.txtObservaciones, ''), NULLIF(a.txtComentarios, ''), NULLIF(r.txtObservaciones, '')) AS txtComentario
    FROM registro.TMD_REGISTRO_HORAMES r
    LEFT JOIN registro.TMD_REGISTRO_HORAMES_ACT a
           ON a.ideRegistroHorames = r.ideRegistroHorames AND a.flgEstado = 1
    LEFT JOIN registro.TMD_REGISTRO_HORAMES_ACTTAREA t
           ON t.ideRegistroHoramesAct = a.ideRegistroHoramesAct AND t.flgEstado = 1
    OUTER APPLY (SELECT TOP (1) pe.codDepartamento, pe.nomEmpleado
                 FROM registro.TMD_PERIODO_EMPLEADO pe
                 WHERE pe.ideEmpleado = r.ideEmpleado AND pe.numAnio = @numAnio AND pe.numMes = @numMes
                   AND pe.flgEstado = 1) pe
    CROSS APPLY registro.ufn_DepartamentoReporte(pe.codDepartamento) d
    WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1
      AND (@codDepartamento IS NULL OR d.codDepartamento = @codDepartamento)
    ORDER BY d.numOrden, nomEmpleado, r.codProyecto,
             a.ideRegistroHoramesAct, t.ideRegistroHoramesActtarea;
END
GO

/* -------------------------------------------------------------------------
   6. Opciones de menu bajo Reportes

   El consolidado ya existe (REP_CONSOLIDADO, script 08). Se agregan los dos
   detallados y se asignan a los perfiles que pide cada historia:
     consolidado y detalle por dia: Contador, Jefe, Supervisor y Administrador
     detalle por mes:               Contador, Jefe y Administrador
   El titulo REPORTES va con cada perfil: sin el, el menu descarta sus opciones.
   ------------------------------------------------------------------------- */

SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT n.codOpcion, n.nomOpcion, n.txtRuta, n.txtIcono, p.ideOpcion, n.numOrden, 1, @usuario
FROM (VALUES
    ('REP_DETALLE_DIA', 'Detallado por trabajador por día', '/reportes/detalle-dia', 'bi bi-calendar3', 6),
    ('REP_DETALLE_MES', 'Detallado por trabajador por mes', '/reportes/detalle-mes', 'bi bi-calendar-month', 7)
) AS n(codOpcion, nomOpcion, txtRuta, txtIcono, numOrden)
JOIN seguridad.TG_OPCION p ON p.codOpcion = 'REPORTES'
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION o WHERE o.codOpcion = n.codOpcion);
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES
    ('CONTADOR', 'REPORTES'), ('JEFE', 'REPORTES'), ('SUPERVISOR', 'REPORTES'), ('ADMINISTRADOR', 'REPORTES'),
    ('CONTADOR', 'REP_CONSOLIDADO'), ('JEFE', 'REP_CONSOLIDADO'), ('SUPERVISOR', 'REP_CONSOLIDADO'), ('ADMINISTRADOR', 'REP_CONSOLIDADO'),
    ('CONTADOR', 'REP_DETALLE_DIA'), ('JEFE', 'REP_DETALLE_DIA'), ('SUPERVISOR', 'REP_DETALLE_DIA'), ('ADMINISTRADOR', 'REP_DETALLE_DIA'),
    ('CONTADOR', 'REP_DETALLE_MES'), ('JEFE', 'REP_DETALLE_MES'), ('ADMINISTRADOR', 'REP_DETALLE_MES')
) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
