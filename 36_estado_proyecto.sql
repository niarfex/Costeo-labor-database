/* =========================================================================
   36 - Actualizacion de estado de proyectos

   El perfil Contador indica por periodo que proyectos estan activos para
   Costo Labor. El listado se arma con "Replicar del periodo anterior":

     - Sin ningun periodo registrado antes, se copian todos los proyectos de
       BD_SPRING (afemst) con la consulta indicada por el lider.
     - Con un periodo anterior registrado (el mas reciente, no necesariamente
       el mes previo), se copia su listado con el estado que tenia, y se
       agregan los proyectos de SPRING que aun no figuraban.

   Los proyectos nuevos quedan sin estado hasta que el Contador lo indique.
   Replicar sobre un periodo que ya tiene proyectos solo agrega los que faltan:
   no pisa lo ya indicado.

   Desde este script, los proyectos activos del periodo son los que se
   ofrecen en el registro de horas por dia (y por tanto las columnas de horas
   por mes) y los que se distribuyen en la Distribucion GIP, en lugar de
   leerlos de SPRING o de los asignados a DIP.

   El estado se guarda por anio y mes y no por idePeriodo: el periodo puede no
   existir todavia, porque lo crea el primer procesamiento.

   Errores nuevos:
     50080  el periodo esta cerrado
     50081  BD_SPRING no esta disponible y no hay periodo anterior que copiar
     50082  el proyecto no existe en el periodo
     50083  el proyecto no esta activo para Costo Labor en el periodo
   Se reutiliza 50060 en el alta de proyectos del trabajador, con el nuevo
   motivo (el proyecto no esta activo en el periodo).

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Tabla
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMD_ESTADO_PROYECTO') IS NULL
BEGIN
    -- Los datos de SPRING se copian al replicar: el listado de un periodo
    -- cerrado debe seguir mostrando lo que se vio entonces.
    CREATE TABLE proceso.TMD_ESTADO_PROYECTO(
        ideEstadoProyecto bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        codProyecto varchar(30) NOT NULL,
        nomProyecto varchar(200) NOT NULL,
        fecAprobadoSpring datetime NULL,
        fecInicioSpring datetime NULL,
        fecFinSpring datetime NULL,
        txtEstadoSpring varchar(10) NULL,
        -- NULL: el Contador aun no lo indica. 1: activo. 0: no activo.
        flgActivoCostoLabor bit NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_ESTADO_PROYECTO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_ESTADO_PROYECTO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_ESTADO_PROYECTO PRIMARY KEY CLUSTERED (ideEstadoProyecto ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_ESTADO_PROYECTO_PERIODO
        ON proceso.TMD_ESTADO_PROYECTO (numAnio, numMes, codProyecto) WHERE flgEstado = 1;
END
GO

/* -------------------------------------------------------------------------
   2. Listado del periodo

   Primero un resumen (periodo cerrado, total y sin estado) y luego los
   proyectos, en dos conjuntos de resultados.
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

    SELECT e.ideEstadoProyecto, e.codProyecto, e.nomProyecto,
           e.fecAprobadoSpring, e.fecInicioSpring, e.fecFinSpring, e.txtEstadoSpring,
           e.flgActivoCostoLabor
    FROM proceso.TMD_ESTADO_PROYECTO e
    WHERE e.numAnio = @numAnio AND e.numMes = @numMes AND e.flgEstado = 1
    ORDER BY e.nomProyecto, e.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   3. Replicar del periodo anterior

   Devuelve de donde copio (anio y mes de origen, nulos si fue de SPRING) y
   cuantos proyectos agrego de cada fuente.
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

    -- Consulta del lider. Si SPRING tuviera dos filas con el mismo codigo,
    -- se queda con una para no romper la clave.
    IF @haySpring = 1
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
            ) a
            WHERE numOrden = 1;';

    DECLARE @numCopiados int = 0, @numNuevos int = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Del periodo anterior, con el estado que tenia. Las fechas y el estado
        -- de SPRING se toman al dia si el proyecto sigue en SPRING.
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
              AND NOT EXISTS (SELECT 1 FROM proceso.TMD_ESTADO_PROYECTO d
                              WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                                AND d.codProyecto = o.codProyecto AND d.flgEstado = 1);

            SET @numCopiados = @@ROWCOUNT;
        END

        -- Los de SPRING que aun no figuran: sin estado, para que el Contador lo indique.
        INSERT INTO proceso.TMD_ESTADO_PROYECTO
              (numAnio, numMes, codProyecto, nomProyecto, fecAprobadoSpring, fecInicioSpring,
               fecFinSpring, txtEstadoSpring, flgActivoCostoLabor, flgEstado, txtUsuarioCreacion)
        SELECT @numAnio, @numMes, s.codProyecto, s.nomProyecto, s.fecAprobadoSpring, s.fecInicioSpring,
               s.fecFinSpring, s.txtEstadoSpring, NULL, 1, @txtUsuario
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
   4. Indicar si un proyecto esta activo para Costo Labor

   Se guarda en cada cambio, sin confirmacion. Un solo valor: si o no.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_EstadoProyecto_Actualizar
    @ideEstadoProyecto   bigint,
    @flgActivoCostoLabor bit,
    @txtUsuario          varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @numAnio int, @numMes int;

    SELECT @numAnio = numAnio, @numMes = numMes
    FROM proceso.TMD_ESTADO_PROYECTO
    WHERE ideEstadoProyecto = @ideEstadoProyecto AND flgEstado = 1;

    IF @numAnio IS NULL
        THROW 50082, 'El proyecto indicado no existe en el periodo.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50080, 'El periodo esta cerrado: el estado de sus proyectos no se puede modificar.', 1;

    IF @flgActivoCostoLabor IS NULL
        THROW 50082, 'Indique si el proyecto esta activo o no para Costo Labor.', 1;

    UPDATE proceso.TMD_ESTADO_PROYECTO
    SET flgActivoCostoLabor = @flgActivoCostoLabor,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE ideEstadoProyecto = @ideEstadoProyecto;
END
GO

/* -------------------------------------------------------------------------
   5. Catalogo del registro de horas: los proyectos activos del periodo

   Reemplaza al del script 35, que leia todo afemst. Las columnas de horas
   por mes salen de los proyectos que el trabajador agrega aqui, asi que
   tambien quedan limitadas a los activos.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Proyecto_ListarCatalogo
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.codProyecto, e.nomProyecto
    FROM proceso.TMD_ESTADO_PROYECTO e
    WHERE e.numAnio = @numAnio AND e.numMes = @numMes
      AND e.flgEstado = 1 AND e.flgActivoCostoLabor = 1
    ORDER BY e.nomProyecto, e.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   6. Agregar un proyecto al periodo del trabajador

   Igual que el script 35, salvo que el proyecto debe estar activo para Costo
   Labor en el periodo, y su nombre se toma de ese listado y no de afemst.
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
   7. Proyectos de la Distribucion GIP

   La distribucion es anual: se ofrecen los proyectos activos para Costo
   Labor en al menos un mes del anio, con el nombre del mes mas reciente.
   Reemplaza al del script 23, que tomaba los asignados a trabajadores de DIP.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_ListarProyectos
    @numAnio int
AS
BEGIN
    SET NOCOUNT ON;

    WITH activos AS (
        SELECT e.codProyecto,
               e.nomProyecto,
               ROW_NUMBER() OVER (PARTITION BY e.codProyecto ORDER BY e.numMes DESC) AS numOrden
        FROM proceso.TMD_ESTADO_PROYECTO e
        WHERE e.numAnio = @numAnio
          AND e.flgEstado = 1
          AND e.flgActivoCostoLabor = 1
    )
    SELECT codProyecto, nomProyecto
    FROM activos
    WHERE numOrden = 1
    ORDER BY nomProyecto, codProyecto;
END
GO

/* -------------------------------------------------------------------------
   8. Opcion de menu, solo para el perfil Contador

   Igual que el script 33: idempotente y sin filtrar por flgEstado, para no
   devolver la opcion a un perfil al que el administrador se la quito.
   ------------------------------------------------------------------------- */

SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'ESTADO_PROYECTOS', 'Actualización de estado de proyectos', '/costo-labor/estado-proyectos',
       'bi bi-toggles', p.ideOpcion, 6, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'ESTADO_PROYECTOS');
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'COSTO_LABOR'), ('CONTADOR', 'ESTADO_PROYECTOS')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
