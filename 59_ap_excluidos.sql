/* =========================================================================
   59 - Vouchers (AP) excluidos del calculo del costo labor

   El Contador indica por periodo (anio y mes) que vouchers de SPRING quedan
   fuera del calculo del costo labor. Funciona igual que los proyectos
   excluidos del script 50: las lineas se cargan igual en
   proceso.TMD_GASTO_PERSONAL y la exclusion se aplica en los cuadros que se
   calculan a partir de ella.

   La exclusion es por cabecera de voucher, no por linea: la linea no tiene
   identificador propio. Al excluir un voucher salen todas sus lineas del
   periodo, sean de uno o de varios proyectos.

   El listado de vouchers sale de la consulta de referencia que indico el
   analista: rango de cuentas de gasto y las cuentas excluidas, sin filtrar
   por estado ni por centro de costo. Se listan por cabecera, asi que solo
   trae lo que es del voucher (numero, titulo y estado); el proveedor, el
   centro de costo y la cuenta varian entre lineas de un mismo voucher y no
   se pueden mostrar como un valor unico.

   Entran todos los vouchers del rango, empiecen o no con "AP".

   Quitar un voucher es una baja logica. "Obtener del periodo anterior" copia
   los excluidos del ultimo periodo anterior que los tenga.

   La opcion exige su marca de registros completados (script 43).

   Errores nuevos:
     50150  el periodo esta cerrado
     50151  el voucher no existe en SPRING (o SPRING no esta disponible)
     50152  el voucher ya esta excluido en el periodo
     50153  la exclusion no existe

   Requiere el script 53 (vista del gasto de personal).

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

-- Las mismas opciones que exigen el indice filtrado al crearlo y al insertar.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF OBJECT_ID('proceso.VW_GASTO_PERSONAL_REPORTE') IS NULL
    THROW 50153, 'Falta proceso.VW_GASTO_PERSONAL_REPORTE: ejecute antes el script 53.', 1;
GO

/* -------------------------------------------------------------------------
   1. Tabla e indice
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMD_AP_EXCLUIDO') IS NULL
BEGIN
    -- codVoucher es el voucherno de SPRING sin espacios: el calculo lo compara
    -- con TRIM(voucherno) de proceso.TMD_GASTO_PERSONAL.
    CREATE TABLE proceso.TMD_AP_EXCLUIDO(
        ideApExcluido bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        codVoucher varchar(30) NOT NULL,
        txtTitulo varchar(500) NULL,
        txtMotivo varchar(500) NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_AP_EXCLUIDO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_AP_EXCLUIDO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_AP_EXCLUIDO PRIMARY KEY CLUSTERED (ideApExcluido ASC)
    );
END
GO

-- Un voucher activo una sola vez por periodo. Tambien es el indice por el que
-- el calculo busca los excluidos del periodo.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('proceso.TMD_AP_EXCLUIDO')
                 AND name = 'UX_TMD_AP_EXCLUIDO_PERIODO')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_AP_EXCLUIDO_PERIODO
        ON proceso.TMD_AP_EXCLUIDO (numAnio, numMes, codVoucher) WHERE flgEstado = 1;
GO

/* -------------------------------------------------------------------------
   2. Maestro de vouchers de SPRING

   Una fila por cabecera. El periodo de SPRING es 'AAAAMM'. Vacio si
   BD_SPRING no esta disponible, como en el script 45.
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
        LEFT JOIN BD_SPRING.dbo.accountmst am ON am.account = vd.Account
        WHERE vd.period = @period
          AND am.account >= ''62110010''
          AND am.account <= ''65990070''
          AND am.account NOT IN (
              ''63801400'', ''63801410'', ''63801420'', ''63801430'', ''63801440'',
              ''63801450'', ''63801460'', ''63801470'', ''63801480'', ''63801490'',
              ''63801500'', ''63801600'', ''63802070'', ''63802080'', ''63802085'',
              ''63802090'', ''63802095'', ''63803000'', ''63803005'', ''63803010'',
              ''63930040'')
        GROUP BY TRIM(vd.voucherno);',
        N'@period varchar(6)', @period = @period;
END
GO

/* -------------------------------------------------------------------------
   3. Listado del periodo

   Dos conjuntos: si el periodo esta cerrado y los vouchers excluidos.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ApExcluido_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado;

    SELECT e.ideApExcluido, e.codVoucher, e.txtTitulo, e.txtMotivo,
           e.txtUsuarioCreacion AS txtUsuario, e.fecCreacion AS fecRegistro
    FROM proceso.TMD_AP_EXCLUIDO e
    WHERE e.numAnio = @numAnio AND e.numMes = @numMes AND e.flgEstado = 1
    ORDER BY e.codVoucher;
END
GO

/* -------------------------------------------------------------------------
   4. Busqueda de vouchers de SPRING para excluir

   Por numero o por titulo sin distinguir tildes, hasta 50 resultados. No
   ofrece los que ya estan excluidos en el periodo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ApExcluido_Buscar
    @numAnio     int,
    @numMes      int,
    @txtCriterio varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- El criterio es texto literal: sus comodines de LIKE no cuentan como tales.
    DECLARE @patron varchar(400) =
        '%' + REPLACE(REPLACE(REPLACE(ISNULL(TRIM(@txtCriterio), ''), '[', '[[]'), '%', '[%]'), '_', '[_]') + '%';

    CREATE TABLE #ap (codVoucher varchar(30) NOT NULL PRIMARY KEY,
                      txtTitulo varchar(500) NULL,
                      txtEstado varchar(20) NULL);
    INSERT INTO #ap (codVoucher, txtTitulo, txtEstado)
        EXEC proceso.usp_ApSpring_Listar @numAnio, @numMes;

    SELECT TOP (50) s.codVoucher, s.txtTitulo, s.txtEstado
    FROM #ap s
    WHERE (s.codVoucher LIKE @patron
           OR ISNULL(s.txtTitulo, '') COLLATE Latin1_General_CI_AI LIKE @patron COLLATE Latin1_General_CI_AI)
      AND NOT EXISTS (SELECT 1 FROM proceso.TMD_AP_EXCLUIDO e
                      WHERE e.numAnio = @numAnio AND e.numMes = @numMes
                        AND e.codVoucher = s.codVoucher AND e.flgEstado = 1)
    ORDER BY s.codVoucher;
END
GO

/* -------------------------------------------------------------------------
   5. Agregar un voucher al periodo
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ApExcluido_Agregar
    @numAnio    int,
    @numMes     int,
    @codVoucher varchar(30),
    @txtMotivo  varchar(500) = NULL,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50150, 'El periodo esta cerrado: sus vouchers excluidos no se pueden modificar.', 1;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50151, 'El voucher no existe en SPRING (BD_SPRING no esta disponible).', 1;

    SET @codVoucher = TRIM(@codVoucher);

    CREATE TABLE #ap (codVoucher varchar(30) NOT NULL PRIMARY KEY,
                      txtTitulo varchar(500) NULL,
                      txtEstado varchar(20) NULL);
    INSERT INTO #ap (codVoucher, txtTitulo, txtEstado)
        EXEC proceso.usp_ApSpring_Listar @numAnio, @numMes;

    IF NOT EXISTS (SELECT 1 FROM #ap WHERE codVoucher = @codVoucher)
        THROW 50151, 'El numero de voucher no existe en SPRING para el periodo.', 1;

    DECLARE @txtTitulo varchar(500) = (SELECT txtTitulo FROM #ap WHERE codVoucher = @codVoucher);

    IF EXISTS (SELECT 1 FROM proceso.TMD_AP_EXCLUIDO
               WHERE numAnio = @numAnio AND numMes = @numMes AND codVoucher = @codVoucher AND flgEstado = 1)
        THROW 50152, 'El voucher ya esta excluido en el periodo.', 1;

    INSERT INTO proceso.TMD_AP_EXCLUIDO
           (numAnio, numMes, codVoucher, txtTitulo, txtMotivo, flgEstado, txtUsuarioCreacion)
    VALUES (@numAnio, @numMes, @codVoucher, @txtTitulo, NULLIF(TRIM(@txtMotivo), ''), 1, @txtUsuario);

    SELECT CAST(SCOPE_IDENTITY() AS bigint) AS ideApExcluido;
END
GO

/* -------------------------------------------------------------------------
   6. Quitar un voucher del periodo (baja logica)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ApExcluido_Quitar
    @ideApExcluido bigint,
    @txtUsuario    varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @numAnio int, @numMes int;
    SELECT @numAnio = numAnio, @numMes = numMes
    FROM proceso.TMD_AP_EXCLUIDO
    WHERE ideApExcluido = @ideApExcluido AND flgEstado = 1;

    IF @numAnio IS NULL
        THROW 50153, 'El voucher excluido indicado no existe.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50150, 'El periodo esta cerrado: sus vouchers excluidos no se pueden modificar.', 1;

    UPDATE proceso.TMD_AP_EXCLUIDO
    SET flgEstado = 0,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE ideApExcluido = @ideApExcluido;
END
GO

/* -------------------------------------------------------------------------
   7. Obtener del periodo anterior

   Copia los excluidos del ultimo periodo anterior que los tenga (no
   necesariamente el mes previo), salvo los que ya estan en el periodo.
   Un voucher es de un periodo: se copia solo si tambien existe en SPRING
   para el periodo destino.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ApExcluido_Replicar
    @numAnio    int,
    @numMes     int,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50150, 'El periodo esta cerrado: sus vouchers excluidos no se pueden modificar.', 1;

    DECLARE @numAnioOrigen int, @numMesOrigen int, @numCopiados int = 0;

    SELECT TOP (1) @numAnioOrigen = numAnio, @numMesOrigen = numMes
    FROM proceso.TMD_AP_EXCLUIDO
    WHERE flgEstado = 1 AND numAnio * 100 + numMes < @numAnio * 100 + @numMes
    ORDER BY numAnio DESC, numMes DESC;

    IF @numAnioOrigen IS NOT NULL
    BEGIN
        CREATE TABLE #ap (codVoucher varchar(30) NOT NULL PRIMARY KEY,
                          txtTitulo varchar(500) NULL,
                          txtEstado varchar(20) NULL);
        INSERT INTO #ap (codVoucher, txtTitulo, txtEstado)
            EXEC proceso.usp_ApSpring_Listar @numAnio, @numMes;

        INSERT INTO proceso.TMD_AP_EXCLUIDO
               (numAnio, numMes, codVoucher, txtTitulo, txtMotivo, flgEstado, txtUsuarioCreacion)
        SELECT @numAnio, @numMes, o.codVoucher, s.txtTitulo, o.txtMotivo, 1, @txtUsuario
        FROM proceso.TMD_AP_EXCLUIDO o
        JOIN #ap s ON s.codVoucher = o.codVoucher
        WHERE o.numAnio = @numAnioOrigen AND o.numMes = @numMesOrigen AND o.flgEstado = 1
          AND NOT EXISTS (SELECT 1 FROM proceso.TMD_AP_EXCLUIDO d
                          WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                            AND d.codVoucher = o.codVoucher AND d.flgEstado = 1);
        SET @numCopiados = @@ROWCOUNT;
    END

    SELECT @numAnioOrigen AS numAnioOrigen, @numMesOrigen AS numMesOrigen, @numCopiados AS numCopiados;
END
GO

/* -------------------------------------------------------------------------
   8. La vista marca las lineas de vouchers excluidos

   Misma definicion del script 53 mas flgApExcluido. Las lineas siguen
   saliendo: la hoja sin filtrar del procesamiento las necesita.
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
        CASE WHEN e.ideProyectoExcluido IS NULL THEN 0 ELSE 1 END AS flgProyectoExcluido,
        CASE WHEN v.ideApExcluido IS NULL THEN 0 ELSE 1 END AS flgApExcluido
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
-- Igual para el voucher: una sola fila activa por voucher y periodo.
LEFT JOIN proceso.TMD_AP_EXCLUIDO v
       ON v.numAnio = p.numAnio AND v.numMes = p.numMes
      AND v.codVoucher = TRIM(g.voucherno) AND v.flgEstado = 1
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
   9. Opcion de menu del Contador y marca de registros completados

   Igual que los scripts 33, 36 y 50: idempotente y sin filtrar por flgEstado,
   para no devolver la opcion a un perfil al que el administrador se la quito.
   ------------------------------------------------------------------------- */

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'AP_EXCLUIDOS', 'Vouchers (AP) excluidos', '/costo-labor/ap-excluidos',
       'bi bi-receipt-cutoff', p.ideOpcion, 12, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'AP_EXCLUIDOS');

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'COSTO_LABOR'), ('CONTADOR', 'AP_EXCLUIDOS')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);

INSERT INTO proceso.TMC_REGISTRO_PREVIO (codOpcion, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'AP_EXCLUIDOS', 75, 1, @usuario
WHERE NOT EXISTS (SELECT 1 FROM proceso.TMC_REGISTRO_PREVIO
                  WHERE codOpcion = 'AP_EXCLUIDOS' AND flgEstado = 1);
GO
