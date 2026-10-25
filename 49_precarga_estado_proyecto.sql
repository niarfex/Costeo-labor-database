/* =========================================================================
   49 - Precarga del estado de proyectos: todos activos en la primera carga

   La primera carga del estado de proyectos (enero 2025, sin un periodo
   anterior que copiar) trae todos los proyectos de SPRING. Desde este script
   quedan con Estado activo = Si; antes quedaban sin estado y el Contador
   debia marcarlos uno a uno. En los periodos siguientes los proyectos nuevos
   de SPRING siguen llegando sin estado.

   Si la primera carga ya se hizo, sus proyectos aun sin estado se marcan
   activos, salvo que el periodo este cerrado. No toca los que el Contador ya
   indico (Si o No).

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Replicar del periodo anterior (igual que el script 36, salvo el estado
      de los proyectos nuevos en la primera carga)
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

    -- Consulta de referencia. Si SPRING tuviera dos filas con el mismo codigo,
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
   2. Primera carga ya hecha: sus proyectos sin estado quedan activos
   ------------------------------------------------------------------------- */

DECLARE @numAnio int, @numMes int;

SELECT TOP (1) @numAnio = numAnio, @numMes = numMes
FROM proceso.TMD_ESTADO_PROYECTO
WHERE flgEstado = 1
ORDER BY numAnio, numMes;

IF @numAnio IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                   WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
    UPDATE proceso.TMD_ESTADO_PROYECTO
    SET flgActivoCostoLabor = 1,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = 'SYSTEM_COSTOLABOR'
    WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1
      AND flgActivoCostoLabor IS NULL;
GO