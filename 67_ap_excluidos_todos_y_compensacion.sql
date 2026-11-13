/* =========================================================================
   67 - Vouchers (AP) excluidos: listado sin filtro de cuentas y exclusion en
        la distribucion de la compensacion

   1. proceso.usp_ApSpring_Listar deja de filtrar por el rango de cuentas de
      gasto (62110010 a 65990070) y por las cuentas excluidas: lista todos los
      vouchers del periodo en SPRING. La exclusion se va a usar tambien en el
      gasto de capital, que no sale de ese rango. Agregar un voucher y
      "Obtener del periodo anterior" validan contra este mismo listado, asi
      que aceptan los vouchers nuevos sin otro cambio.

      El gasto de personal no cambia: su vista (script 59) mantiene el rango
      de cuentas, que es lo que define ese gasto.

   2. proceso.VW_DISTRIBUCION_COMPENSACION_REPORTE deja fuera las lineas de
      los vouchers excluidos del periodo. Es la vista de la que salen las
      hojas BD_DISTRIBUCION_COMPENSACION y DISTRIBUCION_COMPENSACION y los
      cuadros que usan la compensacion. Las lineas siguen en
      proceso.TMD_DISTRIBUCION_COMPENSACION: la pestania de compensacion del
      procesamiento las muestra sin filtrar, igual que el gasto de personal.

   Requiere el script 59.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('proceso.TMD_AP_EXCLUIDO') IS NULL
    THROW 50153, 'Falta proceso.TMD_AP_EXCLUIDO: ejecute antes el script 59.', 1;
GO

/* -------------------------------------------------------------------------
   1. Maestro de vouchers de SPRING

   Una fila por cabecera, sin filtrar por cuenta, estado ni centro de costo.
   Vacio si BD_SPRING no esta disponible.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ApSpring_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS varchar(30))  AS codVoucher,
               CAST(NULL AS varchar(500)) AS txtTitulo,
               CAST(NULL AS varchar(20))  AS txtEstado
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @period varchar(6) = CONCAT(@numAnio, RIGHT(CONCAT('0', @numMes), 2));

    EXEC sp_executesql N'
        SELECT CAST(TRIM(vd.voucherno) AS varchar(30))             AS codVoucher,
               CAST(TRIM(MAX(vh.vouchertitle)) AS varchar(500))    AS txtTitulo,
               CAST(TRIM(MAX(vh.status)) AS varchar(20))           AS txtEstado
        FROM BD_SPRING.dbo.voucherdetail vd
        INNER JOIN BD_SPRING.dbo.voucherheader vh
                ON vh.period = vd.period AND vh.voucherno = vd.voucherno
        WHERE vd.period = @period
        GROUP BY TRIM(vd.voucherno);',
        N'@period varchar(6)', @period = @period;
END
GO

/* -------------------------------------------------------------------------
   2. Distribucion de la compensacion sin los vouchers excluidos

   Misma definicion del script 32 mas la exclusion por voucher del periodo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER VIEW proceso.VW_DISTRIBUCION_COMPENSACION_REPORTE
AS
SELECT  c.ideDistribucionCompensacion, c.idePeriodo, c.period, c.DescripcionLocal,
        c.Proyecto, c.Monto, c.englishname, c.txtCategoria, c.Account, c.voucherno,
        c.vendor, c.invoice, c.ReferenciaFiscal02, c.status
FROM proceso.TMD_DISTRIBUCION_COMPENSACION c
INNER JOIN registro.TMC_PERIODO p ON p.idePeriodo = c.idePeriodo
WHERE c.flgEstado = 1
  AND c.ReferenciaFiscal02 = '33 1 1 1 1'
  AND c.Proyecto IS NOT NULL
  AND c.Proyecto <> '000000000074'
  AND c.status NOT LIKE '%AN%'
  -- Sin referencia fiscal del anio la descripcion es nula y la fila no pasa,
  -- igual que cuando el filtro de anio estaba en el WHERE de la extraccion.
  AND c.DescripcionLocal NOT LIKE '%PRESUPUESTO OPERATIVO%'
  -- Vouchers (AP) excluidos del periodo: salen todas las lineas del voucher.
  AND NOT EXISTS (SELECT 1 FROM proceso.TMD_AP_EXCLUIDO v
                  WHERE v.numAnio = p.numAnio AND v.numMes = p.numMes
                    AND v.codVoucher = TRIM(c.voucherno) AND v.flgEstado = 1);
GO
