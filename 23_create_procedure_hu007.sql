/* =========================================================================
   HU-007 - Registro de distribucion de costos por proyecto - GIP

   Opera sobre registro.TMD_DISTRIBUCION_GIP (cabecera: un proyecto por anio)
   y registro.TMD_DISTRIBUCION_GIP_DETALLE (actividades con el porcentaje de
   cada trimestre), que ya crea 01_create_table.sql. Aqui solo se agregan las
   restricciones que exige el CA-04 y los procedimientos.

   Los totales no se guardan: el I TRIM a IV TRIM del listado (CA-01) y la
   fila Total del formulario (CA-03) son sumas del detalle vigente. Guardarlos
   en la cabecera obligaria a mantener dos copias del mismo dato de acuerdo.

   Codigos de error de negocio (continuan la numeracion de la HU-006):
     50030  el proyecto ya tiene una distribucion vigente en el anio
     50031  la distribucion no existe o fue eliminada
     50032  la distribucion no trae actividades
     50033  una actividad vacia o un porcentaje fuera de 0.00 a 100.00

   PROPUESTA, requiere visto bueno del lider tecnico: el CA-02 pide los
   "proyectos asignados a la GIP", pero el modelo no marca a que gerencia
   pertenece un proyecto. Se toman los asignados en el anio a trabajadores del
   departamento DIP (Direccion de Inversion Privada), la misma sigla que usa la
   HU-006 en registro.TMD_PERIODO_EMPLEADO. En el sistema real ambos datos
   llegan del ERP SPRING.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* Obligatorio: los indices filtrados rechazan cualquier DML y cualquier
   procedimiento compilado sin estas opciones. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* -------------------------------------------------------------------------
   1. Restricciones del CA-04
   ------------------------------------------------------------------------- */

-- Un mismo proyecto no puede registrarse dos veces en el mismo anio. Es
-- filtrado para que una distribucion dada de baja no bloquee registrarla de
-- nuevo; cubre ademas la carrera que la validacion previa no alcanza.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_TMD_DISTRIBUCION_GIP_ANIO_PROYECTO'
                 AND object_id = OBJECT_ID('registro.TMD_DISTRIBUCION_GIP'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_DISTRIBUCION_GIP_ANIO_PROYECTO
        ON registro.TMD_DISTRIBUCION_GIP (numAnio ASC, codProyecto ASC)
        WHERE flgEstado = 1;
GO

-- Porcentaje valido por trimestre, de 0.00 a 100.00
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = 'CK_TMD_DISTRIBUCION_GIP_DETALLE_PORCENTAJE')
    ALTER TABLE registro.TMD_DISTRIBUCION_GIP_DETALLE
        ADD CONSTRAINT CK_TMD_DISTRIBUCION_GIP_DETALLE_PORCENTAJE
        CHECK (primerTrimestre  BETWEEN 0 AND 100
           AND segundoTrimestre BETWEEN 0 AND 100
           AND tercerTrimestre  BETWEEN 0 AND 100
           AND cuartoTrimestre  BETWEEN 0 AND 100);
GO

-- Listado del anio (CA-01)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_DISTRIBUCION_GIP_ANIO'
                 AND object_id = OBJECT_ID('registro.TMD_DISTRIBUCION_GIP'))
    CREATE NONCLUSTERED INDEX IX_TMD_DISTRIBUCION_GIP_ANIO
        ON registro.TMD_DISTRIBUCION_GIP (numAnio ASC, flgEstado ASC)
        INCLUDE (codProyecto, nomProyecto);
GO

-- Actividades de una distribucion, para el formulario y las sumas del listado
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_DISTRIBUCION_GIP_DETALLE_CABECERA'
                 AND object_id = OBJECT_ID('registro.TMD_DISTRIBUCION_GIP_DETALLE'))
    CREATE NONCLUSTERED INDEX IX_TMD_DISTRIBUCION_GIP_DETALLE_CABECERA
        ON registro.TMD_DISTRIBUCION_GIP_DETALLE (ideDistribucionGip ASC, flgEstado ASC)
        INCLUDE (primerTrimestre, segundoTrimestre, tercerTrimestre, cuartoTrimestre);
GO

/* -------------------------------------------------------------------------
   2. Tipo tabla para enviar las actividades del formulario en una sola llamada
   ------------------------------------------------------------------------- */

IF TYPE_ID('registro.TYPE_DISTRIBUCION_GIP_DETALLE') IS NULL
    CREATE TYPE registro.TYPE_DISTRIBUCION_GIP_DETALLE AS TABLE (
        numLinea         int          NOT NULL,   -- orden en que se muestran en la grilla
        txtActividad     varchar(500) NULL,
        primerTrimestre  decimal(5,2) NOT NULL,
        segundoTrimestre decimal(5,2) NOT NULL,
        tercerTrimestre  decimal(5,2) NOT NULL,
        cuartoTrimestre  decimal(5,2) NOT NULL
    );
GO

/* -------------------------------------------------------------------------
   3. Listado paginado del anio (CA-01)

   Cada trimestre es la suma de las actividades vigentes del proyecto; una
   distribucion sin actividades muestra 0.00 en lugar de NULL.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_Listar
    @numAnio          int,
    @numPagina        int = 1,
    @numTamanioPagina int = 10
AS
BEGIN
    SET NOCOUNT ON;

    -- Mismo criterio que la HU-004: paginas de 10 y 20 elementos
    IF @numTamanioPagina NOT IN (10, 20) SET @numTamanioPagina = 10;
    IF @numPagina IS NULL OR @numPagina < 1 SET @numPagina = 1;

    SELECT  g.ideDistribucionGip,
            g.numAnio,
            g.codProyecto,
            g.nomProyecto,
            ISNULL(d.primerTrimestre,  0) AS primerTrimestre,
            ISNULL(d.segundoTrimestre, 0) AS segundoTrimestre,
            ISNULL(d.tercerTrimestre,  0) AS tercerTrimestre,
            ISNULL(d.cuartoTrimestre,  0) AS cuartoTrimestre,
            COUNT(*) OVER () AS numTotalRegistros
    FROM registro.TMD_DISTRIBUCION_GIP g
    OUTER APPLY (
        SELECT  SUM(x.primerTrimestre)  AS primerTrimestre,
                SUM(x.segundoTrimestre) AS segundoTrimestre,
                SUM(x.tercerTrimestre)  AS tercerTrimestre,
                SUM(x.cuartoTrimestre)  AS cuartoTrimestre
        FROM registro.TMD_DISTRIBUCION_GIP_DETALLE x
        WHERE x.ideDistribucionGip = g.ideDistribucionGip
          AND x.flgEstado = 1
    ) d
    WHERE g.numAnio = @numAnio
      AND g.flgEstado = 1
    ORDER BY g.nomProyecto, g.codProyecto
    OFFSET (@numPagina - 1) * @numTamanioPagina ROWS
    FETCH NEXT @numTamanioPagina ROWS ONLY;
END
GO

/* -------------------------------------------------------------------------
   4. Proyectos de la GIP para el combo del formulario (CA-02)

   Un proyecto aparece en tantas filas como meses y trabajadores lo tengan
   asignado; se agrupa por codigo. El nombre se toma del registro mas reciente
   por si el ERP lo corrigio a mitad de anio.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_ListarProyectos
    @numAnio int
AS
BEGIN
    SET NOCOUNT ON;

    WITH asignados AS (
        SELECT  pp.codProyecto,
                pp.nomProyecto,
                ROW_NUMBER() OVER (PARTITION BY pp.codProyecto
                                   ORDER BY pp.numMes DESC, pp.idePeriodoProyecto DESC) AS numOrden
        FROM registro.TMD_PERIODO_PROYECTO pp
        INNER JOIN registro.TMD_PERIODO_EMPLEADO pe
                ON pe.ideEmpleado = pp.ideEmpleado
               AND pe.numAnio     = pp.numAnio
               AND pe.numMes      = pp.numMes
               AND pe.flgEstado   = 1
        WHERE pp.numAnio = @numAnio
          AND pp.flgEstado = 1
          AND pe.codDepartamento = 'DIP'
    )
    SELECT  codProyecto,
            nomProyecto
    FROM asignados
    WHERE numOrden = 1
    ORDER BY nomProyecto, codProyecto;
END
GO

/* -------------------------------------------------------------------------
   5. Lectura de una distribucion para el formulario de edicion (CA-02)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_Obtener
    @ideDistribucionGip bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ideDistribucionGip,
            numAnio,
            codProyecto,
            nomProyecto
    FROM registro.TMD_DISTRIBUCION_GIP
    WHERE ideDistribucionGip = @ideDistribucionGip
      AND flgEstado = 1;
END
GO

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGipDetalle_Listar
    @ideDistribucionGip bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ideDistribucionGipDetalle,
            txtActividad,
            primerTrimestre,
            segundoTrimestre,
            tercerTrimestre,
            cuartoTrimestre
    FROM registro.TMD_DISTRIBUCION_GIP_DETALLE
    WHERE ideDistribucionGip = @ideDistribucionGip
      AND flgEstado = 1
    ORDER BY ideDistribucionGipDetalle;
END
GO

/* -------------------------------------------------------------------------
   6. Unicidad del proyecto en el anio (CA-04)

   El caso de uso la consulta antes de guardar para responder con un mensaje
   claro; los THROW de registrar y actualizar quedan como red de seguridad.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_ExisteProyecto
    @numAnio            int,
    @codProyecto        varchar(30),
    @ideDistribucionGip bigint = NULL   -- en edicion, la propia distribucion no cuenta
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CASE WHEN EXISTS (
        SELECT 1 FROM registro.TMD_DISTRIBUCION_GIP
        WHERE numAnio = @numAnio
          AND codProyecto = @codProyecto
          AND flgEstado = 1
          AND (@ideDistribucionGip IS NULL OR ideDistribucionGip <> @ideDistribucionGip)
    ) THEN 1 ELSE 0 END AS flgExiste;
END
GO

/* -------------------------------------------------------------------------
   7. Alta (CA-04)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_Registrar
    @numAnio            int,
    @codProyecto        varchar(30),
    @nomProyecto        varchar(200),
    @txtUsuario         varchar(30),
    @actividades        registro.TYPE_DISTRIBUCION_GIP_DETALLE READONLY,
    @ideDistribucionGip bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM registro.TMD_DISTRIBUCION_GIP
               WHERE numAnio = @numAnio AND codProyecto = @codProyecto AND flgEstado = 1)
        THROW 50030, 'El proyecto ya tiene una distribucion registrada para el anio indicado.', 1;

    IF NOT EXISTS (SELECT 1 FROM @actividades)
        THROW 50032, 'Debe registrar al menos una actividad.', 1;

    IF EXISTS (SELECT 1 FROM @actividades
               WHERE NULLIF(LTRIM(RTRIM(txtActividad)), '') IS NULL
                  OR primerTrimestre  NOT BETWEEN 0 AND 100
                  OR segundoTrimestre NOT BETWEEN 0 AND 100
                  OR tercerTrimestre  NOT BETWEEN 0 AND 100
                  OR cuartoTrimestre  NOT BETWEEN 0 AND 100)
        THROW 50033, 'Hay actividades sin descripcion o con porcentajes fuera de 0.00 a 100.00.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO registro.TMD_DISTRIBUCION_GIP
              (numAnio, codProyecto, nomProyecto, flgEstado, fecCreacion, txtUsuarioCreacion)
        VALUES (@numAnio, @codProyecto, @nomProyecto, 1, GETDATE(), @txtUsuario);

        SET @ideDistribucionGip = SCOPE_IDENTITY();

        INSERT INTO registro.TMD_DISTRIBUCION_GIP_DETALLE
              (ideDistribucionGip, txtActividad, primerTrimestre, segundoTrimestre,
               tercerTrimestre, cuartoTrimestre, flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @ideDistribucionGip, LTRIM(RTRIM(txtActividad)), primerTrimestre, segundoTrimestre,
               tercerTrimestre, cuartoTrimestre, 1, GETDATE(), @txtUsuario
        FROM @actividades
        ORDER BY numLinea;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   8. Edicion (CA-04)

   Las actividades se reemplazan por completo: las previas quedan con baja
   logica, igual que los atributos de la HU-004, para conservar el rastro de
   lo que habia antes del cambio.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_Actualizar
    @ideDistribucionGip bigint,
    @numAnio            int,
    @codProyecto        varchar(30),
    @nomProyecto        varchar(200),
    @txtUsuario         varchar(30),
    @actividades        registro.TYPE_DISTRIBUCION_GIP_DETALLE READONLY
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM registro.TMD_DISTRIBUCION_GIP
                   WHERE ideDistribucionGip = @ideDistribucionGip AND flgEstado = 1)
        THROW 50031, 'La distribucion indicada no existe o fue eliminada.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMD_DISTRIBUCION_GIP
               WHERE numAnio = @numAnio AND codProyecto = @codProyecto AND flgEstado = 1
                 AND ideDistribucionGip <> @ideDistribucionGip)
        THROW 50030, 'El proyecto ya tiene una distribucion registrada para el anio indicado.', 1;

    IF NOT EXISTS (SELECT 1 FROM @actividades)
        THROW 50032, 'Debe registrar al menos una actividad.', 1;

    IF EXISTS (SELECT 1 FROM @actividades
               WHERE NULLIF(LTRIM(RTRIM(txtActividad)), '') IS NULL
                  OR primerTrimestre  NOT BETWEEN 0 AND 100
                  OR segundoTrimestre NOT BETWEEN 0 AND 100
                  OR tercerTrimestre  NOT BETWEEN 0 AND 100
                  OR cuartoTrimestre  NOT BETWEEN 0 AND 100)
        THROW 50033, 'Hay actividades sin descripcion o con porcentajes fuera de 0.00 a 100.00.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE registro.TMD_DISTRIBUCION_GIP
        SET numAnio                 = @numAnio,
            codProyecto             = @codProyecto,
            nomProyecto             = @nomProyecto,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideDistribucionGip = @ideDistribucionGip;

        UPDATE registro.TMD_DISTRIBUCION_GIP_DETALLE
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideDistribucionGip = @ideDistribucionGip
          AND flgEstado = 1;

        INSERT INTO registro.TMD_DISTRIBUCION_GIP_DETALLE
              (ideDistribucionGip, txtActividad, primerTrimestre, segundoTrimestre,
               tercerTrimestre, cuartoTrimestre, flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @ideDistribucionGip, LTRIM(RTRIM(txtActividad)), primerTrimestre, segundoTrimestre,
               tercerTrimestre, cuartoTrimestre, 1, GETDATE(), @txtUsuario
        FROM @actividades
        ORDER BY numLinea;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   9. Baja logica (CA-05): flgEstado = 0 en la cabecera y sus actividades
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_DistribucionGip_EliminarLogico
    @ideDistribucionGip bigint,
    @txtUsuario         varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM registro.TMD_DISTRIBUCION_GIP
                   WHERE ideDistribucionGip = @ideDistribucionGip AND flgEstado = 1)
        THROW 50031, 'La distribucion indicada no existe o ya fue eliminada.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE registro.TMD_DISTRIBUCION_GIP
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideDistribucionGip = @ideDistribucionGip;

        UPDATE registro.TMD_DISTRIBUCION_GIP_DETALLE
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideDistribucionGip = @ideDistribucionGip
          AND flgEstado = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
