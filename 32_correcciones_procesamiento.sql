/* =========================================================================
   32 - Correcciones del procesamiento (documento del 27/09)

   1. La extraccion de BD_SPRING ya no filtra: trae todo el periodo. Los
      filtros pasan a dos vistas que leen los reportes:
        proceso.VW_GASTO_PERSONAL_REPORTE
        proceso.VW_DISTRIBUCION_COMPENSACION_REPORTE
      Las pestanias de gasto de personal y de distribucion de compensacion
      muestran lo extraido sin filtrar; los reportes, lo filtrado.

      Las tablas guardan ahora las columnas que esos filtros necesitan (afe,
      ReferenciaFiscal02 y estado del voucher) y los montos pasan a
      decimal(18,2): sin filtros llegan lineas de mas de 100 millones, que no
      caben en decimal(10,2).

   2. HH por proyecto: la tabla proceso.TMC_CARGO_NIVEL fija el departamento
      y el nivel de los cargos de la Gerencia de Operaciones que no siguen la
      regla general; proceso.ufn_ClasificarCargo aplica ambas. El reporte que
      la usa se rehace en el script 34, junto con los demas cambios de los
      reportes.

   3. El proyecto 000000000104 (SAN JUAN FA) estaba escrito con 10 digitos en
      la clasificacion FA y nunca coincidia.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Columnas para los filtros y montos sin tope

   Las filas ya procesadas pasaron los filtros al extraerse: se completan con
   valores que las vistas aceptan, para que los periodos cerrados sigan
   mostrando lo mismo. Solo se hace al agregar la columna, para no tocar
   filas nuevas si el script se vuelve a correr.
   ------------------------------------------------------------------------- */

IF COL_LENGTH('proceso.TMD_GASTO_PERSONAL', 'afe') IS NULL
BEGIN
    ALTER TABLE proceso.TMD_GASTO_PERSONAL ADD afe varchar(15) NULL;
    EXEC (N'UPDATE proceso.TMD_GASTO_PERSONAL SET afe = '''' WHERE afe IS NULL;');
END
GO

IF COL_LENGTH('proceso.TMD_DISTRIBUCION_COMPENSACION', 'ReferenciaFiscal02') IS NULL
BEGIN
    ALTER TABLE proceso.TMD_DISTRIBUCION_COMPENSACION ADD
        ReferenciaFiscal02 varchar(20) NULL,
        status             varchar(10) NULL;
    EXEC (N'UPDATE proceso.TMD_DISTRIBUCION_COMPENSACION
            SET ReferenciaFiscal02 = ''33 1 1 1 1'', status = ''''
            WHERE ReferenciaFiscal02 IS NULL;');
END
GO

ALTER TABLE proceso.TMD_GASTO_PERSONAL ALTER COLUMN localamount decimal(18,2) NOT NULL;
ALTER TABLE proceso.TMD_DISTRIBUCION_COMPENSACION ALTER COLUMN Monto decimal(18,2) NOT NULL;
ALTER TABLE proceso.TMD_DISTRIBUCION_COMPENSACION ALTER COLUMN Account varchar(30) NULL;
ALTER TABLE proceso.TMD_DISTRIBUCION_COMPENSACION ALTER COLUMN DescripcionLocal varchar(1000) NULL;
GO

/* -------------------------------------------------------------------------
   2. Filtros de los reportes

   Son los mismos que tenia la extraccion (script 28), aplicados sobre lo
   guardado. Una comparacion con NULL descarta la fila, igual que antes.
   ------------------------------------------------------------------------- */

CREATE OR ALTER VIEW proceso.VW_GASTO_PERSONAL_REPORTE
AS
SELECT  g.ideGastoPersonal, g.idePeriodo, g.voucherno, g.txtTipoGasto, g.voucherline,
        g.vendor, g.status, g.txtLocalName, g.localamount, g.idePersona, g.txtNombreCompleto,
        g.account, g.Documento, g.Area, g.Departamento, g.Cargo, g.CostCenter,
        g.CentroCostos, g.period, g.afe
FROM proceso.TMD_GASTO_PERSONAL g
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

CREATE OR ALTER VIEW proceso.VW_DISTRIBUCION_COMPENSACION_REPORTE
AS
SELECT  c.ideDistribucionCompensacion, c.idePeriodo, c.period, c.DescripcionLocal,
        c.Proyecto, c.Monto, c.englishname, c.txtCategoria, c.Account, c.voucherno,
        c.vendor, c.invoice, c.ReferenciaFiscal02, c.status
FROM proceso.TMD_DISTRIBUCION_COMPENSACION c
WHERE c.flgEstado = 1
  AND c.ReferenciaFiscal02 = '33 1 1 1 1'
  AND c.Proyecto IS NOT NULL
  AND c.Proyecto <> '000000000074'
  AND c.status NOT LIKE '%AN%'
  -- Sin referencia fiscal del anio la descripcion es nula y la fila no pasa,
  -- igual que cuando el filtro de anio estaba en el WHERE de la extraccion.
  AND c.DescripcionLocal NOT LIKE '%PRESUPUESTO OPERATIVO%';
GO

/* -------------------------------------------------------------------------
   3. Departamento y nivel por cargo para el HH por proyecto

   La regla general (usp_Reporte_CostoLabor, CTE EMPLEADOS) toma el nivel del
   inicio del cargo (GERENTE, JEFE, ASISTENTE; el resto es subordinado) y el
   departamento del que trae SPRING. Aqui van los cargos que no la siguen,
   segun el HH por proyecto del contador. Se comparan sin distinguir
   mayusculas ni tildes.
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMC_CARGO_NIVEL') IS NULL
BEGIN
    CREATE TABLE proceso.TMC_CARGO_NIVEL(
        ideCargoNivel bigint IDENTITY(1,1) NOT NULL,
        txtCargo varchar(200) NOT NULL,
        codDepartamento varchar(10) NOT NULL,
        codNivel varchar(20) NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMC_CARGO_NIVEL_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMC_CARGO_NIVEL_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMC_CARGO_NIVEL PRIMARY KEY CLUSTERED (ideCargoNivel ASC),
        CONSTRAINT CK_TMC_CARGO_NIVEL_DEPARTAMENTO CHECK (codDepartamento IN ('DGO', 'DIP', 'DPCM', 'RRCC', 'GO')),
        CONSTRAINT CK_TMC_CARGO_NIVEL_NIVEL CHECK (codNivel IN ('GERENTE', 'JEFE', 'ADMINISTRATIVO', 'SUBORDINADO'))
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMC_CARGO_NIVEL_txtCargo
        ON proceso.TMC_CARGO_NIVEL (txtCargo) WHERE flgEstado = 1;
END
GO

DECLARE @cargos TABLE (txtCargo varchar(200), codDepartamento varchar(10), codNivel varchar(20));

INSERT INTO @cargos (txtCargo, codDepartamento, codNivel) VALUES
    -- SPRING lo ubica en Gestion de Obras.
    ('JEFE DE DEPARTAMENTO DE POST CIERRE Y MANTENIMIENTO', 'DPCM', 'JEFE'),
    -- SPRING los ubica en Operaciones o sin departamento.
    ('ASISTENTE DE GESTION DE OBRAS.',                     'DGO',  'ADMINISTRATIVO'),
    ('ESPECIALISTA EN GESTION DE OBRAS',                   'DGO',  'SUBORDINADO'),
    ('ESPECIALISTA EN POST CIERRE Y MANTENIMIENTO',        'DPCM', 'SUBORDINADO'),
    -- Administrativo del departamento aunque el cargo no empiece por ASISTENTE.
    ('SUPERVISOR DE EJECUCION DE INVERSIONES',             'DIP',  'ADMINISTRATIVO');

INSERT INTO proceso.TMC_CARGO_NIVEL (txtCargo, codDepartamento, codNivel, flgEstado, txtUsuarioCreacion)
SELECT c.txtCargo, c.codDepartamento, c.codNivel, 1, 'SYSTEM_COSTOLABOR'
FROM @cargos c
WHERE NOT EXISTS (SELECT 1 FROM proceso.TMC_CARGO_NIVEL t
                  WHERE t.txtCargo COLLATE Latin1_General_CI_AI = c.txtCargo COLLATE Latin1_General_CI_AI);
GO

/*
   Departamento y nivel de un cargo de la Gerencia de Operaciones. Primero
   manda TMC_CARGO_NIVEL; sin fila ahi, la regla general. Fuera de esa
   gerencia no devuelve fila: su gasto no es del CORE 2, y repartirlo por
   proyecto lo contaria dos veces.

   La tabla se compara sin tildes ni mayusculas, y su indice unico si las
   distingue: si alguien carga el mismo cargo con y sin tilde, se toma uno solo.

   La usan el HH por proyecto (script 34) y la jefatura de cada trabajador en
   el registro de horas (script 35), para que ambos ubiquen igual a cada uno.
*/
CREATE OR ALTER FUNCTION proceso.ufn_ClasificarCargo (
    @Area         varchar(200),
    @Departamento varchar(200),
    @Cargo        varchar(200)
)
RETURNS TABLE
AS
RETURN
    SELECT
        COALESCE(cn.codDepartamento,
            CASE
                WHEN @Cargo COLLATE Latin1_General_CI_AI LIKE '%RELACIONES COMUNITARIAS%'
                  OR @Cargo COLLATE Latin1_General_CI_AI LIKE 'GESTOR SOCIAL%' THEN 'RRCC'
                WHEN @Departamento COLLATE Latin1_General_CI_AI = 'GESTION DE OBRAS' THEN 'DGO'
                WHEN @Departamento COLLATE Latin1_General_CI_AI = 'INGENIERIA DE PROYECTOS' THEN 'DIP'
                WHEN @Departamento COLLATE Latin1_General_CI_AI = 'POST CIERRE Y MANTENIMIENTO' THEN 'DPCM'
                ELSE 'GO'
            END) AS codDepartamento,
        COALESCE(cn.codNivel,
            CASE
                WHEN @Cargo COLLATE Latin1_General_CI_AI LIKE 'GERENTE%' THEN 'GERENTE'
                WHEN @Cargo COLLATE Latin1_General_CI_AI LIKE 'JEFE%' THEN 'JEFE'
                WHEN @Cargo COLLATE Latin1_General_CI_AI LIKE 'ASISTENTE%' THEN 'ADMINISTRATIVO'
                ELSE 'SUBORDINADO'
            END) AS codNivel
    FROM (SELECT 1 AS uno) AS fija
    OUTER APPLY (SELECT TOP (1) t.codDepartamento, t.codNivel
                 FROM proceso.TMC_CARGO_NIVEL t
                 WHERE t.txtCargo COLLATE Latin1_General_CI_AI = TRIM(@Cargo) COLLATE Latin1_General_CI_AI
                   AND t.flgEstado = 1
                 ORDER BY t.ideCargoNivel) AS cn
    WHERE @Area COLLATE Latin1_General_CI_AI = 'GERENCIA DE OPERACIONES';
GO

/* -------------------------------------------------------------------------
   4. Pestania 3: el resumen del gasto de personal es un reporte, con filtros
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
    GROUP BY g.txtTipoGasto, g.account, g.txtLocalName
    ORDER BY g.txtTipoGasto, g.account;
END
GO

/* -------------------------------------------------------------------------
   5. Extraccion sin filtros (CA-02 de la HU-008, rehecho)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_Periodo_Procesar
    @numAnio int,
    @numMes int,
    @txtUsuario varchar(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50010, 'La base de datos BD_SPRING no esta disponible en este servidor.', 1;

    DECLARE @idePeriodo bigint, @flgEstado int;

    SELECT @idePeriodo = idePeriodo, @flgEstado = flgEstado
    FROM registro.TMC_PERIODO
    WHERE numAnio = @numAnio AND numMes = @numMes;

    IF @flgEstado = 2
        THROW 50011, 'El periodo esta cerrado. Debe reaperturarlo antes de volver a procesar.', 1;

    DECLARE @periodo varchar(10) = CONCAT(@numAnio, RIGHT('0' + CAST(@numMes AS varchar(2)), 2));
    DECLARE @anio varchar(4) = CAST(@numAnio AS varchar(4));

    BEGIN TRY
        BEGIN TRANSACTION;

        -- El periodo puede no existir todavia: el procesamiento lo abre.
        IF @idePeriodo IS NULL
        BEGIN
            INSERT INTO registro.TMC_PERIODO (numAnio, numMes, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, 1, @txtUsuario);
            SET @idePeriodo = SCOPE_IDENTITY();
        END

        DELETE FROM proceso.TMD_GASTO_PERSONAL WHERE idePeriodo = @idePeriodo;
        DELETE FROM proceso.TMD_DISTRIBUCION_COMPENSACION WHERE idePeriodo = @idePeriodo;

        /* ---------------------------------------------- Gasto de personal */
        INSERT INTO proceso.TMD_GASTO_PERSONAL (
            idePeriodo, voucherno, txtTipoGasto, voucherline, vendor, status, txtLocalName,
            localamount, idePersona, txtNombreCompleto, account, Documento, Area, Departamento,
            Cargo, CostCenter, CentroCostos, period, afe, flgEstado, txtUsuarioCreacion)
        EXEC sp_executesql N'
            SELECT
                @idePeriodo,
                TRIM(vd.voucherno),
                CASE
                    -- Estas cuatro cuentas solo son reembolso en el centro de costo 111.
                    WHEN am.account IN (''63112040'', ''64310010'', ''64320010'', ''65990070'')
                         AND vd.CostCenter = ''111'' THEN ''Reembolso y Proinv.''
                    WHEN am.account IN (
                        ''62110010'', ''62120010'', ''62130010'', ''62140010'', ''62150010'',
                        ''62200010'', ''62500010'', ''62500031'', ''62500050'', ''62600010'',
                        ''62710010'', ''62720010'', ''62750010'', ''62910010'', ''62920010''
                    ) THEN ''Gasto de Personal''
                    WHEN am.account IN (
                        ''62200020'', ''62200030'', ''62200040'', ''62200050'',
                        ''62300010'', ''62400010'', ''62500020'', ''62500030'', ''62930010''
                    ) THEN ''Bonos y Otros''
                    WHEN am.account IN (''63910010'') THEN ''Gastos Financiero''
                    WHEN am.account IN (''65514050'', ''65514060'') THEN ''Otros''
                    WHEN am.account IN (
                        ''62500040'', ''62730010'', ''62740010'', ''62800010'',
                        ''63111010'', ''63112010'', ''63112020'', ''63112030'', ''63112040'', ''63112050'',
                        ''63120010'', ''63130010'', ''63140010'', ''63150010'',
                        ''63210010'', ''63210020'', ''63220010'', ''63220020'', ''63230010'', ''63230020'', ''63230030'',
                        ''63240010'', ''63240020'', ''63250010'', ''63250020'', ''63260010'', ''63260020'', ''63270010'', ''63270020'',
                        ''63290010'', ''63290020'', ''63300010'',
                        ''63410010'', ''63420010'', ''63422010'', ''63430010'', ''63430020'', ''63430030'', ''63430040'', ''63440010'', ''63450010'',
                        ''63510010'', ''63520010'', ''63530010'', ''63540010'', ''63560010'',
                        ''63610010'', ''63620010'', ''63630010'', ''63640010'', ''63640020'', ''63650010'', ''63660010'', ''63670010'',
                        ''63710010'', ''63710020'', ''63710030'', ''63720010'', ''63730010'',
                        ''63801010'', ''63801020'', ''63801030'', ''63801040'', ''63801050'', ''63801060'', ''63801070'', ''63801080'', ''63801090'',
                        ''63802010'', ''63802020'', ''63802030'', ''63802040'', ''63802050'', ''63802060'',
                        ''63803020'', ''63803030'', ''63803040'',
                        ''63920010'', ''63930020'', ''63930050'', ''63930060'', ''63930090'',
                        ''64110010'', ''64120010'', ''64130010'', ''64140010'', ''64150010'', ''64160010'', ''64190010'', ''64190020'', ''64200010'',
                        ''64310010'', ''64320010'', ''64330010'', ''64340010'', ''64390010'', ''64410010'', ''64420010'', ''64430010'',
                        ''65100010'', ''65100020'', ''65100030'', ''65100040'', ''65100050'', ''65100060'', ''65100070'',
                        ''65200010'', ''65300010'', ''65400010'', ''65514030'',
                        ''65600010'', ''65600020'', ''65600030'', ''65600031'', ''65600040'', ''65600050'', ''65600060'', ''65600070'', ''65600080'', ''65600090'',
                        ''65800010'', ''65910010'',
                        ''65990010'', ''65990020'', ''65990030'', ''65990040'', ''65990050'', ''65990060'', ''65990070'', ''65990080''
                    ) THEN ''Gasto Operativo''
                    ELSE ''Categoria Desconocida''
                END,
                vd.voucherline,
                vd.vendor,
                TRIM(vh.status),
                TRIM(am.localname),
                ISNULL(vd.localamount, 0),
                pm.Persona,
                TRIM(pm.NombreCompleto),
                TRIM(am.account),
                TRIM(pm.Documento),
                TRIM(hrdiv.DescripcionLarga),
                TRIM(hrdep.Descripcion),
                TRIM(hre.Descripcion),
                TRIM(vd.CostCenter),
                TRIM(em.CentroCostos),
                TRIM(vd.period),
                TRIM(vd.afe),
                1,
                @txtUsuario
            FROM BD_SPRING.dbo.voucherdetail AS vd
            INNER JOIN BD_SPRING.dbo.voucherheader AS vh
                ON vh.period = vd.period AND vh.voucherno = vd.voucherno
            LEFT JOIN BD_SPRING.dbo.accountmst AS am ON am.account = vd.Account
            LEFT JOIN BD_SPRING.dbo.PersonaMast AS pm ON pm.Persona = vd.vendor
            LEFT JOIN BD_SPRING.dbo.EmpleadoMast AS em ON em.Empleado = pm.Persona
            LEFT JOIN BD_SPRING.dbo.HR_PuestoEmpresa AS hre ON hre.CodigoPuesto = em.CodigoCargo
            LEFT JOIN BD_SPRING.dbo.HR_Departamento AS hrdep ON hrdep.Departamento = em.DepartamentoOperacional
            LEFT JOIN BD_SPRING.dbo.HR_Division AS hrdiv ON hrdiv.Division = em.Division
            -- Correcciones 27/09: se trae todo el periodo. Los filtros de
            -- estado, cuentas, AFE y centro de costo pasaron a la vista
            -- proceso.VW_GASTO_PERSONAL_REPORTE, que es la que leen los reportes.
            WHERE vd.period = @periodo;',
            N'@idePeriodo bigint, @periodo varchar(10), @txtUsuario varchar(30)',
            @idePeriodo = @idePeriodo, @periodo = @periodo, @txtUsuario = @txtUsuario;

        /* ------------------------------------------ Distribucion compensacion */
        INSERT INTO proceso.TMD_DISTRIBUCION_COMPENSACION (
            idePeriodo, period, DescripcionLocal, Proyecto, Monto, englishname, txtCategoria,
            Account, voucherno, vendor, invoice, ReferenciaFiscal02, status, flgEstado, txtUsuarioCreacion)
        EXEC sp_executesql N'
            SELECT
                @idePeriodo,
                TRIM(vDet.period),
                TRIM(AcRef.DescripcionLocal),
                TRIM(vDet.afe),
                ISNULL(vDet.localamount, 0),
                TRIM(a.englishname),
                CASE
                    WHEN RTRIM(vDet.afe) IN (
                        ''000000000001'', ''000000000007'', ''000000000009'', ''000000000013'',
                        ''000000000027'', ''000000000029'', ''000000000040'', ''000000000041'',
                        ''000000000057'', ''000000000058'', ''000000000065'', ''000000000104'',
                        ''000000202009'', ''000000203008'', ''000000210033'', ''000000210034'',
                        ''000000210035'', ''000000210045'', ''000000220014'', ''000000220017'',
                        ''000000230073''
                    ) THEN ''FA''
                    WHEN RTRIM(vDet.afe) IN (
                        ''000000000018'', ''000000000019'', ''000000000020'', ''000000000021'',
                        ''000000000022'', ''000000000023'', ''000000321016'', ''000000000103'',
                        ''000000210043'', ''000000302002'', ''000000302004'', ''000000302006'',
                        ''000000302007'', ''000000310031'', ''000000310032'', ''000000321001'',
                        ''000000340001'', ''000000340002'', ''000000350001'', ''000000364001'',
                        ''000000632025'', ''000000632026''
                    ) THEN ''PAR''
                    WHEN RTRIM(vDet.afe) IN (''000000000074'') THEN ''TUCARI''
                    WHEN RTRIM(vDet.afe) IN (''000000000105'', ''000000000106'', ''000000000107'') THEN ''TUQUIAR''
                    ELSE ''Categoria Desconocida''
                END,
                TRIM(vDet.Account),
                TRIM(vDet.voucherno),
                vDet.vendor,
                TRIM(vDet.invoice),
                TRIM(vDet.ReferenciaFiscal02),
                TRIM(vh.status),
                1,
                @txtUsuario
            FROM BD_SPRING.dbo.voucherdetail AS vDet
            -- Anio, tipo y version eligen la referencia fiscal vigente: van en el
            -- ON y no en el WHERE, para no descartar las lineas que no tienen una.
            LEFT JOIN BD_SPRING.dbo.AC_ReferenciaFiscal AS AcRef
                ON vDet.ReferenciaFiscal03 = AcRef.ReferenciaFiscal
               AND AcRef.Ano = @anio
               AND AcRef.TipoReferenciaFiscal = ''03''
               AND AcRef.Version = ''1''
            LEFT JOIN BD_SPRING.dbo.voucherheader AS vh
                ON vh.period = vDet.period AND vh.voucherno = vDet.voucherno
            LEFT JOIN BD_SPRING.dbo.afemst AS a ON a.afe = vDet.afe
            LEFT JOIN BD_SPRING.dbo.accountmst AS am ON am.account = vDet.Account
            -- Correcciones 27/09: se trae todo el periodo. Los filtros pasaron a
            -- la vista proceso.VW_DISTRIBUCION_COMPENSACION_REPORTE.
            WHERE vDet.period = @periodo;',
            N'@idePeriodo bigint, @periodo varchar(10), @anio varchar(4), @txtUsuario varchar(30)',
            @idePeriodo = @idePeriodo, @periodo = @periodo, @anio = @anio, @txtUsuario = @txtUsuario;

        UPDATE registro.TMC_PERIODO
        SET fecProcesamiento = GETDATE(),
            txtUsuarioProcesamiento = @txtUsuario,
            fecActualizacion = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE idePeriodo = @idePeriodo;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    EXEC proceso.usp_Periodo_ObtenerEstado @numAnio = @numAnio, @numMes = @numMes;
END
GO
