/* =========================================================================
   69 - Proyectos de SPRING: solo los de estado A (activo)

   Observaciones: de SPRING solo se traen los proyectos con status = 'A', y
   en ninguna parte del sistema se ofrecen los de estado I (inactivo). El
   registro de horas sigue saliendo del listado de "Actualizacion de estado
   de proyectos".

   Un proyecto es inactivo si figura en BD_SPRING.dbo.afemst sin ninguna
   fila en estado A (proceso.usp_ProyectoSpringInactivo_Listar). Sin
   BD_SPRING no se filtra nada.

   1. proceso.usp_ProyectoSpring_Listar devuelve solo los activos: con eso
      se filtran los buscadores (proyectos excluidos, rentabilidad, tipo de
      gasto) y las validaciones que lo usan.
   2. Estado de proyectos: la replica solo trae de SPRING los activos, no
      copia del periodo anterior los que pasaron a I y da de baja (logica)
      los que el periodo ya tenia en I.
   3. Registro de horas (catalogo, alta de proyecto, columnas de la grilla
      mensual) y Distribucion GIP no ofrecen los inactivos aunque esten
      marcados activos en el periodo. Lo ya registrado no se oculta: la
      grilla mensual sigue sumando los proyectos con horas o agregados por
      el trabajador, y la GIP los que ya tienen distribucion en el anio.
   4. Tipo de gasto: no admite un proyecto inactivo, salvo que el tipo ya lo
      tuviera.
   5. Datos ya cargados: en los periodos no cerrados, los proyectos
      inactivos del estado de proyectos se dan de baja logica (flgEstado =
      0). No hay llaves foraneas hacia la tabla y las horas se guardan por
      codigo en otras tablas, asi que no se pierde ninguna. Los periodos
      cerrados no se tocan.

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

IF OBJECT_ID('proceso.TMD_ESTADO_PROYECTO') IS NULL
   OR NOT EXISTS (SELECT 1 FROM sys.parameters
                  WHERE object_id = OBJECT_ID('proceso.usp_ProyectoSpring_Listar') AND name = '@flgNombreLargo')
    THROW 50154, 'Faltan objetos previos: ejecute antes los scripts 36 y 58.', 1;
GO

/* -------------------------------------------------------------------------
   1. Proyectos inactivos de SPRING

   Codigos sin ninguna fila en estado A. Vacio si BD_SPRING no esta
   disponible.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoSpringInactivo_Listar
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS varchar(30)) AS codProyecto WHERE 1 = 0;
        RETURN;
    END

    EXEC sp_executesql N'
        SELECT CAST(TRIM(afe) AS varchar(30)) AS codProyecto
        FROM BD_SPRING.dbo.afemst
        WHERE afe IS NOT NULL
        GROUP BY TRIM(afe)
        HAVING MAX(CASE WHEN UPPER(TRIM(status)) = ''A'' THEN 1 ELSE 0 END) = 0;';
END
GO

/* -------------------------------------------------------------------------
   2. Maestro de proyectos de SPRING: solo activos

   Reemplaza al del script 58. @flgIncluirInactivos = 1 lo usa el listado de
   estado de proyectos, para no perder el nombre largo en los periodos
   cerrados que aun los tienen.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoSpring_Listar
    @flgNombreLargo      bit = 0,
    @flgIncluirInactivos bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        IF @flgNombreLargo = 1
            SELECT CAST(NULL AS varchar(30))  AS codProyecto,
                   CAST(NULL AS varchar(200)) AS nomProyecto,
                   CAST(NULL AS varchar(1000)) AS nomProyectoLargo
            WHERE 1 = 0;
        ELSE
            SELECT CAST(NULL AS varchar(30))  AS codProyecto,
                   CAST(NULL AS varchar(200)) AS nomProyecto
            WHERE 1 = 0;
        RETURN;
    END

    IF @flgNombreLargo = 1
        EXEC sp_executesql N'
            SELECT codProyecto, nomProyecto, nomProyectoLargo
            FROM (
                SELECT CAST(TRIM(afe) AS varchar(30)) AS codProyecto,
                       CAST(TRIM(englishname) AS varchar(200)) AS nomProyecto,
                       NULLIF(CAST(TRIM(localname) AS varchar(1000)), '''') AS nomProyectoLargo,
                       ROW_NUMBER() OVER (PARTITION BY TRIM(afe) ORDER BY englishname) AS numOrden
                FROM BD_SPRING.dbo.afemst
                WHERE afe IS NOT NULL AND englishname IS NOT NULL
                  AND (@flgIncluirInactivos = 1 OR UPPER(TRIM(status)) = ''A'')
            ) a
            WHERE numOrden = 1;',
            N'@flgIncluirInactivos bit', @flgIncluirInactivos = @flgIncluirInactivos;
    ELSE
        EXEC sp_executesql N'
            SELECT codProyecto, nomProyecto
            FROM (
                SELECT CAST(TRIM(afe) AS varchar(30)) AS codProyecto,
                       CAST(TRIM(englishname) AS varchar(200)) AS nomProyecto,
                       ROW_NUMBER() OVER (PARTITION BY TRIM(afe) ORDER BY englishname) AS numOrden
                FROM BD_SPRING.dbo.afemst
                WHERE afe IS NOT NULL AND englishname IS NOT NULL
                  AND (@flgIncluirInactivos = 1 OR UPPER(TRIM(status)) = ''A'')
            ) a
            WHERE numOrden = 1;',
            N'@flgIncluirInactivos bit', @flgIncluirInactivos = @flgIncluirInactivos;
END
GO

/* -------------------------------------------------------------------------
   3. Replica del estado de proyectos

   Reemplaza a la del script 49. De SPRING solo entran los activos; del
   periodo anterior no se copian los inactivos, y los que el periodo ya
   tenia en I se dan de baja. Mismo conjunto de resultados.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_EstadoProyecto_Replicar
    @numAnio    int,
    @numMes     int,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50080, 'El periodo esta cerrado: el estado de sus proyectos no se puede modificar.', 1;

    -- El periodo anterior es el mas reciente con proyectos, aunque no sea el mes previo.
    DECLARE @numAnioOrigen int, @numMesOrigen int;

    SELECT TOP (1) @numAnioOrigen = numAnio, @numMesOrigen = numMes
    FROM proceso.TMD_ESTADO_PROYECTO
    WHERE flgEstado = 1 AND numAnio * 100 + numMes < @numAnio * 100 + @numMes
    ORDER BY numAnio DESC, numMes DESC;

    DECLARE @haySpring bit = CASE WHEN DB_ID('BD_SPRING') IS NULL THEN 0 ELSE 1 END;

    IF @numAnioOrigen IS NULL AND @haySpring = 0
        THROW 50081, 'No hay un periodo anterior que replicar y la base de datos BD_SPRING no esta disponible.', 1;

    CREATE TABLE #spring (
        codProyecto       varchar(30)  NOT NULL PRIMARY KEY,
        nomProyecto       varchar(200) NOT NULL,
        fecAprobadoSpring datetime     NULL,
        fecInicioSpring   datetime     NULL,
        fecFinSpring      datetime     NULL,
        txtEstadoSpring   varchar(10)  NULL
    );

    CREATE TABLE #inactivos (codProyecto varchar(30) NOT NULL PRIMARY KEY);

    -- Consulta de referencia, solo proyectos en estado A. Si SPRING tuviera dos
    -- filas con el mismo codigo, se queda con una para no romper la clave.
    IF @haySpring = 1
    BEGIN
        INSERT INTO #spring (codProyecto, nomProyecto, fecAprobadoSpring, fecInicioSpring, fecFinSpring, txtEstadoSpring)
        EXEC sp_executesql N'
            SELECT codProyecto, nomProyecto, approveddate, startdate, dateEnd, status
            FROM (
                SELECT CAST(TRIM(afe) AS varchar(30)) AS codProyecto,
                       CAST(TRIM(englishname) AS varchar(200)) AS nomProyecto,
                       approveddate, startdate, dateEnd,
                       CAST(TRIM(status) AS varchar(10)) AS status,
                       ROW_NUMBER() OVER (PARTITION BY TRIM(afe) ORDER BY englishname) AS numOrden
                FROM BD_SPRING.dbo.afemst
                WHERE afe IS NOT NULL AND englishname IS NOT NULL
                  AND UPPER(TRIM(status)) = ''A''
            ) a
            WHERE numOrden = 1;';

        INSERT INTO #inactivos (codProyecto) EXEC proceso.usp_ProyectoSpringInactivo_Listar;
    END

    DECLARE @numCopiados int = 0, @numNuevos int = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Los que el periodo ya tenia y pasaron a inactivos en SPRING.
        UPDATE e
        SET flgEstado = 0,
            fecActualizacion = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        FROM proceso.TMD_ESTADO_PROYECTO e
        JOIN #inactivos i ON i.codProyecto = e.codProyecto
        WHERE e.numAnio = @numAnio AND e.numMes = @numMes AND e.flgEstado = 1;

        -- Del periodo anterior, con el estado que tenia. Las fechas y el estado
        -- de SPRING se toman al dia si el proyecto sigue en SPRING. Los inactivos no se copian.
        IF @numAnioOrigen IS NOT NULL
        BEGIN
            INSERT INTO proceso.TMD_ESTADO_PROYECTO
                  (numAnio, numMes, codProyecto, nomProyecto, fecAprobadoSpring, fecInicioSpring,
                   fecFinSpring, txtEstadoSpring, flgActivoCostoLabor, flgEstado, txtUsuarioCreacion)
            SELECT @numAnio, @numMes, o.codProyecto,
                   COALESCE(s.nomProyecto, o.nomProyecto),
                   CASE WHEN s.codProyecto IS NULL THEN o.fecAprobadoSpring ELSE s.fecAprobadoSpring END,
                   CASE WHEN s.codProyecto IS NULL THEN o.fecInicioSpring ELSE s.fecInicioSpring END,
                   CASE WHEN s.codProyecto IS NULL THEN o.fecFinSpring ELSE s.fecFinSpring END,
                   CASE WHEN s.codProyecto IS NULL THEN o.txtEstadoSpring ELSE s.txtEstadoSpring END,
                   o.flgActivoCostoLabor, 1, @txtUsuario
            FROM proceso.TMD_ESTADO_PROYECTO o
            LEFT JOIN #spring s ON s.codProyecto = o.codProyecto
            WHERE o.numAnio = @numAnioOrigen AND o.numMes = @numMesOrigen AND o.flgEstado = 1
              AND NOT EXISTS (SELECT 1 FROM #inactivos i WHERE i.codProyecto = o.codProyecto)
              AND NOT EXISTS (SELECT 1 FROM proceso.TMD_ESTADO_PROYECTO d
                              WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                                AND d.codProyecto = o.codProyecto AND d.flgEstado = 1);

            SET @numCopiados = @@ROWCOUNT;
        END

        -- Los de SPRING que aun no figuran. En la primera carga (sin periodo anterior)
        -- quedan activos; despues, sin estado, para que el Contador lo indique.
        INSERT INTO proceso.TMD_ESTADO_PROYECTO
              (numAnio, numMes, codProyecto, nomProyecto, fecAprobadoSpring, fecInicioSpring,
               fecFinSpring, txtEstadoSpring, flgActivoCostoLabor, flgEstado, txtUsuarioCreacion)
        SELECT @numAnio, @numMes, s.codProyecto, s.nomProyecto, s.fecAprobadoSpring, s.fecInicioSpring,
               s.fecFinSpring, s.txtEstadoSpring,
               CASE WHEN @numAnioOrigen IS NULL THEN CAST(1 AS bit) END, 1, @txtUsuario
        FROM #spring s
        WHERE NOT EXISTS (SELECT 1 FROM proceso.TMD_ESTADO_PROYECTO d
                          WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                            AND d.codProyecto = s.codProyecto AND d.flgEstado = 1);

        SET @numNuevos = @@ROWCOUNT;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @numAnioOrigen AS numAnioOrigen, @numMesOrigen AS numMesOrigen,
           @numCopiados AS numCopiados, @numNuevos AS numNuevos;
END
GO

/* -------------------------------------------------------------------------
   4. Listado de actualizacion de estado de proyectos

   Reemplaza al del script 58. Solo cambia la llamada al maestro: pide
   tambien los inactivos para mostrar el nombre largo de los periodos
   cerrados.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_EstadoProyecto_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado,
           COUNT(e.ideEstadoProyecto) AS numTotal,
           COUNT(CASE WHEN e.ideEstadoProyecto IS NOT NULL AND e.flgActivoCostoLabor IS NULL THEN 1 END) AS numSinEstado
    FROM (SELECT 1 AS uno) u
    LEFT JOIN proceso.TMD_ESTADO_PROYECTO e
           ON e.numAnio = @numAnio AND e.numMes = @numMes AND e.flgEstado = 1;

    CREATE TABLE #spring (codProyecto      varchar(30)   NOT NULL PRIMARY KEY,
                          nomProyecto      varchar(200)  NOT NULL,
                          nomProyectoLargo varchar(1000) NULL);
    INSERT INTO #spring (codProyecto, nomProyecto, nomProyectoLargo)
        EXEC proceso.usp_ProyectoSpring_Listar @flgNombreLargo = 1, @flgIncluirInactivos = 1;

    SELECT e.ideEstadoProyecto, e.codProyecto, e.nomProyecto, s.nomProyectoLargo,
           e.fecAprobadoSpring, e.fecInicioSpring, e.fecFinSpring, e.txtEstadoSpring,
           e.flgActivoCostoLabor
    FROM proceso.TMD_ESTADO_PROYECTO e
    LEFT JOIN #spring s ON s.codProyecto = e.codProyecto
    WHERE e.numAnio = @numAnio AND e.numMes = @numMes AND e.flgEstado = 1
    ORDER BY e.nomProyecto, e.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   5. Catalogo de proyectos del registro de horas

   Reemplaza al del script 58. Sin los inactivos de SPRING.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Proyecto_ListarCatalogo
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #spring (codProyecto      varchar(30)   NOT NULL PRIMARY KEY,
                          nomProyecto      varchar(200)  NOT NULL,
                          nomProyectoLargo varchar(1000) NULL);
    INSERT INTO #spring (codProyecto, nomProyecto, nomProyectoLargo)
        EXEC proceso.usp_ProyectoSpring_Listar @flgNombreLargo = 1;

    CREATE TABLE #inactivos (codProyecto varchar(30) NOT NULL PRIMARY KEY);
    INSERT INTO #inactivos (codProyecto) EXEC proceso.usp_ProyectoSpringInactivo_Listar;

    SELECT e.codProyecto, e.nomProyecto, s.nomProyectoLargo
    FROM proceso.TMD_ESTADO_PROYECTO e
    LEFT JOIN #spring s ON s.codProyecto = e.codProyecto
    WHERE e.numAnio = @numAnio AND e.numMes = @numMes
      AND e.flgEstado = 1 AND e.flgActivoCostoLabor = 1
      AND NOT EXISTS (SELECT 1 FROM #inactivos i WHERE i.codProyecto = e.codProyecto)
    ORDER BY e.nomProyecto, e.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   6. Agregar un proyecto al periodo del trabajador

   Reemplaza al del script 36. Rechaza los inactivos de SPRING.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_PeriodoProyecto_Agregar
    @numAnio     int,
    @numMes      int,
    @ideEmpleado bigint,
    @codProyecto varchar(30),
    @txtUsuario  varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    SET @codProyecto = TRIM(@codProyecto);

    DECLARE @idePeriodo bigint,
            @flgPeriodo int;

    SELECT @idePeriodo = idePeriodo, @flgPeriodo = flgEstado
    FROM registro.TMC_PERIODO
    WHERE numAnio = @numAnio AND numMes = @numMes;

    IF @idePeriodo IS NULL OR @flgPeriodo <> 1
        THROW 50010, 'El periodo no existe o se encuentra cerrado.', 1;

    DECLARE @nomProyecto varchar(200) =
        (SELECT TOP (1) nomProyecto FROM proceso.TMD_ESTADO_PROYECTO
         WHERE numAnio = @numAnio AND numMes = @numMes AND codProyecto = @codProyecto
           AND flgEstado = 1 AND flgActivoCostoLabor = 1);

    IF @nomProyecto IS NULL
        THROW 50060, 'El proyecto no esta activo para Costo Labor en el periodo.', 1;

    CREATE TABLE #inactivos (codProyecto varchar(30) NOT NULL PRIMARY KEY);
    INSERT INTO #inactivos (codProyecto) EXEC proceso.usp_ProyectoSpringInactivo_Listar;

    IF EXISTS (SELECT 1 FROM #inactivos WHERE codProyecto = @codProyecto)
        THROW 50060, 'El proyecto esta inactivo en SPRING (estado I).', 1;

    -- Los periodos anteriores guardaban el codigo con 6 digitos, que es el de
    -- afemst sin los seis ceros iniciales. No se compara solo por los ultimos
    -- seis: en afemst hay proyectos distintos que los comparten (000000000019
    -- 5 RELAVERAS y 002026000019 Lodocretos).
    IF EXISTS (SELECT 1 FROM registro.TMD_PERIODO_PROYECTO
               WHERE numAnio = @numAnio AND numMes = @numMes
                 AND ideEmpleado = @ideEmpleado AND flgEstado = 1
                 AND CASE WHEN LEN(codProyecto) = 6 THEN CONCAT('000000', codProyecto) ELSE codProyecto END = @codProyecto)
        THROW 50061, 'El proyecto ya fue agregado en el periodo.', 1;

    -- Nombre del trabajador: el del periodo, el de su usuario o el de SPRING.
    DECLARE @nomEmpleado varchar(200) =
        (SELECT TOP (1) nomEmpleado FROM registro.TMD_PERIODO_EMPLEADO
         WHERE numAnio = @numAnio AND numMes = @numMes
           AND ideEmpleado = @ideEmpleado AND flgEstado = 1);

    IF @nomEmpleado IS NULL
        SELECT TOP (1) @nomEmpleado = txtNombreCompleto
        FROM seguridad.TMD_PERFIL_USUARIO
        WHERE ideEmpleado = @ideEmpleado AND txtNombreCompleto IS NOT NULL
        ORDER BY flgEstado DESC, idePerfilUsuario DESC;

    IF @nomEmpleado IS NULL AND DB_ID('BD_SPRING') IS NOT NULL
        EXEC sp_executesql N'
            SELECT TOP (1) @nombre = CAST(TRIM(NombreCompleto) AS varchar(200))
            FROM BD_SPRING.dbo.PersonaMast
            WHERE Persona = @persona;',
            N'@persona bigint, @nombre varchar(200) OUTPUT',
            @persona = @ideEmpleado, @nombre = @nomEmpleado OUTPUT;

    -- Un ideEmpleado inventado no debe dar de alta a un trabajador en el periodo.
    IF @nomEmpleado IS NULL
        THROW 50065, 'El trabajador indicado no existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Con dos altas a la vez del mismo trabajador, el bloqueo evita dos filas.
        IF NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO WITH (UPDLOCK, HOLDLOCK)
                       WHERE numAnio = @numAnio AND numMes = @numMes
                         AND ideEmpleado = @ideEmpleado AND flgEstado = 1)
            INSERT INTO registro.TMD_PERIODO_EMPLEADO
                  (idePeriodo, numAnio, numMes, ideEmpleado, nomEmpleado,
                   flgEstado, txtUsuarioCreacion)
            VALUES (@idePeriodo, @numAnio, @numMes, @ideEmpleado, @nomEmpleado,
                   1, @txtUsuario);

        INSERT INTO registro.TMD_PERIODO_PROYECTO
              (idePeriodo, numAnio, numMes, codProyecto, nomProyecto,
               ideEmpleado, nomEmpleado, flgEstado, txtUsuarioCreacion)
        VALUES (@idePeriodo, @numAnio, @numMes, @codProyecto, @nomProyecto,
               @ideEmpleado, @nomEmpleado, 1, @txtUsuario);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- Fuera de la transaccion y sin propagar el error: si SPRING no responde,
    -- el proyecto ya quedo agregado y la jefatura se completa en la siguiente alta.
    BEGIN TRY
        EXEC registro.usp_PeriodoEmpleado_CompletarOrganizacion @numAnio = @numAnio, @numMes = @numMes;
    END TRY
    BEGIN CATCH
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   7. Grilla mensual: columnas

   Reemplaza a la del script 52. Los activos del periodo sin los inactivos
   de SPRING; los proyectos agregados o con horas siguen saliendo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarProyectos
    @numAnio               int,
    @numMes                int,
    @ideEmpleadoJefe       bigint = NULL,
    @ideEmpleado           bigint = NULL,
    @txtUsuarioResponsable varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #inactivos (codProyecto varchar(30) NOT NULL PRIMARY KEY);
    INSERT INTO #inactivos (codProyecto) EXEC proceso.usp_ProyectoSpringInactivo_Listar;

    WITH visibles AS (
        SELECT pe.ideEmpleado
        FROM registro.TMD_PERIODO_EMPLEADO pe
        WHERE pe.numAnio = @numAnio
          AND pe.numMes  = @numMes
          AND pe.flgEstado = 1
          AND (@ideEmpleadoJefe IS NULL
               OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
               OR pe.ideEmpleado = @ideEmpleadoJefe)
          AND (@ideEmpleado IS NULL OR pe.ideEmpleado = @ideEmpleado)
          AND (@txtUsuarioResponsable IS NULL
               OR EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE a
                          WHERE a.numAnio = pe.numAnio AND a.numMes = pe.numMes
                            AND a.ideEmpleado = pe.ideEmpleado AND a.flgEstado = 1
                            AND a.txtUsuarioResponsable = @txtUsuarioResponsable))
    ),
    columnas AS (
        SELECT e.codProyecto, e.nomProyecto, 1 AS numPrioridad
        FROM proceso.TMD_ESTADO_PROYECTO e
        WHERE e.numAnio = @numAnio
          AND e.numMes  = @numMes
          AND e.flgEstado = 1
          AND e.flgActivoCostoLabor = 1
          AND NOT EXISTS (SELECT 1 FROM #inactivos i WHERE i.codProyecto = e.codProyecto)
          AND @ideEmpleadoJefe IS NULL

        UNION ALL

        SELECT pp.codProyecto, pp.nomProyecto, 2
        FROM registro.TMD_PERIODO_PROYECTO pp
        JOIN visibles v ON v.ideEmpleado = pp.ideEmpleado
        WHERE pp.numAnio = @numAnio
          AND pp.numMes  = @numMes
          AND pp.flgEstado = 1

        UNION ALL

        SELECT r.codProyecto, r.nomProyecto, 3
        FROM registro.TMD_REGISTRO_HORAMES r
        JOIN visibles v ON v.ideEmpleado = r.ideEmpleado
        WHERE r.numAnio = @numAnio
          AND r.numMes  = @numMes
          AND r.flgEstado = 1
    ),
    unicos AS (
        SELECT codProyecto, nomProyecto,
               ROW_NUMBER() OVER (PARTITION BY codProyecto ORDER BY numPrioridad) AS numOrden
        FROM columnas
    )
    SELECT codProyecto, nomProyecto
    FROM unicos
    WHERE numOrden = 1
    ORDER BY codProyecto;
END
GO

/* -------------------------------------------------------------------------
   8. Proyectos de la Distribucion GIP

   Reemplaza al del script 36. Sin los inactivos de SPRING, salvo que ya
   tengan distribucion en el anio.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_ListarProyectos
    @numAnio int
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #inactivos (codProyecto varchar(30) NOT NULL PRIMARY KEY);
    INSERT INTO #inactivos (codProyecto) EXEC proceso.usp_ProyectoSpringInactivo_Listar;

    -- Un inactivo sigue saliendo si ya tiene distribucion en el anio, para poder editarla.
    WITH activos AS (
        SELECT e.codProyecto,
               e.nomProyecto,
               ROW_NUMBER() OVER (PARTITION BY e.codProyecto ORDER BY e.numMes DESC) AS numOrden
        FROM proceso.TMD_ESTADO_PROYECTO e
        WHERE e.numAnio = @numAnio
          AND e.flgEstado = 1
          AND e.flgActivoCostoLabor = 1
          AND (NOT EXISTS (SELECT 1 FROM #inactivos i WHERE i.codProyecto = e.codProyecto)
               OR EXISTS (SELECT 1 FROM registro.TMD_DISTRIBUCION_GIP g
                          WHERE g.numAnio = @numAnio AND g.codProyecto = e.codProyecto AND g.flgEstado = 1))
    )
    SELECT codProyecto, nomProyecto
    FROM activos
    WHERE numOrden = 1
    ORDER BY nomProyecto, codProyecto;
END
GO

/* -------------------------------------------------------------------------
   9. Agregar un proyecto excluido

   Reemplaza al del script 50. Solo cambia el mensaje: el maestro ya no
   trae los inactivos.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoExcluido_Agregar
    @numAnio     int,
    @numMes      int,
    @codProyecto varchar(30),
    @txtMotivo   varchar(500) = NULL,
    @txtUsuario  varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50130, 'El periodo esta cerrado: sus proyectos excluidos no se pueden modificar.', 1;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50131, 'El proyecto no existe en SPRING (BD_SPRING no esta disponible).', 1;

    SET @codProyecto = TRIM(@codProyecto);

    CREATE TABLE #spring (codProyecto varchar(30) NOT NULL PRIMARY KEY, nomProyecto varchar(200) NOT NULL);
    INSERT INTO #spring (codProyecto, nomProyecto) EXEC proceso.usp_ProyectoSpring_Listar;

    DECLARE @nomProyecto varchar(200) =
        (SELECT nomProyecto FROM #spring WHERE codProyecto = @codProyecto AND LEN(codProyecto) <= 12);
    IF @nomProyecto IS NULL
        THROW 50131, 'El codigo de proyecto no existe en SPRING o no esta activo (estado A).', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMD_PROYECTO_EXCLUIDO
               WHERE numAnio = @numAnio AND numMes = @numMes AND codProyecto = @codProyecto AND flgEstado = 1)
        THROW 50132, 'El proyecto ya esta excluido en el periodo.', 1;

    INSERT INTO proceso.TMD_PROYECTO_EXCLUIDO
           (numAnio, numMes, codProyecto, nomProyecto, txtMotivo, flgEstado, txtUsuarioCreacion)
    VALUES (@numAnio, @numMes, @codProyecto, @nomProyecto, NULLIF(TRIM(@txtMotivo), ''), 1, @txtUsuario);

    SELECT CAST(SCOPE_IDENTITY() AS bigint) AS ideProyectoExcluido;
END
GO

/* -------------------------------------------------------------------------
   10. Rentabilidad: registrar o editar un proyecto

   Reemplaza al del script 45. Solo cambia el mensaje.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_Rentabilidad_Guardar
    @ideRentabilidadProyecto bigint = NULL,
    @numAnio                 int,
    @numMes                  int,
    @codProyecto             varchar(30),
    @numMontoTotal           decimal(14,2),
    @numMontoRentabilidad    decimal(14,2),
    @txtUsuario              varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ideRentabilidadProyecto IS NOT NULL
    BEGIN
        SELECT @numAnio = numAnio, @numMes = numMes
        FROM proceso.TMD_RENTABILIDAD_PROYECTO
        WHERE ideRentabilidadProyecto = @ideRentabilidadProyecto AND flgEstado = 1;

        IF @@ROWCOUNT = 0
            THROW 50118, 'El registro de rentabilidad no existe.', 1;
    END

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50114, 'El periodo esta cerrado: su rentabilidad no se puede modificar.', 1;

    IF @numMontoTotal IS NULL OR @numMontoRentabilidad IS NULL
       OR @numMontoTotal < 0 OR @numMontoRentabilidad < 0 OR @numMontoRentabilidad > @numMontoTotal
        THROW 50117, 'Ingrese el monto total y el de rentabilidad, mayores o iguales a cero; la rentabilidad no puede superar al total.', 1;

    CREATE TABLE #spring (codProyecto varchar(30) NOT NULL PRIMARY KEY, nomProyecto varchar(200) NOT NULL);
    INSERT INTO #spring (codProyecto, nomProyecto) EXEC proceso.usp_ProyectoSpring_Listar;

    DECLARE @nomProyecto varchar(200) = (SELECT nomProyecto FROM #spring WHERE codProyecto = TRIM(@codProyecto));
    IF @nomProyecto IS NULL
        THROW 50115, 'El codigo de proyecto no existe en SPRING o no esta activo (estado A).', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMD_RENTABILIDAD_PROYECTO
               WHERE numAnio = @numAnio AND numMes = @numMes AND codProyecto = TRIM(@codProyecto)
                 AND flgEstado = 1
                 AND ideRentabilidadProyecto <> ISNULL(@ideRentabilidadProyecto, 0))
        THROW 50116, 'El proyecto ya tiene rentabilidad registrada en el periodo.', 1;

    IF @ideRentabilidadProyecto IS NULL
    BEGIN
        INSERT INTO proceso.TMD_RENTABILIDAD_PROYECTO
               (numAnio, numMes, codProyecto, nomProyecto, numMontoTotal, numMontoRentabilidad,
                flgEstado, txtUsuarioCreacion)
        VALUES (@numAnio, @numMes, TRIM(@codProyecto), @nomProyecto, @numMontoTotal, @numMontoRentabilidad,
                1, @txtUsuario);
        SET @ideRentabilidadProyecto = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE proceso.TMD_RENTABILIDAD_PROYECTO
        SET codProyecto = TRIM(@codProyecto),
            nomProyecto = @nomProyecto,
            numMontoTotal = @numMontoTotal,
            numMontoRentabilidad = @numMontoRentabilidad,
            fecActualizacion = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideRentabilidadProyecto = @ideRentabilidadProyecto;

    SELECT @ideRentabilidadProyecto AS ideRentabilidadProyecto;
END
GO

/* -------------------------------------------------------------------------
   11. Rentabilidad: carga de la plantilla

   Reemplaza a la del script 45. Solo cambia el mensaje.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_Rentabilidad_Cargar
    @numAnio    int,
    @numMes     int,
    @filas      proceso.TYPE_RENTABILIDAD_FILA READONLY,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50114, 'El periodo esta cerrado: su rentabilidad no se puede modificar.', 1;

    CREATE TABLE #spring (codProyecto varchar(30) NOT NULL PRIMARY KEY, nomProyecto varchar(200) NOT NULL);
    INSERT INTO #spring (codProyecto, nomProyecto) EXEC proceso.usp_ProyectoSpring_Listar;

    SELECT e.numFila, e.txtError
    INTO #errores
    FROM (
        SELECT f.numFila, CAST('El codigo de proyecto ' + TRIM(f.codProyecto) + ' no existe en SPRING o no esta activo (estado A).' AS varchar(300)) AS txtError
        FROM @filas f
        WHERE NOT EXISTS (SELECT 1 FROM #spring s WHERE s.codProyecto = TRIM(f.codProyecto))
        UNION ALL
        SELECT f.numFila, CAST('El proyecto ' + TRIM(f.codProyecto) + ' esta repetido en el archivo.' AS varchar(300))
        FROM @filas f
        WHERE EXISTS (SELECT 1 FROM @filas o
                      WHERE TRIM(o.codProyecto) = TRIM(f.codProyecto) AND o.numFila < f.numFila)
    ) e;

    IF NOT EXISTS (SELECT 1 FROM #errores)
    BEGIN
        BEGIN TRANSACTION;

        UPDATE proceso.TMD_RENTABILIDAD_PROYECTO
        SET flgEstado = 0,
            fecActualizacion = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1;

        INSERT INTO proceso.TMD_RENTABILIDAD_PROYECTO
               (numAnio, numMes, codProyecto, nomProyecto, numMontoTotal, numMontoRentabilidad,
                flgEstado, txtUsuarioCreacion)
        SELECT @numAnio, @numMes, s.codProyecto, s.nomProyecto, f.numMontoTotal, f.numMontoRentabilidad,
               1, @txtUsuario
        FROM @filas f
        INNER JOIN #spring s ON s.codProyecto = TRIM(f.codProyecto);

        COMMIT TRANSACTION;
    END

    SELECT numFila, txtError FROM #errores ORDER BY numFila, txtError;
END
GO

/* -------------------------------------------------------------------------
   12. Tipo de gasto: alta y edicion

   Reemplaza a la del script 51. Rechaza los proyectos inactivos de SPRING
   que el tipo no tenia.
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

        -- Solo proyectos activos (estado A); los que el tipo ya tenia se conservan.
        DECLARE @inactivos TABLE (codProyecto varchar(30) PRIMARY KEY);
        INSERT INTO @inactivos (codProyecto) EXEC proceso.usp_ProyectoSpringInactivo_Listar;

        DECLARE @proyectoInactivo varchar(30) =
            (SELECT TOP (1) l.codProyecto FROM @listaProyectos l
             JOIN @inactivos i ON i.codProyecto = l.codProyecto
             WHERE NOT EXISTS (SELECT 1 FROM proceso.TMD_TIPO_GASTO_PROYECTO p
                               WHERE p.ideTipoGasto = @ideTipoGasto AND p.codProyecto = l.codProyecto
                                 AND p.flgEstado = 1));
        IF @proyectoInactivo IS NOT NULL
        BEGIN
            DECLARE @msgInactivo varchar(200) = CONCAT('El proyecto ', @proyectoInactivo, ' no esta activo en SPRING (estado A).');
            THROW 50135, @msgInactivo, 1;
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

/* -------------------------------------------------------------------------
   13. Datos ya cargados: baja logica de los inactivos en periodos no cerrados

   Un periodo que aun no existe en registro.TMC_PERIODO cuenta como no
   cerrado, igual que en la replica.
   ------------------------------------------------------------------------- */

IF DB_ID('BD_SPRING') IS NULL
    PRINT 'BD_SPRING no esta disponible: no se revisan los proyectos ya cargados.';
ELSE
BEGIN
    CREATE TABLE #inactivos (codProyecto varchar(30) NOT NULL PRIMARY KEY);
    INSERT INTO #inactivos (codProyecto) EXEC proceso.usp_ProyectoSpringInactivo_Listar;

    UPDATE e
    SET flgEstado = 0,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = 'SYSTEM_COSTOLABOR'
    FROM proceso.TMD_ESTADO_PROYECTO e
    JOIN #inactivos i ON i.codProyecto = e.codProyecto
    WHERE e.flgEstado = 1
      AND NOT EXISTS (SELECT 1 FROM registro.TMC_PERIODO p
                      WHERE p.numAnio = e.numAnio AND p.numMes = e.numMes AND p.flgEstado = 2);

    PRINT CONCAT('Proyectos inactivos dados de baja en periodos no cerrados: ', @@ROWCOUNT);

    DROP TABLE #inactivos;
END
GO
