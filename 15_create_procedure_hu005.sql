/* =========================================================================
   HU-005 - Procedimientos del registro de horas por dia

   Codigos de error de negocio (siguen la numeracion de la HU-004):
     50010  el periodo no existe o esta cerrado
     50011  la fecha es posterior a hoy
     50012  el dia ya fue validado por la jefatura y esta bloqueado
     50013  el registro solicitado no existe
     50014  el dia no tiene una observacion pendiente de subsanar
     50015  falta el comentario obligatorio al observar un registro

   Decision de diseno sobre la validacion:
   la jefatura valida un DIA completo (CA-05: el modal muestra el consolidado
   de proyectos y horas de la fecha), pero TMD_REGISTRO_HORADIA_VALIDACION
   cuelga de un registro por proyecto. Por eso validar un dia inserta una fila
   de validacion por cada proyecto de esa fecha, y el estado que pinta la
   grilla se calcula agregando esas filas.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* Obligatorio: las tablas con indices filtrados rechazan cualquier DML y
   cualquier procedimiento compilado sin estas opciones. SQL Server las
   guarda al crear el objeto, asi que si el despliegue se hace con una
   herramienta que no las active, el procedimiento se crea bien pero
   falla al ejecutarse. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* -------------------------------------------------------------------------
   Tipos tabla para enviar el detalle del modal en una sola llamada
   ------------------------------------------------------------------------- */

IF TYPE_ID('registro.TYPE_REGISTRO_HORADIA_ACT') IS NULL
    CREATE TYPE registro.TYPE_REGISTRO_HORADIA_ACT AS TABLE (
        numLinea         int           NOT NULL,   -- correlativo dentro del envio
        txtActividad     varchar(500)  NULL,
        txtComentarios   varchar(250)  NULL,
        txtObservaciones varchar(250)  NULL,
        numHoras         decimal(5,2)  NOT NULL,
        txtJsonAtributos nvarchar(max) NULL
    );
GO

IF TYPE_ID('registro.TYPE_REGISTRO_HORADIA_ACTTAREA') IS NULL
    CREATE TYPE registro.TYPE_REGISTRO_HORADIA_ACTTAREA AS TABLE (
        numLineaAct      int           NOT NULL,   -- apunta a numLinea del tipo anterior
        txtTarea         varchar(500)  NULL,
        txtObservaciones varchar(250)  NULL,
        numHoras         decimal(5,2)  NOT NULL,
        txtJsonAtributos nvarchar(max) NULL
    );
GO

/* -------------------------------------------------------------------------
   Estado de revision de cada dia (fila Validacion del CA-02)

   Se expone como vista para no repetir la agregacion en los procedimientos
   que la necesitan.

   PENDIENTE  el dia tiene horas y ninguna validacion todavia (icono de ojo)
   CONFORME   todas las lineas del dia fueron aprobadas (icono de check)
   OBSERVADO  hay al menos una observacion sin subsanar (icono de equis)
   SUBSANADO  el trabajador respondio y falta revalidar (icono de admiracion)
   ------------------------------------------------------------------------- */

CREATE OR ALTER VIEW registro.VW_REGISTRO_HORADIA_ESTADO
AS
WITH ultima AS (
    SELECT  v.ideRegistroHoradia,
            v.flgConforme,
            v.flgSubsanado,
            ROW_NUMBER() OVER (PARTITION BY v.ideRegistroHoradia
                               ORDER BY v.ideRegistroHoradiaValidacion DESC) AS numOrden
    FROM registro.TMD_REGISTRO_HORADIA_VALIDACION v
)
SELECT  r.ideEmpleado,
        r.fecLabor,
        CASE
            WHEN MAX(CASE WHEN u.flgConforme = 0 AND ISNULL(u.flgSubsanado, 0) = 0 THEN 1 ELSE 0 END) = 1
                THEN 'OBSERVADO'
            WHEN MAX(CASE WHEN u.flgConforme = 0 AND u.flgSubsanado = 1 THEN 1 ELSE 0 END) = 1
                THEN 'SUBSANADO'
            WHEN MIN(CASE WHEN u.flgConforme = 1 THEN 1 ELSE 0 END) = 1
                THEN 'CONFORME'
            ELSE 'PENDIENTE'
        END AS codEstadoValidacion
FROM registro.TMD_REGISTRO_HORADIA r
LEFT JOIN ultima u ON u.ideRegistroHoradia = r.ideRegistroHoradia AND u.numOrden = 1
WHERE r.flgEstado = 1
GROUP BY r.ideEmpleado, r.fecLabor;
GO

/* -------------------------------------------------------------------------
   Cabecera de la vista: periodo vigente
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Periodo_ObtenerVigente
    @numAnio int = NULL,
    @numMes  int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
           idePeriodo, numAnio, numMes, flgEstado, fecProcesamiento
    FROM registro.TMC_PERIODO
    WHERE (@numAnio IS NULL OR numAnio = @numAnio)
      AND (@numMes  IS NULL OR numMes  = @numMes)
      AND flgEstado IN (1, 2)
    ORDER BY numAnio DESC, numMes DESC;
END
GO

/* -------------------------------------------------------------------------
   Filas de la grilla: proyectos asignados al trabajador en el periodo
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_ListarProyectos
    @numAnio     int,
    @numMes      int,
    @ideEmpleado bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  pp.codProyecto,
            pp.nomProyecto,
            pp.ideEmpleado,
            pp.nomEmpleado
    FROM registro.TMD_PERIODO_PROYECTO pp
    WHERE pp.numAnio = @numAnio
      AND pp.numMes  = @numMes
      AND pp.ideEmpleado = @ideEmpleado
      AND pp.flgEstado = 1
    ORDER BY pp.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   Celdas de la grilla: horas por proyecto y dia, mas el estado del dia

   Devuelve una fila por celda con horas. El backend arma la matriz, porque
   la cantidad de columnas depende de los dias reales del mes (CA-01).
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_ListarHoras
    @numAnio     int,
    @numMes      int,
    @ideEmpleado bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  r.ideRegistroHoradia,
            r.codProyecto,
            r.numDia,
            r.fecLabor,
            r.numHoras,
            e.codEstadoValidacion
    FROM registro.TMD_REGISTRO_HORADIA r
    LEFT JOIN registro.VW_REGISTRO_HORADIA_ESTADO e
           ON e.ideEmpleado = r.ideEmpleado AND e.fecLabor = r.fecLabor
    WHERE r.numAnio = @numAnio
      AND r.numMes  = @numMes
      AND r.ideEmpleado = @ideEmpleado
      AND r.flgEstado = 1
    ORDER BY r.codProyecto, r.numDia;
END
GO

/* -------------------------------------------------------------------------
   Contenido del modal de captura para un proyecto y dia
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_ObtenerDetalle
    @ideEmpleado bigint,
    @codProyecto varchar(30),
    @fecLabor    date
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ideRegistroHoradia bigint =
        (SELECT ideRegistroHoradia FROM registro.TMD_REGISTRO_HORADIA
         WHERE ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
           AND fecLabor = @fecLabor AND flgEstado = 1);

    SELECT  r.ideRegistroHoradia,
            r.numHoras,
            r.txtObservaciones,
            r.txtJsonAtributos
    FROM registro.TMD_REGISTRO_HORADIA r
    WHERE r.ideRegistroHoradia = @ideRegistroHoradia;

    SELECT  a.ideRegistroHoradiaAct,
            a.txtActividad,
            a.txtComentarios,
            a.txtObservaciones,
            a.numHoras,
            a.txtJsonAtributos,
            t.ideRegistroHoradiaActtarea,
            t.txtTarea,
            t.txtObservaciones AS txtObservacionesTarea,
            t.numHoras         AS numHorasTarea,
            t.txtJsonAtributos AS txtJsonAtributosTarea
    FROM registro.TMD_REGISTRO_HORADIA_ACT a
    LEFT JOIN registro.TMD_REGISTRO_HORADIA_ACTTAREA t
           ON t.ideRegistroHoradiaAct = a.ideRegistroHoradiaAct AND t.flgEstado = 1
    WHERE a.ideRegistroHoradia = @ideRegistroHoradia
      AND a.flgEstado = 1
    ORDER BY a.ideRegistroHoradiaAct, t.ideRegistroHoradiaActtarea;
END
GO

/* -------------------------------------------------------------------------
   Recalculo del consolidado mensual (CA-04)

   Se invoca desde el guardado y desde la subsanacion; suma las cabeceras
   diarias vigentes del empleado y proyecto en el periodo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_Consolidar
    @numAnio     int,
    @numMes      int,
    @ideEmpleado bigint,
    @codProyecto varchar(30),
    @txtUsuario  varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo  bigint,
            @nomProyecto varchar(200),
            @nomEmpleado varchar(200),
            @numHoras    decimal(5,2);

    SELECT  @idePeriodo  = MAX(idePeriodo),
            @nomProyecto = MAX(nomProyecto),
            @nomEmpleado = MAX(nomEmpleado),
            @numHoras    = SUM(numHoras)
    FROM registro.TMD_REGISTRO_HORADIA
    WHERE numAnio = @numAnio AND numMes = @numMes
      AND ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
      AND flgEstado = 1;

    SET @numHoras = ISNULL(@numHoras, 0);

    UPDATE registro.TMD_REGISTRO_HORAMES
    SET numHoras                = @numHoras,
        fecActualizacion        = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE numAnio = @numAnio AND numMes = @numMes
      AND ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
      AND flgEstado = 1;

    IF @@ROWCOUNT = 0 AND @numHoras > 0
        INSERT INTO registro.TMD_REGISTRO_HORAMES
              (idePeriodo, numAnio, numMes, numHoras, codProyecto, nomProyecto,
               ideEmpleado, nomEmpleado, flgEstado, txtUsuarioCreacion)
        VALUES (@idePeriodo, @numAnio, @numMes, @numHoras, @codProyecto, @nomProyecto,
               @ideEmpleado, @nomEmpleado, 1, @txtUsuario);
END
GO

/* -------------------------------------------------------------------------
   Guardado del modal (CA-04)

   Cubre las tres variantes del CA-03 segun lo que llegue en los tipos tabla:
     - con tareas       : @atributosTarea trae filas; las horas de la cabecera
                          son la suma de las tareas
     - con actividades  : solo @atributosAct trae filas; la cabecera suma las
                          actividades
     - formulario simple: ambos vacios; se usa @numHoras y @txtObservaciones

   El detalle anterior se reemplaza por completo con baja logica, con el mismo
   criterio que usa usp_Parametro_Actualizar en la HU-004.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_Guardar
    @ideEmpleado      bigint,
    @nomEmpleado      varchar(200),
    @codProyecto      varchar(30),
    @nomProyecto      varchar(200),
    @fecLabor         date,
    @numHoras         decimal(5,2) = 0,
    @txtObservaciones varchar(250) = NULL,
    @txtJsonAtributos nvarchar(max) = NULL,
    @txtUsuario       varchar(30),
    @actividades      registro.TYPE_REGISTRO_HORADIA_ACT      READONLY,
    @tareas           registro.TYPE_REGISTRO_HORADIA_ACTTAREA READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @numAnio int = YEAR(@fecLabor),
            @numMes  int = MONTH(@fecLabor),
            @numDia  int = DAY(@fecLabor);

    DECLARE @idePeriodo bigint,
            @flgPeriodo int;

    SELECT @idePeriodo = idePeriodo, @flgPeriodo = flgEstado
    FROM registro.TMC_PERIODO
    WHERE numAnio = @numAnio AND numMes = @numMes;

    -- CA-01: solo se registra sobre un periodo activo
    IF @idePeriodo IS NULL OR @flgPeriodo <> 1
        THROW 50010, 'El periodo no existe o se encuentra cerrado.', 1;

    -- CA-01: los dias futuros permanecen bloqueados
    IF @fecLabor > CAST(GETDATE() AS DATE)
        THROW 50011, 'No se pueden registrar horas de una fecha futura.', 1;

    -- CA-05: una vez que la jefatura da conformidad, el dia queda bloqueado
    IF EXISTS (SELECT 1
               FROM registro.VW_REGISTRO_HORADIA_ESTADO
               WHERE ideEmpleado = @ideEmpleado AND fecLabor = @fecLabor
                 AND codEstadoValidacion = 'CONFORME')
        THROW 50012, 'El dia ya fue validado por la jefatura y no admite cambios.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ideRegistroHoradia bigint =
            (SELECT ideRegistroHoradia FROM registro.TMD_REGISTRO_HORADIA
             WHERE ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
               AND fecLabor = @fecLabor AND flgEstado = 1);

        -- Total consolidado de la cabecera segun el nivel de detalle recibido
        DECLARE @numHorasTotal decimal(5,2) =
            CASE
                WHEN EXISTS (SELECT 1 FROM @tareas)      THEN (SELECT SUM(numHoras) FROM @tareas)
                WHEN EXISTS (SELECT 1 FROM @actividades) THEN (SELECT SUM(numHoras) FROM @actividades)
                ELSE @numHoras
            END;

        IF @ideRegistroHoradia IS NULL
        BEGIN
            INSERT INTO registro.TMD_REGISTRO_HORADIA
                  (idePeriodo, numAnio, numMes, numDia, codProyecto, nomProyecto,
                   ideEmpleado, nomEmpleado, fecLabor, numHoras, txtObservaciones,
                   txtJsonAtributos, flgEstado, txtUsuarioCreacion)
            VALUES (@idePeriodo, @numAnio, @numMes, @numDia, @codProyecto, @nomProyecto,
                   @ideEmpleado, @nomEmpleado, @fecLabor, @numHorasTotal, @txtObservaciones,
                   @txtJsonAtributos, 1, @txtUsuario);

            SET @ideRegistroHoradia = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE registro.TMD_REGISTRO_HORADIA
            SET numHoras                = @numHorasTotal,
                txtObservaciones        = @txtObservaciones,
                txtJsonAtributos        = @txtJsonAtributos,
                fecActualizacion        = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideRegistroHoradia = @ideRegistroHoradia;

            -- El detalle previo se da de baja logica antes de reinsertar
            UPDATE t
            SET t.flgEstado               = 0,
                t.fecActualizacion        = GETDATE(),
                t.txtUsuarioActualizacion = @txtUsuario
            FROM registro.TMD_REGISTRO_HORADIA_ACTTAREA t
            JOIN registro.TMD_REGISTRO_HORADIA_ACT a ON a.ideRegistroHoradiaAct = t.ideRegistroHoradiaAct
            WHERE a.ideRegistroHoradia = @ideRegistroHoradia AND t.flgEstado = 1;

            UPDATE registro.TMD_REGISTRO_HORADIA_ACT
            SET flgEstado               = 0,
                fecActualizacion        = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideRegistroHoradia = @ideRegistroHoradia AND flgEstado = 1;
        END

        -- Actividades: hay que conservar numLinea para poder colgarles las
        -- tareas. Un INSERT ... OUTPUT no puede leer columnas del origen, por
        -- eso se usa MERGE, que si expone la fila de origen en el OUTPUT.
        DECLARE @mapa TABLE (numLinea int PRIMARY KEY, ideRegistroHoradiaAct bigint);

        MERGE registro.TMD_REGISTRO_HORADIA_ACT AS destino
        USING @actividades AS origen
           ON 1 = 0   -- nunca coincide: siempre inserta
        WHEN NOT MATCHED THEN
            INSERT (ideRegistroHoradia, txtActividad, txtComentarios, txtObservaciones,
                    numHoras, txtJsonAtributos, flgEstado, txtUsuarioCreacion)
            VALUES (@ideRegistroHoradia, origen.txtActividad, origen.txtComentarios,
                    origen.txtObservaciones,
                    CASE WHEN EXISTS (SELECT 1 FROM @tareas t WHERE t.numLineaAct = origen.numLinea)
                         THEN (SELECT SUM(t.numHoras) FROM @tareas t WHERE t.numLineaAct = origen.numLinea)
                         ELSE origen.numHoras END,
                    origen.txtJsonAtributos, 1, @txtUsuario)
        OUTPUT origen.numLinea, inserted.ideRegistroHoradiaAct
            INTO @mapa (numLinea, ideRegistroHoradiaAct);

        INSERT INTO registro.TMD_REGISTRO_HORADIA_ACTTAREA
              (ideRegistroHoradiaAct, txtTarea, txtObservaciones, numHoras,
               txtJsonAtributos, flgEstado, txtUsuarioCreacion)
        SELECT m.ideRegistroHoradiaAct, t.txtTarea, t.txtObservaciones, t.numHoras,
               t.txtJsonAtributos, 1, @txtUsuario
        FROM @tareas t
        JOIN @mapa m ON m.numLinea = t.numLineaAct;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- CA-04: el consolidado mensual se recalcula en cada guardado
    EXEC registro.usp_RegistroHoraMes_Consolidar @numAnio, @numMes, @ideEmpleado, @codProyecto, @txtUsuario;

    SELECT @ideRegistroHoradia AS ideRegistroHoradia;
END
GO

/* -------------------------------------------------------------------------
   Vista de la jefatura: trabajadores a cargo con horas del periodo
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_ListarTrabajadores
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  pe.ideEmpleado,
            pe.nomEmpleado,
            pe.txtObservaciones,
            SUM(ISNULL(r.numHoras, 0)) AS numHorasTotal,
            SUM(CASE WHEN e.codEstadoValidacion = 'PENDIENTE' THEN 1 ELSE 0 END) AS numDiasPendientes
    FROM registro.TMD_PERIODO_EMPLEADO pe
    LEFT JOIN registro.TMD_REGISTRO_HORADIA r
           ON r.ideEmpleado = pe.ideEmpleado AND r.numAnio = pe.numAnio
          AND r.numMes = pe.numMes AND r.flgEstado = 1
    LEFT JOIN registro.VW_REGISTRO_HORADIA_ESTADO e
           ON e.ideEmpleado = r.ideEmpleado AND e.fecLabor = r.fecLabor
    WHERE pe.numAnio = @numAnio
      AND pe.numMes  = @numMes
      AND pe.flgEstado = 1
    GROUP BY pe.ideEmpleado, pe.nomEmpleado, pe.txtObservaciones
    ORDER BY pe.nomEmpleado;
END
GO

/* -------------------------------------------------------------------------
   Validacion de un dia por la jefatura (CA-05)

   Inserta una fila de validacion por cada proyecto registrado esa fecha.
   Observar exige comentario.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_Validar
    @ideEmpleado    bigint,
    @fecLabor       date,
    @flgConforme    int,
    @txtComentario  varchar(250) = NULL,
    @txtUsuario     varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF @flgConforme = 0 AND (@txtComentario IS NULL OR LTRIM(RTRIM(@txtComentario)) = '')
        THROW 50015, 'Observar un registro exige ingresar un comentario.', 1;

    IF NOT EXISTS (SELECT 1 FROM registro.TMD_REGISTRO_HORADIA
                   WHERE ideEmpleado = @ideEmpleado AND fecLabor = @fecLabor AND flgEstado = 1)
        THROW 50013, 'No existen horas registradas para la fecha indicada.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO registro.TMD_REGISTRO_HORADIA_VALIDACION
              (ideRegistroHoradia, flgConforme, flgSubsanado, txtComentario, txtUsuarioCreacion)
        SELECT r.ideRegistroHoradia,
               @flgConforme,
               CASE WHEN @flgConforme = 0 THEN 0 ELSE NULL END,
               @txtComentario,
               @txtUsuario
        FROM registro.TMD_REGISTRO_HORADIA r
        WHERE r.ideEmpleado = @ideEmpleado AND r.fecLabor = @fecLabor AND r.flgEstado = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   Respuesta del trabajador a una observacion (CA-06)

   Solo marca la subsanacion y guarda el descargo. Las horas rectificadas se
   envian por separado con usp_RegistroHoraDia_Guardar, que ya recalcula el
   consolidado mensual.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_Subsanar
    @ideEmpleado   bigint,
    @fecLabor      date,
    @txtRespuesta  varchar(250),
    @txtUsuario    varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF @txtRespuesta IS NULL OR LTRIM(RTRIM(@txtRespuesta)) = ''
        THROW 50014, 'La respuesta a la observacion es obligatoria.', 1;

    IF NOT EXISTS (SELECT 1 FROM registro.VW_REGISTRO_HORADIA_ESTADO
                   WHERE ideEmpleado = @ideEmpleado AND fecLabor = @fecLabor
                     AND codEstadoValidacion = 'OBSERVADO')
        THROW 50014, 'El dia no tiene observaciones pendientes de subsanar.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Se responde la ultima observacion abierta de cada proyecto del dia
        ;WITH abierta AS (
            SELECT  v.ideRegistroHoradiaValidacion,
                    ROW_NUMBER() OVER (PARTITION BY v.ideRegistroHoradia
                                       ORDER BY v.ideRegistroHoradiaValidacion DESC) AS numOrden
            FROM registro.TMD_REGISTRO_HORADIA_VALIDACION v
            JOIN registro.TMD_REGISTRO_HORADIA r ON r.ideRegistroHoradia = v.ideRegistroHoradia
            WHERE r.ideEmpleado = @ideEmpleado AND r.fecLabor = @fecLabor AND r.flgEstado = 1
              AND v.flgConforme = 0 AND ISNULL(v.flgSubsanado, 0) = 0
        )
        UPDATE v
        SET v.flgSubsanado           = 1,
            v.txtRespuesta           = @txtRespuesta,
            v.fecRespuesta           = GETDATE(),
            v.txtUsuarioRespuesta    = @txtUsuario,
            v.fecActualizacion       = GETDATE(),
            v.txtUsuarioActualizacion = @txtUsuario
        FROM registro.TMD_REGISTRO_HORADIA_VALIDACION v
        JOIN abierta a ON a.ideRegistroHoradiaValidacion = v.ideRegistroHoradiaValidacion
        WHERE a.numOrden = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   Historial cronologico de observaciones y respuestas del dia (CA-05)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_ListarHistorial
    @ideEmpleado bigint,
    @fecLabor    date
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  v.ideRegistroHoradiaValidacion,
            r.codProyecto,
            r.nomProyecto,
            v.flgConforme,
            v.flgSubsanado,
            v.txtComentario,
            v.txtUsuarioCreacion  AS txtUsuarioObservacion,
            v.fecCreacion         AS fecObservacion,
            v.txtRespuesta,
            v.txtUsuarioRespuesta,
            v.fecRespuesta
    FROM registro.TMD_REGISTRO_HORADIA_VALIDACION v
    JOIN registro.TMD_REGISTRO_HORADIA r ON r.ideRegistroHoradia = v.ideRegistroHoradia
    WHERE r.ideEmpleado = @ideEmpleado
      AND r.fecLabor = @fecLabor
      AND r.flgEstado = 1
    ORDER BY v.fecCreacion, v.ideRegistroHoradiaValidacion;
END
GO

/* -------------------------------------------------------------------------
   Observacion por periodo del trabajador (CA-01)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_PeriodoEmpleado_GuardarObservacion
    @numAnio          int,
    @numMes           int,
    @ideEmpleado      bigint,
    @txtObservaciones varchar(250),
    @txtUsuario       varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE registro.TMD_PERIODO_EMPLEADO
    SET txtObservaciones        = @txtObservaciones,
        fecActualizacion        = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE numAnio = @numAnio AND numMes = @numMes
      AND ideEmpleado = @ideEmpleado AND flgEstado = 1;

    IF @@ROWCOUNT = 0
        THROW 50013, 'El trabajador no esta asignado al periodo indicado.', 1;
END
GO
