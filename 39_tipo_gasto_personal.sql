/* =========================================================================
   39 - Tipo de gasto de personal

   El procesamiento clasificaba cada linea del gasto de personal
   (proceso.TMD_GASTO_PERSONAL.txtTipoGasto) con un CASE fijo por cuenta
   contable. Ahora el perfil Contador registra por periodo los tipos de gasto
   y sus cuentas, y el procesamiento las lee de aqui.

     - Las cuentas se eligen de SPRING (accountmst). Algunas cuentas solo
       pertenecen a un tipo en un centro de costo (por ejemplo, el reembolso
       en el centro de costo 111): la cuenta se registra con ese centro de
       costo, que se elige de SPRING (AC_CostCenterMst).
     - Una cuenta con centro de costo pesa mas que la misma cuenta sin el:
       igual que el CASE, que evaluaba primero el reembolso del 111.
     - Una cuenta (con o sin centro de costo) va en un solo tipo del periodo.
     - "Replicar del periodo anterior" copia los tipos del periodo con tipos
       mas reciente. Solo agrega lo que falta: no pisa lo ya hecho.
     - El procesamiento usa la configuracion del periodo; si el periodo no
       tiene, la del ultimo anterior que tenga (y si no hay ninguno anterior,
       la mas antigua). Lo que no encaja queda como 'Categoria Desconocida',
       el ELSE del CASE.
     - Con el periodo cerrado no se puede modificar.
     - Los reportes del costo labor leen 'Gasto de Personal' y 'Gasto
       Operativo' por su nombre: esos dos tipos no se pueden renombrar ni
       eliminar.
     - Un periodo sin tipos usa los del anterior. Crear un tipo en ese periodo
       haria que solo ese tipo cuente y el resto del gasto quede sin
       clasificar: por eso se exige replicar primero.

   Incluye la precarga de enero 2025 con las listas del CASE original
   (script 37), para que el procesamiento clasifique igual que hasta hoy.

   Errores nuevos:
     50100  el periodo esta cerrado
     50101  ya hay un tipo de gasto con ese nombre en el periodo
     50102  la cuenta (con ese centro de costo) ya esta en otro tipo del periodo
     50103  el tipo de gasto no existe
     50104  datos del tipo de gasto invalidos (nombre o sin cuentas)
     50105  el tipo de gasto lo usan los reportes y no se puede renombrar
     50106  la cuenta no existe en SPRING
     50107  el centro de costo no existe en SPRING
     50108  no hay un periodo anterior con tipos de gasto que replicar
     50109  el periodo no tiene tipos y hay uno anterior: replicar antes de crear

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* -------------------------------------------------------------------------
   1. Tablas y tipo
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMC_TIPO_GASTO') IS NULL
BEGIN
    CREATE TABLE proceso.TMC_TIPO_GASTO(
        ideTipoGasto bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        -- Mismo largo que proceso.TMD_GASTO_PERSONAL.txtTipoGasto.
        nomTipoGasto varchar(30) NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMC_TIPO_GASTO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMC_TIPO_GASTO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMC_TIPO_GASTO PRIMARY KEY CLUSTERED (ideTipoGasto ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMC_TIPO_GASTO_NOMBRE
        ON proceso.TMC_TIPO_GASTO (numAnio, numMes, nomTipoGasto) WHERE flgEstado = 1;
END
GO

IF OBJECT_ID('proceso.TMD_TIPO_GASTO_CUENTA') IS NULL
BEGIN
    CREATE TABLE proceso.TMD_TIPO_GASTO_CUENTA(
        ideTipoGastoCuenta bigint IDENTITY(1,1) NOT NULL,
        ideTipoGasto bigint NOT NULL,
        -- Repetidos de la cabecera para que el indice unico impida tener una
        -- cuenta en dos tipos del mismo periodo.
        numAnio int NOT NULL,
        numMes int NOT NULL,
        codCuenta varchar(30) NOT NULL,
        nomCuenta varchar(500) NULL,
        -- Vacio: la cuenta pertenece al tipo en cualquier centro de costo.
        codCentroCosto varchar(10) NOT NULL CONSTRAINT DF_TMD_TIPO_GASTO_CUENTA_codCentroCosto DEFAULT (''),
        nomCentroCosto varchar(200) NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_TIPO_GASTO_CUENTA_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_TIPO_GASTO_CUENTA_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_TIPO_GASTO_CUENTA PRIMARY KEY CLUSTERED (ideTipoGastoCuenta ASC),
        CONSTRAINT FK_TMD_TIPO_GASTO_CUENTA_TIPO FOREIGN KEY (ideTipoGasto)
            REFERENCES proceso.TMC_TIPO_GASTO (ideTipoGasto)
    );

    CREATE NONCLUSTERED INDEX IX_TMD_TIPO_GASTO_CUENTA_TIPO
        ON proceso.TMD_TIPO_GASTO_CUENTA (ideTipoGasto, flgEstado);

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_TIPO_GASTO_CUENTA_PERIODO
        ON proceso.TMD_TIPO_GASTO_CUENTA (numAnio, numMes, codCuenta, codCentroCosto) WHERE flgEstado = 1;
END
GO

IF TYPE_ID('proceso.TYPE_TIPO_GASTO_CUENTA') IS NULL
    CREATE TYPE proceso.TYPE_TIPO_GASTO_CUENTA AS TABLE (
        codCuenta varchar(30) NOT NULL,
        codCentroCosto varchar(10) NOT NULL DEFAULT (''),
        PRIMARY KEY (codCuenta, codCentroCosto)
    );
GO

/* -------------------------------------------------------------------------
   2. Catalogos de SPRING para elegir cuentas y centros de costo

   Busqueda por codigo o nombre, hasta 50 resultados. Sin BD_SPRING no hay
   catalogo. AC_CostCenterMst es la tabla que indico el lider; si la copia
   de SPRING no la tiene, se ofrecen los centros de costo usados en los
   vouchers, sin nombre.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_CuentaSpring_Buscar
    @txtCriterio varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50010, 'La base de datos BD_SPRING no esta disponible en este servidor.', 1;

    SET @txtCriterio = NULLIF(TRIM(@txtCriterio), '');

    EXEC sp_executesql N'
        SELECT TOP (50) TRIM(am.account) AS codCuenta, TRIM(am.localname) AS nomCuenta
        FROM BD_SPRING.dbo.accountmst am
        WHERE @txtCriterio IS NULL
           OR TRIM(am.account) LIKE @txtCriterio + ''%''
           OR am.localname COLLATE Latin1_General_CI_AI LIKE ''%'' + @txtCriterio + ''%'' COLLATE Latin1_General_CI_AI
        ORDER BY am.account;',
        N'@txtCriterio varchar(100)', @txtCriterio = @txtCriterio;
END
GO

CREATE OR ALTER PROCEDURE proceso.usp_CentroCostoSpring_Buscar
    @txtCriterio varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50010, 'La base de datos BD_SPRING no esta disponible en este servidor.', 1;

    SET @txtCriterio = NULLIF(TRIM(@txtCriterio), '');

    IF OBJECT_ID('BD_SPRING.dbo.AC_CostCenterMst') IS NOT NULL
        EXEC sp_executesql N'
            SELECT TOP (50) TRIM(cc.CostCenter) AS codCentroCosto, TRIM(cc.LocalName) AS nomCentroCosto
            FROM BD_SPRING.dbo.AC_CostCenterMst cc
            WHERE @txtCriterio IS NULL
               OR TRIM(cc.CostCenter) LIKE @txtCriterio + ''%''
               OR cc.LocalName COLLATE Latin1_General_CI_AI LIKE ''%'' + @txtCriterio + ''%'' COLLATE Latin1_General_CI_AI
            ORDER BY cc.CostCenter;',
            N'@txtCriterio varchar(100)', @txtCriterio = @txtCriterio;
    ELSE
        EXEC sp_executesql N'
            SELECT TOP (50) codCentroCosto, CAST(NULL AS varchar(200)) AS nomCentroCosto
            FROM (SELECT DISTINCT TRIM(vd.CostCenter) AS codCentroCosto
                  FROM BD_SPRING.dbo.voucherdetail vd
                  WHERE NULLIF(TRIM(vd.CostCenter), '''') IS NOT NULL) c
            WHERE @txtCriterio IS NULL OR codCentroCosto LIKE @txtCriterio + ''%''
            ORDER BY codCentroCosto;',
            N'@txtCriterio varchar(100)', @txtCriterio = @txtCriterio;
END
GO

/* -------------------------------------------------------------------------
   3. Listado del periodo

   Tres conjuntos de resultados: el resumen (periodo cerrado), los tipos de
   gasto y las cuentas de todos ellos.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_TipoGasto_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado;

    SELECT t.ideTipoGasto, t.numAnio, t.numMes, t.nomTipoGasto,
           (SELECT COUNT(*) FROM proceso.TMD_TIPO_GASTO_CUENTA c
            WHERE c.ideTipoGasto = t.ideTipoGasto AND c.flgEstado = 1) AS numCuentas
    FROM proceso.TMC_TIPO_GASTO t
    WHERE t.numAnio = @numAnio AND t.numMes = @numMes AND t.flgEstado = 1
    ORDER BY t.nomTipoGasto;

    SELECT c.ideTipoGasto, c.codCuenta, c.nomCuenta, c.codCentroCosto, c.nomCentroCosto
    FROM proceso.TMD_TIPO_GASTO_CUENTA c
    JOIN proceso.TMC_TIPO_GASTO t
      ON t.ideTipoGasto = c.ideTipoGasto AND t.flgEstado = 1
    WHERE c.numAnio = @numAnio AND c.numMes = @numMes AND c.flgEstado = 1
    ORDER BY c.ideTipoGasto, c.codCuenta, c.codCentroCosto;
END
GO

/* -------------------------------------------------------------------------
   4. Alta y edicion

   Con @ideTipoGasto nulo da de alta; con valor, reemplaza nombre y cuentas.
   Devuelve el id del tipo de gasto.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_TipoGasto_Guardar
    @ideTipoGasto bigint = NULL,
    @numAnio      int,
    @numMes       int,
    @nomTipoGasto varchar(100),
    @cuentas      proceso.TYPE_TIPO_GASTO_CUENTA READONLY,
    @txtUsuario   varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Espacios de mas fuera: el nombre es lo que el procesamiento guarda en
    -- cada linea y lo que agrupan los reportes.
    SET @nomTipoGasto = TRIM(@nomTipoGasto);
    WHILE CHARINDEX('  ', @nomTipoGasto) > 0
        SET @nomTipoGasto = REPLACE(@nomTipoGasto, '  ', ' ');

    DECLARE @nombreAnterior varchar(30);

    IF @ideTipoGasto IS NOT NULL
    BEGIN
        -- En la edicion el periodo es el del tipo de gasto, no el que mande el cliente.
        SELECT @numAnio = numAnio, @numMes = numMes, @nombreAnterior = nomTipoGasto
        FROM proceso.TMC_TIPO_GASTO
        WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1;

        IF @@ROWCOUNT = 0
            THROW 50103, 'El tipo de gasto indicado no existe o fue eliminado.', 1;
    END

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50100, 'El periodo esta cerrado: sus tipos de gasto de personal no se pueden modificar.', 1;

    IF ISNULL(@nomTipoGasto, '') = ''
        THROW 50104, 'El nombre del tipo de gasto es obligatorio.', 1;

    IF LEN(@nomTipoGasto) > 30
        THROW 50104, 'El nombre del tipo de gasto admite hasta 30 caracteres.', 1;

    -- 'Categoria Desconocida' es lo que queda en las lineas que no encajan en ningun tipo.
    IF @nomTipoGasto = 'Categoria Desconocida'
        THROW 50104, 'Categoria Desconocida es la marca de las cuentas sin tipo de gasto: elija otro nombre.', 1;

    IF @nombreAnterior IN ('Gasto de Personal', 'Gasto Operativo')
       AND @nomTipoGasto COLLATE Latin1_General_BIN <> @nombreAnterior COLLATE Latin1_General_BIN
        THROW 50105, 'Los reportes del costo labor usan este tipo de gasto por su nombre: no se puede renombrar.', 1;

    IF NOT EXISTS (SELECT 1 FROM @cuentas)
        THROW 50104, 'El tipo de gasto debe tener al menos una cuenta.', 1;

    -- Con el periodo vacio el procesamiento usa la configuracion anterior
    -- completa; un tipo suelto la reemplazaria y el resto quedaria sin tipo.
    IF @ideTipoGasto IS NULL
       AND NOT EXISTS (SELECT 1 FROM proceso.TMC_TIPO_GASTO
                       WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1)
       AND EXISTS (SELECT 1 FROM proceso.TMC_TIPO_GASTO
                   WHERE flgEstado = 1 AND numAnio * 100 + numMes < @numAnio * 100 + @numMes)
        THROW 50109, 'El periodo aun no tiene tipos de gasto: use Replicar del periodo anterior antes de crear uno nuevo.', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMC_TIPO_GASTO
               WHERE numAnio = @numAnio AND numMes = @numMes AND nomTipoGasto = @nomTipoGasto
                 AND flgEstado = 1
                 AND ideTipoGasto <> ISNULL(@ideTipoGasto, 0))
        THROW 50101, 'Ya existe un tipo de gasto con ese nombre en el periodo.', 1;

    -- Codigos sin espacios, como los guarda el procesamiento (TRIM de SPRING).
    DECLARE @lista TABLE (codCuenta varchar(30) NOT NULL, codCentroCosto varchar(10) NOT NULL,
                          PRIMARY KEY (codCuenta, codCentroCosto));
    INSERT INTO @lista (codCuenta, codCentroCosto)
    SELECT DISTINCT UPPER(TRIM(codCuenta)), UPPER(TRIM(ISNULL(codCentroCosto, '')))
    FROM @cuentas
    WHERE TRIM(codCuenta) <> '';

    IF NOT EXISTS (SELECT 1 FROM @lista)
        THROW 50104, 'El tipo de gasto debe tener al menos una cuenta.', 1;

    -- Una cuenta en dos tipos quedaria clasificada al azar.
    DECLARE @repetida varchar(300) =
        (SELECT TOP (1) CONCAT('La cuenta ', l.codCuenta,
                               CASE WHEN l.codCentroCosto <> '' THEN CONCAT(' (centro de costo ', l.codCentroCosto, ')') ELSE '' END,
                               ' ya esta en el tipo de gasto ', t.nomTipoGasto, '.')
         FROM @lista l
         JOIN proceso.TMD_TIPO_GASTO_CUENTA c
           ON c.codCuenta = l.codCuenta AND c.codCentroCosto = l.codCentroCosto AND c.flgEstado = 1
         JOIN proceso.TMC_TIPO_GASTO t
           ON t.ideTipoGasto = c.ideTipoGasto AND t.flgEstado = 1
         WHERE c.numAnio = @numAnio AND c.numMes = @numMes
           AND t.ideTipoGasto <> ISNULL(@ideTipoGasto, 0));

    IF @repetida IS NOT NULL
        THROW 50102, @repetida, 1;

    -- Nombres de SPRING. Sin BD_SPRING se aceptan los codigos tal cual: la
    -- validacion de que existan queda para cuando la base este disponible.
    DECLARE @nombresCuenta TABLE (codCuenta varchar(30) PRIMARY KEY, nomCuenta varchar(500));
    DECLARE @nombresCentro TABLE (codCentroCosto varchar(10) PRIMARY KEY, nomCentroCosto varchar(200));

    IF DB_ID('BD_SPRING') IS NOT NULL
    BEGIN
        INSERT INTO @nombresCuenta (codCuenta, nomCuenta)
        EXEC sp_executesql N'
            SELECT TRIM(am.account), MAX(TRIM(am.localname))
            FROM BD_SPRING.dbo.accountmst am
            GROUP BY TRIM(am.account);';

        DECLARE @sinCuenta varchar(30) =
            (SELECT TOP (1) l.codCuenta FROM @lista l
             WHERE NOT EXISTS (SELECT 1 FROM @nombresCuenta n WHERE n.codCuenta = l.codCuenta));
        IF @sinCuenta IS NOT NULL
        BEGIN
            DECLARE @msgCuenta varchar(200) = CONCAT('La cuenta ', @sinCuenta, ' no existe en SPRING.');
            THROW 50106, @msgCuenta, 1;
        END

        IF OBJECT_ID('BD_SPRING.dbo.AC_CostCenterMst') IS NOT NULL
        BEGIN
            INSERT INTO @nombresCentro (codCentroCosto, nomCentroCosto)
            EXEC sp_executesql N'
                SELECT TRIM(cc.CostCenter), MAX(TRIM(cc.LocalName))
                FROM BD_SPRING.dbo.AC_CostCenterMst cc
                WHERE LEN(TRIM(cc.CostCenter)) <= 10
                GROUP BY TRIM(cc.CostCenter);';

            DECLARE @sinCentro varchar(10) =
                (SELECT TOP (1) l.codCentroCosto FROM @lista l
                 WHERE l.codCentroCosto <> ''
                   AND NOT EXISTS (SELECT 1 FROM @nombresCentro n WHERE n.codCentroCosto = l.codCentroCosto));
            IF @sinCentro IS NOT NULL
            BEGIN
                DECLARE @msgCentro varchar(200) = CONCAT('El centro de costo ', @sinCentro, ' no existe en SPRING.');
                THROW 50107, @msgCentro, 1;
            END
        END
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Los nombres que ya tenia cada cuenta, por si SPRING no esta disponible.
        DECLARE @previos TABLE (codCuenta varchar(30), codCentroCosto varchar(10), nomCuenta varchar(500),
                                nomCentroCosto varchar(200), PRIMARY KEY (codCuenta, codCentroCosto));

        IF @ideTipoGasto IS NULL
        BEGIN
            INSERT INTO proceso.TMC_TIPO_GASTO (numAnio, numMes, nomTipoGasto, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, @nomTipoGasto, 1, @txtUsuario);
            SET @ideTipoGasto = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE proceso.TMC_TIPO_GASTO
            SET nomTipoGasto = @nomTipoGasto,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideTipoGasto = @ideTipoGasto;

            INSERT INTO @previos (codCuenta, codCentroCosto, nomCuenta, nomCentroCosto)
            SELECT codCuenta, codCentroCosto, MAX(nomCuenta), MAX(nomCentroCosto)
            FROM proceso.TMD_TIPO_GASTO_CUENTA
            WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1
            GROUP BY codCuenta, codCentroCosto;

            UPDATE proceso.TMD_TIPO_GASTO_CUENTA
            SET flgEstado = 0,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1;
        END

        INSERT INTO proceso.TMD_TIPO_GASTO_CUENTA
              (ideTipoGasto, numAnio, numMes, codCuenta, nomCuenta, codCentroCosto, nomCentroCosto,
               flgEstado, txtUsuarioCreacion)
        SELECT @ideTipoGasto, @numAnio, @numMes, l.codCuenta,
               COALESCE(nc.nomCuenta, p.nomCuenta),
               l.codCentroCosto,
               CASE WHEN l.codCentroCosto = '' THEN NULL ELSE COALESCE(ncc.nomCentroCosto, p.nomCentroCosto) END,
               1, @txtUsuario
        FROM @lista l
        LEFT JOIN @nombresCuenta nc ON nc.codCuenta = l.codCuenta
        LEFT JOIN @nombresCentro ncc ON ncc.codCentroCosto = l.codCentroCosto
        LEFT JOIN @previos p ON p.codCuenta = l.codCuenta AND p.codCentroCosto = l.codCentroCosto;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @ideTipoGasto AS ideTipoGasto;
END
GO

CREATE OR ALTER PROCEDURE proceso.usp_TipoGasto_Eliminar
    @ideTipoGasto bigint,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @numAnio int, @numMes int, @nomTipoGasto varchar(30);

    SELECT @numAnio = numAnio, @numMes = numMes, @nomTipoGasto = nomTipoGasto
    FROM proceso.TMC_TIPO_GASTO
    WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1;

    IF @numAnio IS NULL
        THROW 50103, 'El tipo de gasto indicado no existe o fue eliminado.', 1;

    IF @nomTipoGasto IN ('Gasto de Personal', 'Gasto Operativo')
        THROW 50105, 'Los reportes del costo labor usan este tipo de gasto por su nombre: no se puede eliminar.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50100, 'El periodo esta cerrado: sus tipos de gasto de personal no se pueden modificar.', 1;

    BEGIN TRANSACTION;

    UPDATE proceso.TMD_TIPO_GASTO_CUENTA
    SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
    WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1;

    UPDATE proceso.TMC_TIPO_GASTO
    SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
    WHERE ideTipoGasto = @ideTipoGasto;

    COMMIT TRANSACTION;
END
GO

/* -------------------------------------------------------------------------
   5. Replicar del periodo anterior

   Copia los tipos que el periodo aun no tiene, con sus cuentas, salvo las
   que ya esten en otro tipo del periodo. Un tipo que se quedaria sin
   cuentas no se copia. Devuelve el periodo de origen y cuanto copio.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_TipoGasto_Replicar
    @numAnio    int,
    @numMes     int,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50100, 'El periodo esta cerrado: sus tipos de gasto de personal no se pueden modificar.', 1;

    DECLARE @numAnioOrigen int, @numMesOrigen int;

    SELECT TOP (1) @numAnioOrigen = numAnio, @numMesOrigen = numMes
    FROM proceso.TMC_TIPO_GASTO
    WHERE flgEstado = 1 AND numAnio * 100 + numMes < @numAnio * 100 + @numMes
    ORDER BY numAnio DESC, numMes DESC;

    IF @numAnioOrigen IS NULL
        THROW 50108, 'No hay un periodo anterior con tipos de gasto que replicar.', 1;

    DECLARE @copiados TABLE (ideOrigen bigint PRIMARY KEY, ideDestino bigint);
    DECLARE @numTipos int = 0, @numCuentas int = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Bloquea el periodo destino: dos replicas a la vez duplicarian tipos.
        DECLARE @bloqueo int =
            (SELECT COUNT(*) FROM proceso.TMC_TIPO_GASTO WITH (UPDLOCK, HOLDLOCK)
             WHERE numAnio = @numAnio AND numMes = @numMes);

        -- MERGE y no INSERT: es la forma de saber que id nuevo le toco a cada tipo de origen.
        MERGE proceso.TMC_TIPO_GASTO AS destino
        USING (SELECT o.ideTipoGasto, o.nomTipoGasto
               FROM proceso.TMC_TIPO_GASTO o
               WHERE o.numAnio = @numAnioOrigen AND o.numMes = @numMesOrigen AND o.flgEstado = 1
                 AND NOT EXISTS (SELECT 1 FROM proceso.TMC_TIPO_GASTO d
                                 WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                                   AND d.nomTipoGasto = o.nomTipoGasto AND d.flgEstado = 1)
                 -- Al menos una cuenta libre en el destino; si no, quedaria vacio.
                 AND EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_CUENTA oc
                             WHERE oc.ideTipoGasto = o.ideTipoGasto AND oc.flgEstado = 1
                               AND NOT EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_CUENTA dc
                                               WHERE dc.numAnio = @numAnio AND dc.numMes = @numMes
                                                 AND dc.codCuenta = oc.codCuenta
                                                 AND dc.codCentroCosto = oc.codCentroCosto
                                                 AND dc.flgEstado = 1))) AS origen
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (numAnio, numMes, nomTipoGasto, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, origen.nomTipoGasto, 1, @txtUsuario)
        OUTPUT origen.ideTipoGasto, inserted.ideTipoGasto INTO @copiados (ideOrigen, ideDestino);

        SET @numTipos = @@ROWCOUNT;

        INSERT INTO proceso.TMD_TIPO_GASTO_CUENTA
              (ideTipoGasto, numAnio, numMes, codCuenta, nomCuenta, codCentroCosto, nomCentroCosto,
               flgEstado, txtUsuarioCreacion)
        SELECT c.ideDestino, @numAnio, @numMes, o.codCuenta, o.nomCuenta, o.codCentroCosto, o.nomCentroCosto,
               1, @txtUsuario
        FROM @copiados c
        JOIN proceso.TMD_TIPO_GASTO_CUENTA o
          ON o.ideTipoGasto = c.ideOrigen AND o.flgEstado = 1
        WHERE NOT EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_CUENTA d
                          WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                            AND d.codCuenta = o.codCuenta AND d.codCentroCosto = o.codCentroCosto
                            AND d.flgEstado = 1);

        SET @numCuentas = @@ROWCOUNT;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @numAnioOrigen AS numAnioOrigen, @numMesOrigen AS numMesOrigen,
           @numTipos AS numTipos, @numCuentas AS numCuentas;
END
GO

/* -------------------------------------------------------------------------
   6. Procesamiento: el tipo de gasto sale de la configuracion, no de un CASE

   Igual que el script 37, salvo el gasto de personal: se inserta con
   'Categoria Desconocida' (el ELSE del CASE anterior) y luego se actualiza
   con los tipos de gasto vigentes para el periodo.
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

    -- Tipos de gasto vigentes: los del periodo o los del ultimo anterior que
    -- tenga; sin ninguno anterior, los mas antiguos.
    DECLARE @numAnioTipoGasto int, @numMesTipoGasto int;

    SELECT TOP (1) @numAnioTipoGasto = numAnio, @numMesTipoGasto = numMes
    FROM proceso.TMC_TIPO_GASTO
    WHERE flgEstado = 1 AND numAnio * 100 + numMes <= @numAnio * 100 + @numMes
    ORDER BY numAnio DESC, numMes DESC;

    IF @numAnioTipoGasto IS NULL
        SELECT TOP (1) @numAnioTipoGasto = numAnio, @numMesTipoGasto = numMes
        FROM proceso.TMC_TIPO_GASTO
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
                -- El tipo de gasto se completa abajo, con la configuracion del periodo.
                ''Categoria Desconocida'',
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

        -- Reemplaza el CASE fijo de FA, PAR, TUCARI y TUQUIAR.
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

        -- Reemplaza el CASE fijo de tipos de gasto. Primero las cuentas que valen
        -- en cualquier centro de costo y luego las de un centro de costo
        -- concreto, que pesan mas (como el reembolso del 111 en el CASE).
        UPDATE gp
        SET gp.txtTipoGasto = t.nomTipoGasto
        FROM proceso.TMD_GASTO_PERSONAL gp
        JOIN proceso.TMD_TIPO_GASTO_CUENTA c
          ON c.codCuenta = gp.account
         AND c.codCentroCosto = ''
         AND c.numAnio = @numAnioTipoGasto AND c.numMes = @numMesTipoGasto
         AND c.flgEstado = 1
        JOIN proceso.TMC_TIPO_GASTO t
          ON t.ideTipoGasto = c.ideTipoGasto AND t.flgEstado = 1
        WHERE gp.idePeriodo = @idePeriodo;

        UPDATE gp
        SET gp.txtTipoGasto = t.nomTipoGasto
        FROM proceso.TMD_GASTO_PERSONAL gp
        JOIN proceso.TMD_TIPO_GASTO_CUENTA c
          ON c.codCuenta = gp.account
         AND c.codCentroCosto <> ''
         AND c.codCentroCosto = gp.CostCenter
         AND c.numAnio = @numAnioTipoGasto AND c.numMes = @numMesTipoGasto
         AND c.flgEstado = 1
        JOIN proceso.TMC_TIPO_GASTO t
          ON t.ideTipoGasto = c.ideTipoGasto AND t.flgEstado = 1
        WHERE gp.idePeriodo = @idePeriodo;

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
   7. Precarga de enero 2025 con las listas del CASE original (script 37)

   Solo si enero 2025 aun no tiene tipos de gasto. El nombre de cada cuenta
   y centro de costo se toma de SPRING cuando esta disponible.
   ------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM proceso.TMC_TIPO_GASTO WHERE numAnio = 2025 AND numMes = 1)
BEGIN
    DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

    DECLARE @precarga TABLE (nomTipoGasto varchar(30), codCuenta varchar(30), codCentroCosto varchar(10));
    INSERT INTO @precarga (nomTipoGasto, codCuenta, codCentroCosto) VALUES
   ('Reembolso y Proinv.', '63112040', '111'),
   ('Reembolso y Proinv.', '64310010', '111'),
   ('Reembolso y Proinv.', '64320010', '111'),
   ('Reembolso y Proinv.', '65990070', '111'),
   ('Gasto de Personal', '62110010', ''),
   ('Gasto de Personal', '62120010', ''),
   ('Gasto de Personal', '62130010', ''),
   ('Gasto de Personal', '62140010', ''),
   ('Gasto de Personal', '62150010', ''),
   ('Gasto de Personal', '62200010', ''),
   ('Gasto de Personal', '62500010', ''),
   ('Gasto de Personal', '62500031', ''),
   ('Gasto de Personal', '62500050', ''),
   ('Gasto de Personal', '62600010', ''),
   ('Gasto de Personal', '62710010', ''),
   ('Gasto de Personal', '62720010', ''),
   ('Gasto de Personal', '62750010', ''),
   ('Gasto de Personal', '62910010', ''),
   ('Gasto de Personal', '62920010', ''),
   ('Bonos y Otros', '62200020', ''),
   ('Bonos y Otros', '62200030', ''),
   ('Bonos y Otros', '62200040', ''),
   ('Bonos y Otros', '62200050', ''),
   ('Bonos y Otros', '62300010', ''),
   ('Bonos y Otros', '62400010', ''),
   ('Bonos y Otros', '62500020', ''),
   ('Bonos y Otros', '62500030', ''),
   ('Bonos y Otros', '62930010', ''),
   ('Gastos Financiero', '63910010', ''),
   ('Otros', '65514050', ''),
   ('Otros', '65514060', ''),
   ('Gasto Operativo', '62500040', ''),
   ('Gasto Operativo', '62730010', ''),
   ('Gasto Operativo', '62740010', ''),
   ('Gasto Operativo', '62800010', ''),
   ('Gasto Operativo', '63111010', ''),
   ('Gasto Operativo', '63112010', ''),
   ('Gasto Operativo', '63112020', ''),
   ('Gasto Operativo', '63112030', ''),
   ('Gasto Operativo', '63112040', ''),
   ('Gasto Operativo', '63112050', ''),
   ('Gasto Operativo', '63120010', ''),
   ('Gasto Operativo', '63130010', ''),
   ('Gasto Operativo', '63140010', ''),
   ('Gasto Operativo', '63150010', ''),
   ('Gasto Operativo', '63210010', ''),
   ('Gasto Operativo', '63210020', ''),
   ('Gasto Operativo', '63220010', ''),
   ('Gasto Operativo', '63220020', ''),
   ('Gasto Operativo', '63230010', ''),
   ('Gasto Operativo', '63230020', ''),
   ('Gasto Operativo', '63230030', ''),
   ('Gasto Operativo', '63240010', ''),
   ('Gasto Operativo', '63240020', ''),
   ('Gasto Operativo', '63250010', ''),
   ('Gasto Operativo', '63250020', ''),
   ('Gasto Operativo', '63260010', ''),
   ('Gasto Operativo', '63260020', ''),
   ('Gasto Operativo', '63270010', ''),
   ('Gasto Operativo', '63270020', ''),
   ('Gasto Operativo', '63290010', ''),
   ('Gasto Operativo', '63290020', ''),
   ('Gasto Operativo', '63300010', ''),
   ('Gasto Operativo', '63410010', ''),
   ('Gasto Operativo', '63420010', ''),
   ('Gasto Operativo', '63422010', ''),
   ('Gasto Operativo', '63430010', ''),
   ('Gasto Operativo', '63430020', ''),
   ('Gasto Operativo', '63430030', ''),
   ('Gasto Operativo', '63430040', ''),
   ('Gasto Operativo', '63440010', ''),
   ('Gasto Operativo', '63450010', ''),
   ('Gasto Operativo', '63510010', ''),
   ('Gasto Operativo', '63520010', ''),
   ('Gasto Operativo', '63530010', ''),
   ('Gasto Operativo', '63540010', ''),
   ('Gasto Operativo', '63560010', ''),
   ('Gasto Operativo', '63610010', ''),
   ('Gasto Operativo', '63620010', ''),
   ('Gasto Operativo', '63630010', ''),
   ('Gasto Operativo', '63640010', ''),
   ('Gasto Operativo', '63640020', ''),
   ('Gasto Operativo', '63650010', ''),
   ('Gasto Operativo', '63660010', ''),
   ('Gasto Operativo', '63670010', ''),
   ('Gasto Operativo', '63710010', ''),
   ('Gasto Operativo', '63710020', ''),
   ('Gasto Operativo', '63710030', ''),
   ('Gasto Operativo', '63720010', ''),
   ('Gasto Operativo', '63730010', ''),
   ('Gasto Operativo', '63801010', ''),
   ('Gasto Operativo', '63801020', ''),
   ('Gasto Operativo', '63801030', ''),
   ('Gasto Operativo', '63801040', ''),
   ('Gasto Operativo', '63801050', ''),
   ('Gasto Operativo', '63801060', ''),
   ('Gasto Operativo', '63801070', ''),
   ('Gasto Operativo', '63801080', ''),
   ('Gasto Operativo', '63801090', ''),
   ('Gasto Operativo', '63802010', ''),
   ('Gasto Operativo', '63802020', ''),
   ('Gasto Operativo', '63802030', ''),
   ('Gasto Operativo', '63802040', ''),
   ('Gasto Operativo', '63802050', ''),
   ('Gasto Operativo', '63802060', ''),
   ('Gasto Operativo', '63803020', ''),
   ('Gasto Operativo', '63803030', ''),
   ('Gasto Operativo', '63803040', ''),
   ('Gasto Operativo', '63920010', ''),
   ('Gasto Operativo', '63930020', ''),
   ('Gasto Operativo', '63930050', ''),
   ('Gasto Operativo', '63930060', ''),
   ('Gasto Operativo', '63930090', ''),
   ('Gasto Operativo', '64110010', ''),
   ('Gasto Operativo', '64120010', ''),
   ('Gasto Operativo', '64130010', ''),
   ('Gasto Operativo', '64140010', ''),
   ('Gasto Operativo', '64150010', ''),
   ('Gasto Operativo', '64160010', ''),
   ('Gasto Operativo', '64190010', ''),
   ('Gasto Operativo', '64190020', ''),
   ('Gasto Operativo', '64200010', ''),
   ('Gasto Operativo', '64310010', ''),
   ('Gasto Operativo', '64320010', ''),
   ('Gasto Operativo', '64330010', ''),
   ('Gasto Operativo', '64340010', ''),
   ('Gasto Operativo', '64390010', ''),
   ('Gasto Operativo', '64410010', ''),
   ('Gasto Operativo', '64420010', ''),
   ('Gasto Operativo', '64430010', ''),
   ('Gasto Operativo', '65100010', ''),
   ('Gasto Operativo', '65100020', ''),
   ('Gasto Operativo', '65100030', ''),
   ('Gasto Operativo', '65100040', ''),
   ('Gasto Operativo', '65100050', ''),
   ('Gasto Operativo', '65100060', ''),
   ('Gasto Operativo', '65100070', ''),
   ('Gasto Operativo', '65200010', ''),
   ('Gasto Operativo', '65300010', ''),
   ('Gasto Operativo', '65400010', ''),
   ('Gasto Operativo', '65514030', ''),
   ('Gasto Operativo', '65600010', ''),
   ('Gasto Operativo', '65600020', ''),
   ('Gasto Operativo', '65600030', ''),
   ('Gasto Operativo', '65600031', ''),
   ('Gasto Operativo', '65600040', ''),
   ('Gasto Operativo', '65600050', ''),
   ('Gasto Operativo', '65600060', ''),
   ('Gasto Operativo', '65600070', ''),
   ('Gasto Operativo', '65600080', ''),
   ('Gasto Operativo', '65600090', ''),
   ('Gasto Operativo', '65800010', ''),
   ('Gasto Operativo', '65910010', ''),
   ('Gasto Operativo', '65990010', ''),
   ('Gasto Operativo', '65990020', ''),
   ('Gasto Operativo', '65990030', ''),
   ('Gasto Operativo', '65990040', ''),
   ('Gasto Operativo', '65990050', ''),
   ('Gasto Operativo', '65990060', ''),
   ('Gasto Operativo', '65990070', ''),
   ('Gasto Operativo', '65990080', '');

    INSERT INTO proceso.TMC_TIPO_GASTO (numAnio, numMes, nomTipoGasto, flgEstado, txtUsuarioCreacion)
    SELECT DISTINCT 2025, 1, nomTipoGasto, 1, @usuario FROM @precarga;

    INSERT INTO proceso.TMD_TIPO_GASTO_CUENTA
          (ideTipoGasto, numAnio, numMes, codCuenta, codCentroCosto, flgEstado, txtUsuarioCreacion)
    SELECT t.ideTipoGasto, 2025, 1, p.codCuenta, p.codCentroCosto, 1, @usuario
    FROM @precarga p
    JOIN proceso.TMC_TIPO_GASTO t
      ON t.numAnio = 2025 AND t.numMes = 1 AND t.nomTipoGasto = p.nomTipoGasto AND t.flgEstado = 1;

    IF DB_ID('BD_SPRING') IS NOT NULL
    BEGIN
        EXEC sp_executesql N'
            UPDATE c
            SET c.nomCuenta = TRIM(am.localname)
            FROM proceso.TMD_TIPO_GASTO_CUENTA c
            JOIN BD_SPRING.dbo.accountmst am ON TRIM(am.account) = c.codCuenta
            WHERE c.numAnio = 2025 AND c.numMes = 1 AND c.nomCuenta IS NULL;';

        IF OBJECT_ID('BD_SPRING.dbo.AC_CostCenterMst') IS NOT NULL
            EXEC sp_executesql N'
                UPDATE c
                SET c.nomCentroCosto = TRIM(cc.LocalName)
                FROM proceso.TMD_TIPO_GASTO_CUENTA c
                JOIN BD_SPRING.dbo.AC_CostCenterMst cc ON TRIM(cc.CostCenter) = c.codCentroCosto
                WHERE c.numAnio = 2025 AND c.numMes = 1 AND c.codCentroCosto <> '''' AND c.nomCentroCosto IS NULL;';
    END
END
GO

/* -------------------------------------------------------------------------
   8. Opcion de menu del Contador
   ------------------------------------------------------------------------- */

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'TIPO_GASTO_PERSONAL', 'Tipo de gasto de personal', '/costo-labor/tipo-gasto-personal',
       'bi bi-wallet2', p.ideOpcion, 8, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'TIPO_GASTO_PERSONAL');
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'COSTO_LABOR'), ('CONTADOR', 'TIPO_GASTO_PERSONAL')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
