/* =========================================================================
   53 - Gasto de personal de los reportes: proyectos excluidos y area por
        departamento

   Parte de la version del script 48 de proceso.VW_GASTO_PERSONAL_REPORTE y
   de proceso.usp_GastoPersonal_Listar.

   1. Proyectos excluidos por periodo (proceso.TMD_PROYECTO_EXCLUIDO, script
      50). La vista ya no descarta el proyecto 000000505049 con un filtro
      fijo: trae todas las lineas y marca con flgProyectoExcluido = 1 las de
      un proyecto excluido en su periodo. BD_REP19 las muestra; los cuadros
      del costo labor (proceso.usp_Reporte_CostoLabor) las dejan fuera.

      El filtro fijo (afe <> '000000505049') tambien descartaba las lineas
      sin AFE, porque una comparacion con NULL no se cumple. Se conserva de
      forma explicita (afe IS NOT NULL) para no cambiar resultados: en los
      periodos procesados las lineas sin AFE son todas de cuentas de balance
      (01 a 49, 75, 77 y 88), que el rango de cuentas ya descarta.

   2. Area vacia en SPRING. Hay personal con EmpleadoMast.Division vacia
      (ingresos recientes): el area sale en blanco y el reporte no le
      encuentra gerencia. HR_Departamento no tiene una columna que lo ligue a
      una division, asi que el area se completa con la mas frecuente entre
      las personas del mismo departamento en el periodo (desempate por
      nombre). Con el area ya completa se aplican, como en el script 48, la
      regla de cese (GO pasa a GAF desde el mes siguiente al cese) y por
      encima de todo la asignacion del Contador (script 47).

   3. La pestania Gasto personal del procesamiento muestra el codigo del
      proyecto (codProyecto, el afe de la linea).

   4. La pestania Resumen del procesamiento (proceso.usp_GastoPersonal_Resumen,
      version del script 32) sigue sin las lineas de proyectos excluidos.

   Requiere el script 50. Error nuevo:
     50143  falta proceso.TMD_PROYECTO_EXCLUIDO (script 50)

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('proceso.TMD_PROYECTO_EXCLUIDO') IS NULL
    THROW 50143, 'Falta proceso.TMD_PROYECTO_EXCLUIDO: ejecute antes el script 50 (proyectos excluidos).', 1;
GO

/* -------------------------------------------------------------------------
   1 y 2. Vista de los reportes
   ------------------------------------------------------------------------- */

CREATE OR ALTER VIEW proceso.VW_GASTO_PERSONAL_REPORTE
AS
SELECT  g.ideGastoPersonal, g.idePeriodo, g.voucherno, g.txtTipoGasto, g.voucherline,
        g.vendor, g.status, g.txtLocalName, g.localamount, g.idePersona, g.txtNombreCompleto,
        g.account, g.Documento,
        CAST(COALESCE(a.nomArea,
                 CASE WHEN b.AreaBase = 'GERENCIA DE OPERACIONES' AND g.fecCese IS NOT NULL
                           AND p.numAnio * 100 + p.numMes > YEAR(g.fecCese) * 100 + MONTH(g.fecCese)
                      THEN 'GERENCIA DE ADMINISTRACION Y FINANZAS'
                      ELSE b.AreaBase END) AS varchar(200)) AS Area,
        g.Departamento, g.Cargo, g.CostCenter,
        g.CentroCostos, g.period, g.afe,
        g.fecCese, g.Area AS AreaSpring,
        CASE WHEN e.ideProyectoExcluido IS NULL THEN 0 ELSE 1 END AS flgProyectoExcluido
FROM proceso.TMD_GASTO_PERSONAL g
INNER JOIN registro.TMC_PERIODO p ON p.idePeriodo = g.idePeriodo
LEFT JOIN proceso.TMD_ASIGNACION_AREA a
       ON a.numAnio = p.numAnio AND a.numMes = p.numMes AND a.idePersona = g.vendor AND a.flgEstado = 1
-- Area mas frecuente de cada departamento en el periodo, segun SPRING.
LEFT JOIN (
    SELECT idePeriodo, Departamento, Area,
           ROW_NUMBER() OVER (PARTITION BY idePeriodo, Departamento
                              ORDER BY COUNT(DISTINCT vendor) DESC, Area) AS numOrden
    FROM proceso.TMD_GASTO_PERSONAL
    WHERE flgEstado = 1 AND Area <> '' AND Departamento <> ''
    GROUP BY idePeriodo, Departamento, Area
) d ON d.idePeriodo = g.idePeriodo AND d.Departamento = g.Departamento AND d.numOrden = 1
CROSS APPLY (SELECT COALESCE(NULLIF(g.Area, ''), d.Area) AS AreaBase) b
-- El indice unico de la tabla deja una sola fila activa por proyecto y periodo.
LEFT JOIN proceso.TMD_PROYECTO_EXCLUIDO e
       ON e.numAnio = p.numAnio AND e.numMes = p.numMes
      AND e.codProyecto = TRIM(g.afe) AND e.flgEstado = 1
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
  AND g.afe IS NOT NULL
  AND g.CostCenter <> '0216';
GO

/* -------------------------------------------------------------------------
   3. Pestania Gasto personal del procesamiento con el codigo del proyecto
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
        g.afe AS codProyecto,
        COUNT(*) OVER () AS numTotalRegistros
    FROM proceso.TMD_GASTO_PERSONAL g
    WHERE g.idePeriodo = @idePeriodo AND g.flgEstado = 1
    ORDER BY g.voucherno, g.ideGastoPersonal
    OFFSET (@numPagina * @numTamanio) ROWS FETCH NEXT @numTamanio ROWS ONLY;
END
GO

/* -------------------------------------------------------------------------
   4. Pestania Resumen del procesamiento (version del script 32)

   Lee la vista, que ahora trae tambien las lineas de proyectos excluidos:
   el resumen sigue mostrando solo lo que entra al costo labor.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_GastoPersonal_Resumen
    @numAnio int,
    @numMes int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo bigint = (SELECT idePeriodo FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes);

    SELECT
        g.txtTipoGasto,
        g.account,
        g.txtLocalName,
        COUNT(*) AS numRegistros,
        SUM(g.localamount) AS montoTotal
    FROM proceso.VW_GASTO_PERSONAL_REPORTE g
    WHERE g.idePeriodo = @idePeriodo
      AND g.flgProyectoExcluido = 0
    GROUP BY g.txtTipoGasto, g.account, g.txtLocalName
    ORDER BY g.txtTipoGasto, g.account;
END
GO
