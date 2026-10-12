/* =========================================================================
   37 - Categorizacion de proyectos (documento del 10/10, punto 4)

   El procesamiento clasificaba cada proyecto de la distribucion de la
   compensacion con un CASE fijo (FA, PAR, TUCARI, TUQUIAR). Ahora el perfil
   Contador registra por periodo las categorias y sus proyectos, y el
   procesamiento las lee de aqui.

     - Los proyectos se eligen de los activos del periodo (script 36). Un
       proyecto va en una sola categoria del periodo.
     - "Replicar del periodo anterior" copia las categorias del periodo con
       categorias mas reciente. Solo agrega lo que falta: no pisa lo ya hecho.
     - El procesamiento usa la categorizacion del periodo; si el periodo no
       tiene, la del ultimo periodo anterior que tenga (y si no hay ninguno
       anterior, la mas antigua). Asi, reprocesar un mes que nunca se
       categorizo sigue dando lo mismo que antes.
     - Con el periodo cerrado no se puede modificar.

   Incluye la precarga de enero 2025 con las listas del CASE original
   (script 32), para que el procesamiento clasifique igual que hasta hoy.

   Errores nuevos:
     50090  el periodo esta cerrado
     50091  ya hay una categoria con ese nombre en el periodo
     50092  el proyecto ya esta en otra categoria del periodo
     50093  la categoria no existe
     50094  datos de la categoria invalidos (nombre o sin proyectos)
     50095  el proyecto no esta activo para Costo Labor en el periodo
     50096  no hay un periodo anterior con categorias que replicar

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Tablas y tipo
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMC_CATEGORIA_PROYECTO') IS NULL
BEGIN
    CREATE TABLE proceso.TMC_CATEGORIA_PROYECTO(
        ideCategoriaProyecto bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        -- Mismo largo que proceso.TMD_DISTRIBUCION_COMPENSACION.txtCategoria.
        codCategoria varchar(30) NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMC_CATEGORIA_PROYECTO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMC_CATEGORIA_PROYECTO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMC_CATEGORIA_PROYECTO PRIMARY KEY CLUSTERED (ideCategoriaProyecto ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMC_CATEGORIA_PROYECTO_CODIGO
        ON proceso.TMC_CATEGORIA_PROYECTO (numAnio, numMes, codCategoria) WHERE flgEstado = 1;
END
GO

IF OBJECT_ID('proceso.TMD_CATEGORIA_PROYECTO_DETALLE') IS NULL
BEGIN
    CREATE TABLE proceso.TMD_CATEGORIA_PROYECTO_DETALLE(
        ideCategoriaProyectoDetalle bigint IDENTITY(1,1) NOT NULL,
        ideCategoriaProyecto bigint NOT NULL,
        -- Repetidos de la cabecera para que el indice unico impida tener un
        -- proyecto en dos categorias del mismo periodo.
        numAnio int NOT NULL,
        numMes int NOT NULL,
        codProyecto varchar(30) NOT NULL,
        nomProyecto varchar(200) NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_CATEGORIA_PROYECTO_DETALLE_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_CATEGORIA_PROYECTO_DETALLE_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_CATEGORIA_PROYECTO_DETALLE PRIMARY KEY CLUSTERED (ideCategoriaProyectoDetalle ASC),
        CONSTRAINT FK_TMD_CATEGORIA_PROYECTO_DETALLE_CATEGORIA FOREIGN KEY (ideCategoriaProyecto)
            REFERENCES proceso.TMC_CATEGORIA_PROYECTO (ideCategoriaProyecto)
    );

    CREATE NONCLUSTERED INDEX IX_TMD_CATEGORIA_PROYECTO_DETALLE_CATEGORIA
        ON proceso.TMD_CATEGORIA_PROYECTO_DETALLE (ideCategoriaProyecto, flgEstado);

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_CATEGORIA_PROYECTO_DETALLE_PERIODO
        ON proceso.TMD_CATEGORIA_PROYECTO_DETALLE (numAnio, numMes, codProyecto) WHERE flgEstado = 1;
END
GO

IF TYPE_ID('proceso.TYPE_CATEGORIA_PROYECTO_DETALLE') IS NULL
    CREATE TYPE proceso.TYPE_CATEGORIA_PROYECTO_DETALLE AS TABLE (
        codProyecto varchar(30) NOT NULL PRIMARY KEY
    );
GO

/* -------------------------------------------------------------------------
   2. Listado del periodo

   Tres conjuntos de resultados: el resumen (periodo cerrado), las
   categorias y los proyectos de todas ellas.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_CategoriaProyecto_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado;

    SELECT c.ideCategoriaProyecto, c.numAnio, c.numMes, c.codCategoria,
           (SELECT COUNT(*) FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
            WHERE d.ideCategoriaProyecto = c.ideCategoriaProyecto AND d.flgEstado = 1) AS numProyectos
    FROM proceso.TMC_CATEGORIA_PROYECTO c
    WHERE c.numAnio = @numAnio AND c.numMes = @numMes AND c.flgEstado = 1
    ORDER BY c.codCategoria;

    SELECT d.ideCategoriaProyecto, d.codProyecto, d.nomProyecto
    FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
    JOIN proceso.TMC_CATEGORIA_PROYECTO c
      ON c.ideCategoriaProyecto = d.ideCategoriaProyecto AND c.flgEstado = 1
    WHERE d.numAnio = @numAnio AND d.numMes = @numMes AND d.flgEstado = 1
    ORDER BY d.ideCategoriaProyecto, d.nomProyecto, d.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   3. Alta y edicion

   Con @ideCategoriaProyecto nulo da de alta; con valor, reemplaza nombre y
   proyectos. Devuelve el id de la categoria.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_CategoriaProyecto_Guardar
    @ideCategoriaProyecto bigint = NULL,
    @numAnio      int,
    @numMes       int,
    @codCategoria varchar(30),
    @proyectos    proceso.TYPE_CATEGORIA_PROYECTO_DETALLE READONLY,
    @txtUsuario   varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @codCategoria = UPPER(TRIM(@codCategoria));

    IF @ideCategoriaProyecto IS NOT NULL
    BEGIN
        -- En la edicion el periodo es el de la categoria, no el que mande el cliente.
        SELECT @numAnio = numAnio, @numMes = numMes
        FROM proceso.TMC_CATEGORIA_PROYECTO
        WHERE ideCategoriaProyecto = @ideCategoriaProyecto AND flgEstado = 1;

        IF @@ROWCOUNT = 0
            THROW 50093, 'La categoria indicada no existe o fue eliminada.', 1;
    END

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50090, 'El periodo esta cerrado: su categorizacion de proyectos no se puede modificar.', 1;

    -- Es el valor que el procesamiento guarda como categoria (FA, PAR...) y la
    -- fuente que muestran los reportes: letras, numeros, espacios y guion.
    IF ISNULL(@codCategoria, '') = ''
        THROW 50094, 'El nombre de la categoria es obligatorio.', 1;

    IF @codCategoria COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9 -]%'
        THROW 50094, 'El nombre de la categoria solo admite letras, numeros, espacios y guion.', 1;

    IF NOT EXISTS (SELECT 1 FROM @proyectos)
        THROW 50094, 'La categoria debe tener al menos un proyecto.', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMC_CATEGORIA_PROYECTO
               WHERE numAnio = @numAnio AND numMes = @numMes AND codCategoria = @codCategoria
                 AND flgEstado = 1
                 AND ideCategoriaProyecto <> ISNULL(@ideCategoriaProyecto, 0))
        THROW 50091, 'Ya existe una categoria con ese nombre en el periodo.', 1;

    -- Se eligen de los activos del periodo. Los que la categoria ya tenia se
    -- conservan aunque hayan dejado de estar activos (por ejemplo, al replicar).
    DECLARE @inactivo varchar(200) =
        (SELECT TOP (1) CONCAT('El proyecto ', p.codProyecto, ' no esta activo para Costo Labor en el periodo.')
         FROM @proyectos p
         WHERE NOT EXISTS (SELECT 1 FROM proceso.TMD_ESTADO_PROYECTO e
                           WHERE e.numAnio = @numAnio AND e.numMes = @numMes AND e.codProyecto = p.codProyecto
                             AND e.flgEstado = 1 AND e.flgActivoCostoLabor = 1)
           AND NOT EXISTS (SELECT 1 FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
                           WHERE d.ideCategoriaProyecto = @ideCategoriaProyecto
                             AND d.codProyecto = p.codProyecto AND d.flgEstado = 1));

    IF @inactivo IS NOT NULL
        THROW 50095, @inactivo, 1;

    -- Un proyecto en dos categorias quedaria clasificado al azar.
    DECLARE @repetido varchar(200) =
        (SELECT TOP (1) CONCAT('El proyecto ', p.codProyecto, ' ya esta en la categoria ', c.codCategoria, '.')
         FROM @proyectos p
         JOIN proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
           ON d.codProyecto = p.codProyecto AND d.flgEstado = 1
         JOIN proceso.TMC_CATEGORIA_PROYECTO c
           ON c.ideCategoriaProyecto = d.ideCategoriaProyecto AND c.flgEstado = 1
         WHERE c.numAnio = @numAnio AND c.numMes = @numMes
           AND c.ideCategoriaProyecto <> ISNULL(@ideCategoriaProyecto, 0));

    IF @repetido IS NOT NULL
        THROW 50092, @repetido, 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- El nombre que tenia cada proyecto, para no perderlo al reemplazar el detalle.
        DECLARE @nombres TABLE (codProyecto varchar(30) PRIMARY KEY, nomProyecto varchar(200));

        IF @ideCategoriaProyecto IS NULL
        BEGIN
            INSERT INTO proceso.TMC_CATEGORIA_PROYECTO (numAnio, numMes, codCategoria, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, @codCategoria, 1, @txtUsuario);
            SET @ideCategoriaProyecto = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE proceso.TMC_CATEGORIA_PROYECTO
            SET codCategoria = @codCategoria,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideCategoriaProyecto = @ideCategoriaProyecto;

            INSERT INTO @nombres (codProyecto, nomProyecto)
            SELECT codProyecto, MAX(nomProyecto)
            FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE
            WHERE ideCategoriaProyecto = @ideCategoriaProyecto AND flgEstado = 1
            GROUP BY codProyecto;

            UPDATE proceso.TMD_CATEGORIA_PROYECTO_DETALLE
            SET flgEstado = 0,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideCategoriaProyecto = @ideCategoriaProyecto AND flgEstado = 1;
        END

        INSERT INTO proceso.TMD_CATEGORIA_PROYECTO_DETALLE
              (ideCategoriaProyecto, numAnio, numMes, codProyecto, nomProyecto, flgEstado, txtUsuarioCreacion)
        SELECT @ideCategoriaProyecto, @numAnio, @numMes, p.codProyecto,
               COALESCE(e.nomProyecto, n.nomProyecto), 1, @txtUsuario
        FROM @proyectos p
        LEFT JOIN proceso.TMD_ESTADO_PROYECTO e
               ON e.numAnio = @numAnio AND e.numMes = @numMes AND e.codProyecto = p.codProyecto AND e.flgEstado = 1
        LEFT JOIN @nombres n ON n.codProyecto = p.codProyecto;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @ideCategoriaProyecto AS ideCategoriaProyecto;
END
GO

CREATE OR ALTER PROCEDURE proceso.usp_CategoriaProyecto_Eliminar
    @ideCategoriaProyecto bigint,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @numAnio int, @numMes int;

    SELECT @numAnio = numAnio, @numMes = numMes
    FROM proceso.TMC_CATEGORIA_PROYECTO
    WHERE ideCategoriaProyecto = @ideCategoriaProyecto AND flgEstado = 1;

    IF @numAnio IS NULL
        THROW 50093, 'La categoria indicada no existe o fue eliminada.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50090, 'El periodo esta cerrado: su categorizacion de proyectos no se puede modificar.', 1;

    BEGIN TRANSACTION;

    UPDATE proceso.TMD_CATEGORIA_PROYECTO_DETALLE
    SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
    WHERE ideCategoriaProyecto = @ideCategoriaProyecto AND flgEstado = 1;

    UPDATE proceso.TMC_CATEGORIA_PROYECTO
    SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
    WHERE ideCategoriaProyecto = @ideCategoriaProyecto;

    COMMIT TRANSACTION;
END
GO

/* -------------------------------------------------------------------------
   4. Replicar del periodo anterior

   Copia las categorias que el periodo aun no tiene, con sus proyectos,
   salvo los que ya esten en otra categoria del periodo. Devuelve el
   periodo de origen y cuanto copio.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_CategoriaProyecto_Replicar
    @numAnio    int,
    @numMes     int,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50090, 'El periodo esta cerrado: su categorizacion de proyectos no se puede modificar.', 1;

    DECLARE @numAnioOrigen int, @numMesOrigen int;

    SELECT TOP (1) @numAnioOrigen = numAnio, @numMesOrigen = numMes
    FROM proceso.TMC_CATEGORIA_PROYECTO
    WHERE flgEstado = 1 AND numAnio * 100 + numMes < @numAnio * 100 + @numMes
    ORDER BY numAnio DESC, numMes DESC;

    IF @numAnioOrigen IS NULL
        THROW 50096, 'No hay un periodo anterior con categorias que replicar.', 1;

    DECLARE @copiadas TABLE (ideOrigen bigint PRIMARY KEY, ideDestino bigint);
    DECLARE @numCategorias int = 0, @numProyectos int = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- MERGE y no INSERT: es la forma de saber que id nuevo le toco a cada categoria de origen.
        MERGE proceso.TMC_CATEGORIA_PROYECTO AS destino
        USING (SELECT o.ideCategoriaProyecto, o.codCategoria
               FROM proceso.TMC_CATEGORIA_PROYECTO o
               WHERE o.numAnio = @numAnioOrigen AND o.numMes = @numMesOrigen AND o.flgEstado = 1
                 AND NOT EXISTS (SELECT 1 FROM proceso.TMC_CATEGORIA_PROYECTO d
                                 WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                                   AND d.codCategoria = o.codCategoria AND d.flgEstado = 1)) AS origen
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (numAnio, numMes, codCategoria, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, origen.codCategoria, 1, @txtUsuario)
        OUTPUT origen.ideCategoriaProyecto, inserted.ideCategoriaProyecto INTO @copiadas (ideOrigen, ideDestino);

        SET @numCategorias = @@ROWCOUNT;

        INSERT INTO proceso.TMD_CATEGORIA_PROYECTO_DETALLE
              (ideCategoriaProyecto, numAnio, numMes, codProyecto, nomProyecto, flgEstado, txtUsuarioCreacion)
        SELECT c.ideDestino, @numAnio, @numMes, o.codProyecto, o.nomProyecto, 1, @txtUsuario
        FROM @copiadas c
        JOIN proceso.TMD_CATEGORIA_PROYECTO_DETALLE o
          ON o.ideCategoriaProyecto = c.ideOrigen AND o.flgEstado = 1
        WHERE NOT EXISTS (SELECT 1 FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
                          WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                            AND d.codProyecto = o.codProyecto AND d.flgEstado = 1);

        SET @numProyectos = @@ROWCOUNT;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @numAnioOrigen AS numAnioOrigen, @numMesOrigen AS numMesOrigen,
           @numCategorias AS numCategorias, @numProyectos AS numProyectos;
END
GO

/* -------------------------------------------------------------------------
   5. Procesamiento: la categoria sale de la categorizacion, no de un CASE

   Igual que el script 32, salvo la distribucion de la compensacion: se
   inserta con 'Categoria Desconocida' (el ELSE del CASE anterior) y luego se
   actualiza con la categorizacion vigente para el periodo.
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

    -- Categorizacion vigente: la del periodo o la del ultimo anterior que tenga;
    -- sin ninguna anterior, la mas antigua.
    DECLARE @numAnioCategoria int, @numMesCategoria int;

    SELECT TOP (1) @numAnioCategoria = numAnio, @numMesCategoria = numMes
    FROM proceso.TMC_CATEGORIA_PROYECTO
    WHERE flgEstado = 1 AND numAnio * 100 + numMes <= @numAnio * 100 + @numMes
    ORDER BY numAnio DESC, numMes DESC;

    IF @numAnioCategoria IS NULL
        SELECT TOP (1) @numAnioCategoria = numAnio, @numMesCategoria = numMes
        FROM proceso.TMC_CATEGORIA_PROYECTO
        WHERE flgEstado = 1
        ORDER BY numAnio, numMes;

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
                -- La categoria se completa abajo, con la categorizacion del periodo.
                ''Categoria Desconocida'',
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

        -- Documento del 10/10: reemplaza el CASE fijo de FA, PAR, TUCARI y TUQUIAR.
        UPDATE dc
        SET dc.txtCategoria = c.codCategoria
        FROM proceso.TMD_DISTRIBUCION_COMPENSACION dc
        JOIN proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
          ON d.codProyecto = dc.Proyecto
         AND d.numAnio = @numAnioCategoria AND d.numMes = @numMesCategoria
         AND d.flgEstado = 1
        JOIN proceso.TMC_CATEGORIA_PROYECTO c
          ON c.ideCategoriaProyecto = d.ideCategoriaProyecto AND c.flgEstado = 1
        WHERE dc.idePeriodo = @idePeriodo;

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
   6. Precarga de enero 2025 con las listas del CASE original (script 32)

   Solo si enero 2025 aun no tiene categorias. El nombre de cada proyecto
   se toma de SPRING cuando esta disponible.
   ------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM proceso.TMC_CATEGORIA_PROYECTO WHERE numAnio = 2025 AND numMes = 1 AND flgEstado = 1)
BEGIN
    DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

    DECLARE @precarga TABLE (codCategoria varchar(30), codProyecto varchar(30) PRIMARY KEY);

    INSERT INTO @precarga (codCategoria, codProyecto)
    SELECT 'FA', v.cod FROM (VALUES
        ('000000000001'), ('000000000007'), ('000000000009'), ('000000000013'),
        ('000000000027'), ('000000000029'), ('000000000040'), ('000000000041'),
        ('000000000057'), ('000000000058'), ('000000000065'), ('000000000104'),
        ('000000202009'), ('000000203008'), ('000000210033'), ('000000210034'),
        ('000000210035'), ('000000210045'), ('000000220014'), ('000000220017'),
        ('000000230073')) AS v(cod)
    UNION ALL
    SELECT 'PAR', v.cod FROM (VALUES
        ('000000000018'), ('000000000019'), ('000000000020'), ('000000000021'),
        ('000000000022'), ('000000000023'), ('000000321016'), ('000000000103'),
        ('000000210043'), ('000000302002'), ('000000302004'), ('000000302006'),
        ('000000302007'), ('000000310031'), ('000000310032'), ('000000321001'),
        ('000000340001'), ('000000340002'), ('000000350001'), ('000000364001'),
        ('000000632025'), ('000000632026')) AS v(cod)
    UNION ALL
    SELECT 'TUCARI', '000000000074'
    UNION ALL
    SELECT 'TUQUIAR', v.cod FROM (VALUES ('000000000105'), ('000000000106'), ('000000000107')) AS v(cod);

    BEGIN TRANSACTION;

    INSERT INTO proceso.TMC_CATEGORIA_PROYECTO (numAnio, numMes, codCategoria, flgEstado, txtUsuarioCreacion)
    SELECT DISTINCT 2025, 1, codCategoria, 1, @usuario FROM @precarga;

    INSERT INTO proceso.TMD_CATEGORIA_PROYECTO_DETALLE
          (ideCategoriaProyecto, numAnio, numMes, codProyecto, flgEstado, txtUsuarioCreacion)
    SELECT c.ideCategoriaProyecto, 2025, 1, p.codProyecto, 1, @usuario
    FROM @precarga p
    JOIN proceso.TMC_CATEGORIA_PROYECTO c
      ON c.numAnio = 2025 AND c.numMes = 1 AND c.codCategoria = p.codCategoria AND c.flgEstado = 1;

    COMMIT TRANSACTION;

    IF DB_ID('BD_SPRING') IS NOT NULL
        EXEC sp_executesql N'
            UPDATE d
            SET d.nomProyecto = CAST(TRIM(a.englishname) AS varchar(200))
            FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
            JOIN BD_SPRING.dbo.afemst a ON TRIM(a.afe) = d.codProyecto
            WHERE d.numAnio = 2025 AND d.numMes = 1 AND d.nomProyecto IS NULL;';
END
GO

/* -------------------------------------------------------------------------
   7. Opcion de menu, solo para el perfil Contador
   ------------------------------------------------------------------------- */

SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'CATEGORIZACION_PROYECTOS', 'Categorización de proyectos', '/costo-labor/categorizacion-proyectos',
       'bi bi-tags', p.ideOpcion, 7, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'CATEGORIZACION_PROYECTOS');
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'COSTO_LABOR'), ('CONTADOR', 'CATEGORIZACION_PROYECTOS')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
