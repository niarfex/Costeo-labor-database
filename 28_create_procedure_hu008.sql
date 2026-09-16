/* =========================================================================
   HU-008 - Procesamiento de periodo

   CA-01 estado del periodo y acciones, CA-02 motor de extraccion desde
   BD_SPRING, CA-03 pestanias de resultados.

   Las consultas a BD_SPRING van dentro de sp_executesql y detras de un
   guarda DB_ID('BD_SPRING'): en un ambiente sin esa base el script se crea
   igual y el procedimiento avisa en vez de romper la compilacion.

   Idempotente: CREATE OR ALTER en todo.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   Estado del periodo (CA-01)

   Devuelve una sola fila aunque el periodo todavia no exista: la pantalla
   necesita mostrar el estado Pendiente antes del primer procesamiento.
   ------------------------------------------------------------------------- */
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
        ISNULL((SELECT COUNT(*) FROM proceso.TMD_GASTO_PERSONAL g
                WHERE g.idePeriodo = p.idePeriodo AND g.flgEstado = 1), 0) AS numGastoPersonal,
        ISNULL((SELECT COUNT(*) FROM proceso.TMD_DISTRIBUCION_COMPENSACION c
                WHERE c.idePeriodo = p.idePeriodo AND c.flgEstado = 1), 0) AS numCompensacion
    FROM (SELECT 1 AS uno) AS fija
    LEFT JOIN registro.TMC_PERIODO p
           ON p.numAnio = @numAnio AND p.numMes = @numMes;
END
GO

/* -------------------------------------------------------------------------
   CA-02: motor de procesamiento

   Reprocesable: borra lo del periodo y lo vuelve a insertar. Todo en una
   transaccion, para que un fallo a mitad no deje el periodo con la mitad de
   los datos nuevos y la mitad de los viejos.
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
            Cargo, CostCenter, CentroCostos, period, flgEstado, txtUsuarioCreacion)
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
                vd.localamount,
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
            WHERE vd.period = @periodo
              AND vh.status = ''PR''
              -- Rango de cuentas como texto: asi el indice se puede usar.
              AND am.account >= ''62110010''
              AND am.account <= ''65990070''
              AND am.account NOT IN (
                  ''63801400'', ''63801410'', ''63801420'', ''63801430'', ''63801440'',
                  ''63801450'', ''63801460'', ''63801470'', ''63801480'', ''63801490'',
                  ''63801500'', ''63801600'', ''63802070'', ''63802080'', ''63802085'',
                  ''63802090'', ''63802095'', ''63803000'', ''63803005'', ''63803010'',
                  ''63930040''
              )
              AND vd.afe <> ''000000505049''
              AND vd.CostCenter <> ''0216'';',
            N'@idePeriodo bigint, @periodo varchar(10), @txtUsuario varchar(30)',
            @idePeriodo = @idePeriodo, @periodo = @periodo, @txtUsuario = @txtUsuario;

        /* ------------------------------------------ Distribucion compensacion */
        INSERT INTO proceso.TMD_DISTRIBUCION_COMPENSACION (
            idePeriodo, period, DescripcionLocal, Proyecto, Monto, englishname, txtCategoria,
            Account, voucherno, vendor, invoice, flgEstado, txtUsuarioCreacion)
        EXEC sp_executesql N'
            SELECT
                @idePeriodo,
                TRIM(vDet.period),
                TRIM(AcRef.DescripcionLocal),
                TRIM(vDet.afe),
                vDet.localamount,
                TRIM(a.englishname),
                CASE
                    WHEN RTRIM(vDet.afe) IN (
                        ''000000000001'', ''000000000007'', ''000000000009'', ''000000000013'',
                        ''000000000027'', ''000000000029'', ''000000000040'', ''000000000041'',
                        ''000000000057'', ''000000000058'', ''000000000065'', ''0000000104'',
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
                1,
                @txtUsuario
            FROM BD_SPRING.dbo.voucherdetail AS vDet
            LEFT JOIN BD_SPRING.dbo.AC_ReferenciaFiscal AS AcRef
                ON vDet.ReferenciaFiscal03 = AcRef.ReferenciaFiscal
            LEFT JOIN BD_SPRING.dbo.voucherheader AS vh
                ON vh.period = vDet.period AND vh.voucherno = vDet.voucherno
            LEFT JOIN BD_SPRING.dbo.afemst AS a ON a.afe = vDet.afe
            LEFT JOIN BD_SPRING.dbo.accountmst AS am ON am.account = vDet.Account
            WHERE AcRef.Ano = @anio
              AND vDet.period = @periodo
              AND AcRef.TipoReferenciaFiscal = ''03''
              AND AcRef.Version = ''1''
              AND vDet.ReferenciaFiscal02 = ''33 1 1 1 1''
              AND vDet.afe IS NOT NULL
              AND vDet.afe <> ''000000000074''
              AND vh.status NOT LIKE ''%AN%''
              AND AcRef.DescripcionLocal NOT LIKE ''%PRESUPUESTO OPERATIVO%'';',
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

/* -------------------------------------------------------------------------
   CA-01: aprobar (cerrar) y reaperturar
   ------------------------------------------------------------------------- */
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
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE idePeriodo = @idePeriodo;

    EXEC proceso.usp_Periodo_ObtenerEstado @numAnio = @numAnio, @numMes = @numMes;
END
GO

/* -------------------------------------------------------------------------
   CA-03 pestania 1: gasto de personal, paginado
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
        g.Documento, g.Area, g.Departamento, g.Cargo,
        COUNT(*) OVER () AS numTotalRegistros
    FROM proceso.TMD_GASTO_PERSONAL g
    WHERE g.idePeriodo = @idePeriodo AND g.flgEstado = 1
    ORDER BY g.voucherno, g.ideGastoPersonal
    OFFSET (@numPagina * @numTamanio) ROWS FETCH NEXT @numTamanio ROWS ONLY;
END
GO

/* -------------------------------------------------------------------------
   CA-03 pestania 2: distribucion de compensacion, paginado
   ------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE proceso.usp_DistribucionCompensacion_Listar
    @numAnio int,
    @numMes int,
    @numPagina int = 0,
    @numTamanio int = 20
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo bigint = (SELECT idePeriodo FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes);

    SELECT
        c.ideDistribucionCompensacion, c.DescripcionLocal, c.Proyecto, c.Monto,
        c.englishname, c.txtCategoria, c.Account, c.voucherno, c.vendor, c.invoice,
        COUNT(*) OVER () AS numTotalRegistros
    FROM proceso.TMD_DISTRIBUCION_COMPENSACION c
    WHERE c.idePeriodo = @idePeriodo AND c.flgEstado = 1
    ORDER BY c.txtCategoria, c.Proyecto, c.ideDistribucionCompensacion
    OFFSET (@numPagina * @numTamanio) ROWS FETCH NEXT @numTamanio ROWS ONLY;
END
GO

/* -------------------------------------------------------------------------
   CA-01: opcion de menu de la pantalla, solo para el perfil Contador

   Idempotente y sin filtrar por flgEstado: si el administrador ya quito la
   opcion de un perfil, volver a correr el script no debe devolversela.
   ------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'PROCESAMIENTO_PERIODO', 'Procesamiento de periodo', '/costo-labor/procesamiento',
       'bi bi-gear-wide-connected', p.ideOpcion, 4, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'PROCESAMIENTO_PERIODO');
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

-- El titulo va junto con la opcion: el menu descarta las opciones cuyo titulo
-- no llega en la lista del usuario, y el Contador no lo tenia.
INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'COSTO_LABOR'), ('CONTADOR', 'PROCESAMIENTO_PERIODO')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO

/* -------------------------------------------------------------------------
   CA-03 pestania 3: resumen del gasto de personal

   Agrupado por tipo de gasto, cuenta y descripcion, que es la tabla dinamica
   del Excel del contador.
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
    FROM proceso.TMD_GASTO_PERSONAL g
    WHERE g.idePeriodo = @idePeriodo AND g.flgEstado = 1
    GROUP BY g.txtTipoGasto, g.account, g.txtLocalName
    ORDER BY g.txtTipoGasto, g.account;
END
GO
