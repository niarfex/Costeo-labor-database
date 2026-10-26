/* =========================================================================
   51 - Tipo de gasto de personal agrupado por proyecto

   Hasta ahora un tipo de gasto agrupaba cuentas contables. Los proyectos
   de innovacion y de reaprovechamiento, que se excluyen del calculo del
   costo labor, se quieren identificar igual por su tipo de gasto para
   conocer sus montos. Para eso un tipo de gasto agrupa ahora por cuenta o
   por proyecto (afe de SPRING), nunca por ambos:

     - proceso.TMC_TIPO_GASTO.codAgrupacion: 'CUENTA' (lo de siempre, valor
       por defecto) o 'PROYECTO'.
     - proceso.TMD_TIPO_GASTO_PROYECTO: los proyectos de cada tipo. Un
       proyecto va en un solo tipo del periodo.
     - El proyecto se valida contra BD_SPRING (afemst) y su nombre se copia
       de alli (englishname, el mismo del resto de opciones de proyectos).
       Para buscarlos se usa proceso.usp_ProyectoSpring_Listar (script 45).
     - "Replicar del periodo anterior" tambien copia los proyectos.
     - Gasto de Personal y Gasto Operativo siguen siendo por cuenta: los
       reportes del costo labor los leen por su nombre y sus cuentas.

   Procesamiento: despues de la clasificacion por cuenta, las lineas del
   gasto de personal cuyo afe esta en un tipo agrupado por proyecto toman
   ese tipo (el proyecto pesa mas que la cuenta), pero solo si el proyecto
   esta excluido del calculo en el periodo procesado
   (proceso.TMD_PROYECTO_EXCLUIDO, script 50). Asi un tipo por proyecto
   nunca saca del Gasto de Personal o del Gasto Operativo las lineas de un
   proyecto que si entra al costo labor. Lo hace
   proceso.usp_GastoPersonal_ClasificarPorProyecto, que llama
   proceso.usp_Periodo_Procesar con la configuracion de tipos vigente para
   el periodo (la misma que usan las cuentas).

   Centro de costo: SPRING guarda el de cada linea con ceros a la izquierda
   ('0111') y la configuracion puede no tenerlos ('111' en la precarga del
   script 40). La clasificacion por cuenta, las validaciones de cuenta
   repetida y la replica comparan el centro de costo sin ceros a la
   izquierda (proceso.ufn_CentroCostoNormalizado). Vacio sigue siendo
   "cualquier centro de costo".

   Errores nuevos:
     50134  el proyecto ya esta en otro tipo de gasto del periodo
     50135  el proyecto no existe en SPRING
     50136  agrupacion no valida, o cuentas y proyectos en el mismo tipo
     50137  Gasto de Personal y Gasto Operativo no se agrupan por proyecto

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
   1. Agrupacion del tipo de gasto

   Los tipos que ya existen agrupan cuentas: el valor por defecto los deja
   como estaban.
   ------------------------------------------------------------------------- */

IF COL_LENGTH('proceso.TMC_TIPO_GASTO', 'codAgrupacion') IS NULL
    ALTER TABLE proceso.TMC_TIPO_GASTO
        ADD codAgrupacion varchar(10) NOT NULL
            CONSTRAINT DF_TMC_TIPO_GASTO_codAgrupacion DEFAULT ('CUENTA');
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = 'CK_TMC_TIPO_GASTO_codAgrupacion'
                 AND parent_object_id = OBJECT_ID('proceso.TMC_TIPO_GASTO'))
    ALTER TABLE proceso.TMC_TIPO_GASTO
        ADD CONSTRAINT CK_TMC_TIPO_GASTO_codAgrupacion CHECK (codAgrupacion IN ('CUENTA', 'PROYECTO'));
GO

/* -------------------------------------------------------------------------
   2. Proyectos del tipo de gasto
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMD_TIPO_GASTO_PROYECTO') IS NULL
BEGIN
    CREATE TABLE proceso.TMD_TIPO_GASTO_PROYECTO(
        ideTipoGastoProyecto bigint IDENTITY(1,1) NOT NULL,
        ideTipoGasto bigint NOT NULL,
        -- Repetidos de la cabecera para que el indice unico impida tener un
        -- proyecto en dos tipos del mismo periodo.
        numAnio int NOT NULL,
        numMes int NOT NULL,
        -- Mismo valor que proceso.TMD_GASTO_PERSONAL.afe (TRIM de SPRING).
        codProyecto varchar(12) NOT NULL,
        -- Copia del nombre de SPRING: el periodo cerrado sigue mostrando el de entonces.
        nomProyecto varchar(500) NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_TIPO_GASTO_PROYECTO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_TIPO_GASTO_PROYECTO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_TIPO_GASTO_PROYECTO PRIMARY KEY CLUSTERED (ideTipoGastoProyecto ASC),
        CONSTRAINT FK_TMD_TIPO_GASTO_PROYECTO_TIPO FOREIGN KEY (ideTipoGasto)
            REFERENCES proceso.TMC_TIPO_GASTO (ideTipoGasto)
    );

    CREATE NONCLUSTERED INDEX IX_TMD_TIPO_GASTO_PROYECTO_TIPO
        ON proceso.TMD_TIPO_GASTO_PROYECTO (ideTipoGasto, flgEstado);

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_TIPO_GASTO_PROYECTO_PERIODO
        ON proceso.TMD_TIPO_GASTO_PROYECTO (numAnio, numMes, codProyecto) WHERE flgEstado = 1;
END
GO

-- Mas largo que la columna: un codigo de mas se rechaza con su mensaje y no
-- con un error de truncado.
IF TYPE_ID('proceso.TYPE_TIPO_GASTO_PROYECTO') IS NULL
    CREATE TYPE proceso.TYPE_TIPO_GASTO_PROYECTO AS TABLE (
        codProyecto varchar(30) NOT NULL PRIMARY KEY
    );
GO

/* -------------------------------------------------------------------------
   3. Centro de costo sin ceros a la izquierda

   '111', '0111' y '00111' son el mismo centro de costo. Vacio queda vacio
   (cualquier centro) y uno de solo ceros queda en '0', para no confundirlo
   con vacio.
   ------------------------------------------------------------------------- */

CREATE OR ALTER FUNCTION proceso.ufn_CentroCostoNormalizado (@codCentroCosto varchar(100))
RETURNS varchar(100)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @codigo varchar(100) = TRIM(@codCentroCosto);
    RETURN CASE
        WHEN @codigo IS NULL OR @codigo = '' THEN @codigo
        WHEN @codigo NOT LIKE '%[^0]%' THEN '0'
        ELSE SUBSTRING(@codigo, PATINDEX('%[^0]%', @codigo), 100)
    END;
END
GO

-- Igual que el script 40, salvo que el criterio tambien se compara sin
-- ceros a la izquierda ('111' encuentra '0111'). El codigo se devuelve como
-- lo tiene SPRING (el maestro o, sin el, las lineas) y se guarda tal cual: su
-- formato puede no coincidir con el de las lineas, y por eso todas las
-- comparaciones con ellas son sin ceros a la izquierda.
CREATE OR ALTER PROCEDURE proceso.usp_CentroCostoSpring_Buscar
    @txtCriterio varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50010, 'La base de datos BD_SPRING no esta disponible en este servidor.', 1;

    SET @txtCriterio = NULLIF(TRIM(@txtCriterio), '');
    DECLARE @criterioSinCeros varchar(100) = proceso.ufn_CentroCostoNormalizado(@txtCriterio);

    IF OBJECT_ID('BD_SPRING.dbo.AC_CostCenterMst') IS NOT NULL
        EXEC sp_executesql N'
            SELECT TOP (50) TRIM(cc.CostCenter) AS codCentroCosto, TRIM(cc.LocalName) AS nomCentroCosto
            FROM BD_SPRING.dbo.AC_CostCenterMst cc
            WHERE @txtCriterio IS NULL
               OR TRIM(cc.CostCenter) LIKE @txtCriterio + ''%''
               OR proceso.ufn_CentroCostoNormalizado(cc.CostCenter) LIKE @criterioSinCeros + ''%''
               OR cc.LocalName COLLATE Latin1_General_CI_AI LIKE ''%'' + @txtCriterio + ''%'' COLLATE Latin1_General_CI_AI
            ORDER BY cc.CostCenter;',
            N'@txtCriterio varchar(100), @criterioSinCeros varchar(100)',
            @txtCriterio = @txtCriterio, @criterioSinCeros = @criterioSinCeros;
    ELSE
        EXEC sp_executesql N'
            SELECT TOP (50) codCentroCosto, CAST(NULL AS varchar(200)) AS nomCentroCosto
            FROM (SELECT DISTINCT TRIM(vd.CostCenter) AS codCentroCosto
                  FROM BD_SPRING.dbo.voucherdetail vd
                  WHERE NULLIF(TRIM(vd.CostCenter), '''') IS NOT NULL) c
            WHERE @txtCriterio IS NULL
               OR codCentroCosto LIKE @txtCriterio + ''%''
               OR proceso.ufn_CentroCostoNormalizado(codCentroCosto) LIKE @criterioSinCeros + ''%''
            ORDER BY codCentroCosto;',
            N'@txtCriterio varchar(100), @criterioSinCeros varchar(100)',
            @txtCriterio = @txtCriterio, @criterioSinCeros = @criterioSinCeros;
END
GO

/* -------------------------------------------------------------------------
   4. Listado del periodo

   Cuatro conjuntos de resultados: el resumen (periodo cerrado), los tipos
   de gasto con su agrupacion, las cuentas y los proyectos de todos ellos.
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

    SELECT t.ideTipoGasto, t.numAnio, t.numMes, t.nomTipoGasto, t.codAgrupacion,
           (SELECT COUNT(*) FROM proceso.TMD_TIPO_GASTO_CUENTA c
            WHERE c.ideTipoGasto = t.ideTipoGasto AND c.flgEstado = 1) AS numCuentas,
           (SELECT COUNT(*) FROM proceso.TMD_TIPO_GASTO_PROYECTO p
            WHERE p.ideTipoGasto = t.ideTipoGasto AND p.flgEstado = 1) AS numProyectos
    FROM proceso.TMC_TIPO_GASTO t
    WHERE t.numAnio = @numAnio AND t.numMes = @numMes AND t.flgEstado = 1
    ORDER BY t.nomTipoGasto;

    SELECT c.ideTipoGasto, c.codCuenta, c.nomCuenta, c.codCentroCosto, c.nomCentroCosto
    FROM proceso.TMD_TIPO_GASTO_CUENTA c
    JOIN proceso.TMC_TIPO_GASTO t
      ON t.ideTipoGasto = c.ideTipoGasto AND t.flgEstado = 1
    WHERE c.numAnio = @numAnio AND c.numMes = @numMes AND c.flgEstado = 1
    ORDER BY c.ideTipoGasto, c.codCuenta, c.codCentroCosto;

    SELECT p.ideTipoGasto, p.codProyecto, p.nomProyecto
    FROM proceso.TMD_TIPO_GASTO_PROYECTO p
    JOIN proceso.TMC_TIPO_GASTO t
      ON t.ideTipoGasto = p.ideTipoGasto AND t.flgEstado = 1
    WHERE p.numAnio = @numAnio AND p.numMes = @numMes AND p.flgEstado = 1
    ORDER BY p.ideTipoGasto, p.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   5. Alta y edicion

   Con @ideTipoGasto nulo da de alta; con valor, reemplaza nombre,
   agrupacion y su contenido (cuentas o proyectos). Al cambiar la
   agrupacion, lo de la anterior se da de baja. Devuelve el id del tipo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_TipoGasto_Guardar
    @ideTipoGasto  bigint = NULL,
    @numAnio       int,
    @numMes        int,
    @nomTipoGasto  varchar(100),
    @cuentas       proceso.TYPE_TIPO_GASTO_CUENTA READONLY,
    @txtUsuario    varchar(100),
    -- Al final y opcionales: una llamada sin ellos sigue siendo un tipo por cuenta.
    @codAgrupacion varchar(10) = 'CUENTA',
    @proyectos     proceso.TYPE_TIPO_GASTO_PROYECTO READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Espacios de mas fuera: el nombre es lo que el procesamiento guarda en
    -- cada linea y lo que agrupan los reportes.
    SET @nomTipoGasto = TRIM(@nomTipoGasto);
    WHILE CHARINDEX('  ', @nomTipoGasto) > 0
        SET @nomTipoGasto = REPLACE(@nomTipoGasto, '  ', ' ');

    SET @codAgrupacion = UPPER(TRIM(ISNULL(@codAgrupacion, 'CUENTA')));

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

    IF @codAgrupacion NOT IN ('CUENTA', 'PROYECTO')
        THROW 50136, 'El tipo de gasto se agrupa por cuenta o por proyecto.', 1;

    -- Los reportes toman de estos dos tipos el gasto de personal y el
    -- operativo de todas las cuentas: por proyecto quedarian casi vacios.
    IF @codAgrupacion = 'PROYECTO'
       AND (@nomTipoGasto IN ('Gasto de Personal', 'Gasto Operativo')
            OR @nombreAnterior IN ('Gasto de Personal', 'Gasto Operativo'))
        THROW 50137, 'Gasto de Personal y Gasto Operativo se agrupan por cuenta: los reportes del costo labor los leen asi.', 1;

    -- Con cuentas y proyectos a la vez no se sabria cual manda en cada linea.
    IF (@codAgrupacion = 'CUENTA' AND EXISTS (SELECT 1 FROM @proyectos))
       OR (@codAgrupacion = 'PROYECTO' AND EXISTS (SELECT 1 FROM @cuentas))
        THROW 50136, 'Un tipo de gasto agrupa cuentas o proyectos, no ambos.', 1;

    IF @codAgrupacion = 'CUENTA' AND NOT EXISTS (SELECT 1 FROM @cuentas)
        THROW 50104, 'El tipo de gasto debe tener al menos una cuenta.', 1;

    IF @codAgrupacion = 'PROYECTO' AND NOT EXISTS (SELECT 1 FROM @proyectos)
        THROW 50104, 'El tipo de gasto debe tener al menos un proyecto.', 1;

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

    DECLARE @listaProyectos TABLE (codProyecto varchar(30) NOT NULL PRIMARY KEY);
    INSERT INTO @listaProyectos (codProyecto)
    SELECT DISTINCT UPPER(TRIM(codProyecto))
    FROM @proyectos
    WHERE TRIM(codProyecto) <> '';

    IF @codAgrupacion = 'CUENTA' AND NOT EXISTS (SELECT 1 FROM @lista)
        THROW 50104, 'El tipo de gasto debe tener al menos una cuenta.', 1;

    IF @codAgrupacion = 'PROYECTO' AND NOT EXISTS (SELECT 1 FROM @listaProyectos)
        THROW 50104, 'El tipo de gasto debe tener al menos un proyecto.', 1;

    DECLARE @proyectoLargo varchar(30) =
        (SELECT TOP (1) codProyecto FROM @listaProyectos WHERE LEN(codProyecto) > 12);
    IF @proyectoLargo IS NOT NULL
    BEGIN
        DECLARE @msgLargo varchar(200) = CONCAT('El codigo de proyecto ', @proyectoLargo, ' no es valido.');
        THROW 50104, @msgLargo, 1;
    END

    -- '111' y '0111' son el mismo centro de costo: seria la misma regla dos veces.
    DECLARE @duplicada varchar(300) =
        (SELECT TOP (1) CONCAT('La cuenta ', codCuenta, ' esta repetida con el centro de costo ',
                               MIN(codCentroCosto), ' en el tipo de gasto.')
         FROM @lista
         GROUP BY codCuenta, proceso.ufn_CentroCostoNormalizado(codCentroCosto)
         HAVING COUNT(*) > 1);

    IF @duplicada IS NOT NULL
        THROW 50104, @duplicada, 1;

    -- Una cuenta en dos tipos quedaria clasificada al azar.
    DECLARE @repetida varchar(300) =
        (SELECT TOP (1) CONCAT('La cuenta ', l.codCuenta,
                               CASE WHEN l.codCentroCosto <> '' THEN CONCAT(' (centro de costo ', l.codCentroCosto, ')') ELSE '' END,
                               ' ya esta en el tipo de gasto ', t.nomTipoGasto, '.')
         FROM @lista l
         JOIN proceso.TMD_TIPO_GASTO_CUENTA c
           ON c.codCuenta = l.codCuenta
          AND proceso.ufn_CentroCostoNormalizado(c.codCentroCosto) = proceso.ufn_CentroCostoNormalizado(l.codCentroCosto)
          AND c.flgEstado = 1
         JOIN proceso.TMC_TIPO_GASTO t
           ON t.ideTipoGasto = c.ideTipoGasto AND t.flgEstado = 1
         WHERE c.numAnio = @numAnio AND c.numMes = @numMes
           AND t.ideTipoGasto <> ISNULL(@ideTipoGasto, 0));

    IF @repetida IS NOT NULL
        THROW 50102, @repetida, 1;

    -- Igual con los proyectos.
    DECLARE @proyectoRepetido varchar(300) =
        (SELECT TOP (1) CONCAT('El proyecto ', l.codProyecto, ' ya esta en el tipo de gasto ', t.nomTipoGasto, '.')
         FROM @listaProyectos l
         JOIN proceso.TMD_TIPO_GASTO_PROYECTO p
           ON p.codProyecto = l.codProyecto AND p.flgEstado = 1
         JOIN proceso.TMC_TIPO_GASTO t
           ON t.ideTipoGasto = p.ideTipoGasto AND t.flgEstado = 1
         WHERE p.numAnio = @numAnio AND p.numMes = @numMes
           AND t.ideTipoGasto <> ISNULL(@ideTipoGasto, 0));

    IF @proyectoRepetido IS NOT NULL
        THROW 50134, @proyectoRepetido, 1;

    -- Nombres de SPRING. Sin BD_SPRING se aceptan los codigos tal cual: la
    -- validacion de que existan queda para cuando la base este disponible.
    DECLARE @nombresCuenta TABLE (codCuenta varchar(30) PRIMARY KEY, nomCuenta varchar(500));
    DECLARE @nombresCentro TABLE (codCentroCosto varchar(10) PRIMARY KEY, nomCentroCosto varchar(200));
    DECLARE @nombresProyecto TABLE (codProyecto varchar(30) PRIMARY KEY, nomProyecto varchar(500));

    IF DB_ID('BD_SPRING') IS NOT NULL AND EXISTS (SELECT 1 FROM @lista)
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

            -- El maestro puede escribir el codigo con otros ceros a la izquierda.
            DECLARE @sinCentro varchar(10) =
                (SELECT TOP (1) l.codCentroCosto FROM @lista l
                 WHERE l.codCentroCosto <> ''
                   AND NOT EXISTS (SELECT 1 FROM @nombresCentro n
                                   WHERE proceso.ufn_CentroCostoNormalizado(n.codCentroCosto)
                                       = proceso.ufn_CentroCostoNormalizado(l.codCentroCosto)));
            IF @sinCentro IS NOT NULL
            BEGIN
                DECLARE @msgCentro varchar(200) = CONCAT('El centro de costo ', @sinCentro, ' no existe en SPRING.');
                THROW 50107, @msgCentro, 1;
            END
        END
    END

    IF DB_ID('BD_SPRING') IS NOT NULL AND EXISTS (SELECT 1 FROM @listaProyectos)
    BEGIN
        INSERT INTO @nombresProyecto (codProyecto, nomProyecto)
        EXEC sp_executesql N'
            SELECT TRIM(a.afe), NULLIF(MAX(ISNULL(TRIM(a.englishname), '''')), '''')
            FROM BD_SPRING.dbo.afemst a
            WHERE a.afe IS NOT NULL
            GROUP BY TRIM(a.afe);';

        DECLARE @sinProyecto varchar(30) =
            (SELECT TOP (1) l.codProyecto FROM @listaProyectos l
             WHERE NOT EXISTS (SELECT 1 FROM @nombresProyecto n WHERE n.codProyecto = l.codProyecto));
        IF @sinProyecto IS NOT NULL
        BEGIN
            DECLARE @msgProyecto varchar(200) = CONCAT('El proyecto ', @sinProyecto, ' no existe en SPRING.');
            THROW 50135, @msgProyecto, 1;
        END
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Los nombres que ya tenia cada cuenta y proyecto, por si SPRING no esta disponible.
        DECLARE @previos TABLE (codCuenta varchar(30), codCentroCosto varchar(10), nomCuenta varchar(500),
                                nomCentroCosto varchar(200), PRIMARY KEY (codCuenta, codCentroCosto));
        DECLARE @previosProyecto TABLE (codProyecto varchar(12) PRIMARY KEY, nomProyecto varchar(500));

        IF @ideTipoGasto IS NULL
        BEGIN
            INSERT INTO proceso.TMC_TIPO_GASTO (numAnio, numMes, nomTipoGasto, codAgrupacion, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, @nomTipoGasto, @codAgrupacion, 1, @txtUsuario);
            SET @ideTipoGasto = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE proceso.TMC_TIPO_GASTO
            SET nomTipoGasto = @nomTipoGasto,
                codAgrupacion = @codAgrupacion,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideTipoGasto = @ideTipoGasto;

            INSERT INTO @previos (codCuenta, codCentroCosto, nomCuenta, nomCentroCosto)
            SELECT codCuenta, codCentroCosto, MAX(nomCuenta), MAX(nomCentroCosto)
            FROM proceso.TMD_TIPO_GASTO_CUENTA
            WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1
            GROUP BY codCuenta, codCentroCosto;

            INSERT INTO @previosProyecto (codProyecto, nomProyecto)
            SELECT codProyecto, MAX(nomProyecto)
            FROM proceso.TMD_TIPO_GASTO_PROYECTO
            WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1
            GROUP BY codProyecto;

            UPDATE proceso.TMD_TIPO_GASTO_CUENTA
            SET flgEstado = 0,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1;

            UPDATE proceso.TMD_TIPO_GASTO_PROYECTO
            SET flgEstado = 0,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1;
        END

        -- Solo una de las dos listas tiene filas: se valido arriba. El centro de
        -- costo se guarda como se eligio; su nombre se busca sin ceros a la izquierda.
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
        OUTER APPLY (SELECT TOP (1) n.nomCentroCosto FROM @nombresCentro n
                     WHERE l.codCentroCosto <> ''
                       AND proceso.ufn_CentroCostoNormalizado(n.codCentroCosto)
                         = proceso.ufn_CentroCostoNormalizado(l.codCentroCosto)
                     ORDER BY CASE WHEN n.codCentroCosto = l.codCentroCosto THEN 0 ELSE 1 END) ncc
        OUTER APPLY (SELECT TOP (1) pr.nomCuenta, pr.nomCentroCosto FROM @previos pr
                     WHERE pr.codCuenta = l.codCuenta
                       AND proceso.ufn_CentroCostoNormalizado(pr.codCentroCosto)
                         = proceso.ufn_CentroCostoNormalizado(l.codCentroCosto)
                     ORDER BY CASE WHEN pr.codCentroCosto = l.codCentroCosto THEN 0 ELSE 1 END) p;

        INSERT INTO proceso.TMD_TIPO_GASTO_PROYECTO
              (ideTipoGasto, numAnio, numMes, codProyecto, nomProyecto, flgEstado, txtUsuarioCreacion)
        SELECT @ideTipoGasto, @numAnio, @numMes, l.codProyecto,
               COALESCE(np.nomProyecto, pp.nomProyecto),
               1, @txtUsuario
        FROM @listaProyectos l
        LEFT JOIN @nombresProyecto np ON np.codProyecto = l.codProyecto
        LEFT JOIN @previosProyecto pp ON pp.codProyecto = l.codProyecto;

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

    UPDATE proceso.TMD_TIPO_GASTO_PROYECTO
    SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
    WHERE ideTipoGasto = @ideTipoGasto AND flgEstado = 1;

    UPDATE proceso.TMC_TIPO_GASTO
    SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
    WHERE ideTipoGasto = @ideTipoGasto;

    COMMIT TRANSACTION;
END
GO

/* -------------------------------------------------------------------------
   6. Replicar del periodo anterior

   Copia los tipos que el periodo aun no tiene, con su agrupacion y sus
   cuentas o proyectos, salvo los que ya esten en otro tipo del periodo. Un
   tipo que se quedaria vacio no se copia. Devuelve el periodo de origen y
   cuanto copio.
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
    DECLARE @numTipos int = 0, @numCuentas int = 0, @numProyectos int = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Bloquea el periodo destino: dos replicas a la vez duplicarian tipos.
        DECLARE @bloqueo int =
            (SELECT COUNT(*) FROM proceso.TMC_TIPO_GASTO WITH (UPDLOCK, HOLDLOCK)
             WHERE numAnio = @numAnio AND numMes = @numMes);

        -- MERGE y no INSERT: es la forma de saber que id nuevo le toco a cada tipo de origen.
        MERGE proceso.TMC_TIPO_GASTO AS destino
        USING (SELECT o.ideTipoGasto, o.nomTipoGasto, o.codAgrupacion
               FROM proceso.TMC_TIPO_GASTO o
               WHERE o.numAnio = @numAnioOrigen AND o.numMes = @numMesOrigen AND o.flgEstado = 1
                 AND NOT EXISTS (SELECT 1 FROM proceso.TMC_TIPO_GASTO d
                                 WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                                   AND d.nomTipoGasto = o.nomTipoGasto AND d.flgEstado = 1)
                 -- Al menos una cuenta o un proyecto libre en el destino; si no, quedaria vacio.
                 AND (EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_CUENTA oc
                              WHERE oc.ideTipoGasto = o.ideTipoGasto AND oc.flgEstado = 1
                                AND NOT EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_CUENTA dc
                                                WHERE dc.numAnio = @numAnio AND dc.numMes = @numMes
                                                  AND dc.codCuenta = oc.codCuenta
                                                  AND proceso.ufn_CentroCostoNormalizado(dc.codCentroCosto)
                                                    = proceso.ufn_CentroCostoNormalizado(oc.codCentroCosto)
                                                  AND dc.flgEstado = 1))
                      OR EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_PROYECTO op
                                 WHERE op.ideTipoGasto = o.ideTipoGasto AND op.flgEstado = 1
                                   AND NOT EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_PROYECTO dp
                                                   WHERE dp.numAnio = @numAnio AND dp.numMes = @numMes
                                                     AND dp.codProyecto = op.codProyecto
                                                     AND dp.flgEstado = 1)))) AS origen
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (numAnio, numMes, nomTipoGasto, codAgrupacion, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, origen.nomTipoGasto, origen.codAgrupacion, 1, @txtUsuario)
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
                            AND d.codCuenta = o.codCuenta
                            AND proceso.ufn_CentroCostoNormalizado(d.codCentroCosto)
                              = proceso.ufn_CentroCostoNormalizado(o.codCentroCosto)
                            AND d.flgEstado = 1);

        SET @numCuentas = @@ROWCOUNT;

        INSERT INTO proceso.TMD_TIPO_GASTO_PROYECTO
              (ideTipoGasto, numAnio, numMes, codProyecto, nomProyecto, flgEstado, txtUsuarioCreacion)
        SELECT c.ideDestino, @numAnio, @numMes, o.codProyecto, o.nomProyecto, 1, @txtUsuario
        FROM @copiados c
        JOIN proceso.TMD_TIPO_GASTO_PROYECTO o
          ON o.ideTipoGasto = c.ideOrigen AND o.flgEstado = 1
        WHERE NOT EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_PROYECTO d
                          WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                            AND d.codProyecto = o.codProyecto
                            AND d.flgEstado = 1);

        SET @numProyectos = @@ROWCOUNT;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @numAnioOrigen AS numAnioOrigen, @numMesOrigen AS numMesOrigen,
           @numTipos AS numTipos, @numCuentas AS numCuentas, @numProyectos AS numProyectos;
END
GO

/* -------------------------------------------------------------------------
   7. Procesamiento: clasificacion por proyecto

   Se ejecuta despues de la clasificacion por cuenta, dentro de la misma
   transaccion de proceso.usp_Periodo_Procesar y con su configuracion de
   tipos vigente. Solo toca las lineas de los proyectos excluidos del
   periodo procesado (no del periodo de los tipos): las demas conservan el
   tipo de su cuenta. Sin la tabla de proyectos excluidos no clasifica nada
   por proyecto. No devuelve resultados: el backend lee como primera
   respuesta del procesamiento el estado del periodo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_GastoPersonal_ClasificarPorProyecto
    @idePeriodo       bigint,
    @numAnioTipoGasto int,
    @numMesTipoGasto  int
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('proceso.TMD_PROYECTO_EXCLUIDO') IS NULL
        RETURN;

    DECLARE @numAnio int, @numMes int;

    SELECT @numAnio = numAnio, @numMes = numMes
    FROM registro.TMC_PERIODO
    WHERE idePeriodo = @idePeriodo;

    -- El proyecto pesa mas que la cuenta: la linea de un proyecto excluido
    -- toma el tipo de su proyecto aunque su cuenta ya la hubiera clasificado.
    -- Dinamico porque la tabla de excluidos la crea otro script: el
    -- procedimiento debe compilar y ejecutarse aunque no exista.
    EXEC sp_executesql N'
        UPDATE gp
        SET gp.txtTipoGasto = t.nomTipoGasto
        FROM proceso.TMD_GASTO_PERSONAL gp
        JOIN proceso.TMD_TIPO_GASTO_PROYECTO p
          ON p.codProyecto = TRIM(gp.afe)
         AND p.numAnio = @numAnioTipoGasto AND p.numMes = @numMesTipoGasto
         AND p.flgEstado = 1
        JOIN proceso.TMC_TIPO_GASTO t
          ON t.ideTipoGasto = p.ideTipoGasto AND t.flgEstado = 1 AND t.codAgrupacion = ''PROYECTO''
        WHERE gp.idePeriodo = @idePeriodo
          AND EXISTS (SELECT 1 FROM proceso.TMD_PROYECTO_EXCLUIDO e
                      WHERE e.numAnio = @numAnio AND e.numMes = @numMes
                        AND e.codProyecto = TRIM(gp.afe) AND e.flgEstado = 1);',
        N'@idePeriodo bigint, @numAnioTipoGasto int, @numMesTipoGasto int, @numAnio int, @numMes int',
        @idePeriodo = @idePeriodo, @numAnioTipoGasto = @numAnioTipoGasto, @numMesTipoGasto = @numMesTipoGasto,
        @numAnio = @numAnio, @numMes = @numMes;
END
GO

/* -------------------------------------------------------------------------
   8. Procesamiento del periodo

   Igual que el script 40, con dos cambios: la cuenta con centro de costo
   compara el centro sin ceros a la izquierda (la precarga tiene '111' y
   SPRING '0111'), y despues de la clasificacion por cuentas va la de los
   proyectos excluidos.
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

        -- Sin ceros a la izquierda: la configuracion puede tener '111' y la linea '0111'.
        UPDATE gp
        SET gp.txtTipoGasto = t.nomTipoGasto
        FROM proceso.TMD_GASTO_PERSONAL gp
        JOIN proceso.TMD_TIPO_GASTO_CUENTA c
          ON c.codCuenta = gp.account
         AND c.codCentroCosto <> ''
         AND proceso.ufn_CentroCostoNormalizado(c.codCentroCosto) = proceso.ufn_CentroCostoNormalizado(gp.CostCenter)
         AND c.numAnio = @numAnioTipoGasto AND c.numMes = @numMesTipoGasto
         AND c.flgEstado = 1
        JOIN proceso.TMC_TIPO_GASTO t
          ON t.ideTipoGasto = c.ideTipoGasto AND t.flgEstado = 1
        WHERE gp.idePeriodo = @idePeriodo;

        -- Al final: en los proyectos excluidos del periodo, el tipo del
        -- proyecto pesa mas que el de la cuenta.
        EXEC proceso.usp_GastoPersonal_ClasificarPorProyecto
             @idePeriodo = @idePeriodo,
             @numAnioTipoGasto = @numAnioTipoGasto,
             @numMesTipoGasto = @numMesTipoGasto;

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
