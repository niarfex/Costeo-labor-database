/* =========================================================================
   48 - Fecha de cese y area del gasto de personal

   1. La fecha de cese de cada persona (BD_SPRING.dbo.EmpleadoMast.FechaCese)
      se guarda en proceso.TMD_GASTO_PERSONAL al procesar el periodo, para
      mostrarla y usarla en los reportes. La completa
      proceso.usp_GastoPersonal_CompletarCese, que el backend ejecuta despues
      de proceso.usp_Periodo_Procesar.

   2. El area con la que los reportes arman el DETALLE_GASTO_PERSONAL y el
      RESUMEN_GASTO_PERSONAL se resuelve en proceso.VW_GASTO_PERSONAL_REPORTE:
        - Primero, la asignacion del Contador para el periodo (script 47).
        - Si no hay, y SPRING la tiene en la Gerencia de Operaciones con una
          fecha de cese anterior al mes del periodo, pasa a la Gerencia de
          Administracion y Finanzas: el cambio es al mes siguiente del cese.
        - Si no, el area de SPRING.
      La Oficina de Planeamiento y Mejora Continua ya se suma a la Gerencia
      General en el reporte (GERENCIAS). El area original queda en AreaSpring.

   La vista conserva los filtros del script 32. Quien la modifique despues
   (por ejemplo, para la exclusion de proyectos por periodo) debe partir de
   esta version.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Columna de fecha de cese
   ------------------------------------------------------------------------- */

IF COL_LENGTH('proceso.TMD_GASTO_PERSONAL', 'fecCese') IS NULL
    ALTER TABLE proceso.TMD_GASTO_PERSONAL ADD fecCese datetime NULL;
GO

/* -------------------------------------------------------------------------
   2. Completar la fecha de cese del periodo procesado

   Sin BD_SPRING no hace nada: la fecha queda vacia y no aplica la regla de
   cese. Devuelve cuantas lineas actualizo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_GastoPersonal_CompletarCese
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo bigint = (SELECT idePeriodo FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes);
    DECLARE @numActualizadas int = 0;

    IF @idePeriodo IS NOT NULL AND DB_ID('BD_SPRING') IS NOT NULL
    BEGIN
        EXEC sp_executesql N'
            UPDATE g
            SET g.fecCese = em.FechaCese
            FROM proceso.TMD_GASTO_PERSONAL g
            INNER JOIN BD_SPRING.dbo.EmpleadoMast em ON em.Empleado = g.vendor
            WHERE g.idePeriodo = @periodo AND g.flgEstado = 1
              AND ISNULL(g.fecCese, ''19000101'') <> ISNULL(em.FechaCese, ''19000101'');
            SET @actualizadas = @@ROWCOUNT;',
            N'@periodo bigint, @actualizadas int OUTPUT', @periodo = @idePeriodo, @actualizadas = @numActualizadas OUTPUT;
    END

    SELECT @numActualizadas AS numActualizadas;
END
GO

/* -------------------------------------------------------------------------
   3. Vista de los reportes con el area resuelta
   ------------------------------------------------------------------------- */

CREATE OR ALTER VIEW proceso.VW_GASTO_PERSONAL_REPORTE
AS
SELECT  g.ideGastoPersonal, g.idePeriodo, g.voucherno, g.txtTipoGasto, g.voucherline,
        g.vendor, g.status, g.txtLocalName, g.localamount, g.idePersona, g.txtNombreCompleto,
        g.account, g.Documento,
        CAST(COALESCE(a.nomArea,
                 CASE WHEN g.Area = 'GERENCIA DE OPERACIONES' AND g.fecCese IS NOT NULL
                           AND p.numAnio * 100 + p.numMes > YEAR(g.fecCese) * 100 + MONTH(g.fecCese)
                      THEN 'GERENCIA DE ADMINISTRACION Y FINANZAS'
                      ELSE g.Area END) AS varchar(200)) AS Area,
        g.Departamento, g.Cargo, g.CostCenter,
        g.CentroCostos, g.period, g.afe,
        g.fecCese, g.Area AS AreaSpring
FROM proceso.TMD_GASTO_PERSONAL g
INNER JOIN registro.TMC_PERIODO p ON p.idePeriodo = g.idePeriodo
LEFT JOIN proceso.TMD_ASIGNACION_AREA a
       ON a.numAnio = p.numAnio AND a.numMes = p.numMes AND a.idePersona = g.vendor AND a.flgEstado = 1
WHERE g.flgEstado = 1
  AND g.status = 'PR'
  AND g.account >= '62110010'
  AND g.account <= '65990070'
  AND g.account NOT IN (
      '63801400', '63801410', '63801420', '63801430', '63801440',
      '63801450', '63801460', '63801470', '63801480', '63801490',
      '63801500', '63801600', '63802070', '63802080', '63802085',
      '63802090', '63802095', '63803000', '63803005', '63803010',
      '63930040')
  AND g.afe <> '000000505049'
  AND g.CostCenter <> '0216';
GO

/* -------------------------------------------------------------------------
   4. Pestania Gasto personal del procesamiento con la fecha de cese
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_GastoPersonal_Listar
    @numAnio int,
    @numMes int,
    @numPagina int = 0,
    @numTamanio int = 20
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo bigint = (SELECT idePeriodo FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes);

    -- El total viaja en cada fila, como en los demas listados paginados.
    SELECT
        g.ideGastoPersonal, g.voucherno, g.txtTipoGasto, g.vendor, g.status,
        g.txtLocalName, g.localamount, g.txtNombreCompleto, g.account,
        g.Documento, g.Area, g.Departamento, g.Cargo, g.fecCese,
        COUNT(*) OVER () AS numTotalRegistros
    FROM proceso.TMD_GASTO_PERSONAL g
    WHERE g.idePeriodo = @idePeriodo AND g.flgEstado = 1
    ORDER BY g.voucherno, g.ideGastoPersonal
    OFFSET (@numPagina * @numTamanio) ROWS FETCH NEXT @numTamanio ROWS ONLY;
END
GO
