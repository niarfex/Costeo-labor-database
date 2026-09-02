/* =========================================================================
   HU-006 - Procedimientos del registro de horas por mes

   Codigos de error de negocio (continuan la numeracion de la HU-005):
     50020  el periodo no existe o esta cerrado
     50021  el periodo es posterior al mes en curso
     50022  el registro ya fue validado por la jefatura y esta bloqueado
     50023  el registro solicitado no existe
     50024  el trabajador no tiene una observacion pendiente de subsanar
     50025  falta el comentario obligatorio al observar un registro
     50026  nadie da conformidad a sus propias horas
     50027  el trabajador ya registra por dia en el mes (HU-005)

   Decision de diseno sobre la validacion:
   la jefatura valida el MES completo de un trabajador (CA-05: el modal lista
   el desglose de horas por proyecto), pero TMD_REGISTRO_HORAMES_VALIDACION
   cuelga de un registro por proyecto. Por eso validar un mes inserta una fila
   de validacion por cada proyecto con horas, y el estado que pinta la columna
   Validacion de la grilla se calcula agregando esas filas. Es el mismo
   criterio que aplica la HU-005 sobre el dia.

   numHoras lo reclaman dos historias:
   el CA-04 de la HU-006 dice que TMD_REGISTRO_HORAMES.numHoras se consolida
   desde HORAMES_ACT / HORAMES_ACTTAREA; el CA-04 de la HU-005 dice que se
   recalcula desde las horas diarias. Es la misma fila y el indice
   UX_TMD_REGISTRO_HORAMES_PERIODO garantiza que solo exista una.

   Criterio confirmado por el lider: la modalidad se fija por TRABAJADOR y MES,
   no por proyecto. Si el trabajador ya tiene horas diarias en cualquier
   proyecto del mes, la captura mensual se rechaza con 50027 para todos.

   PENDIENTE: falta la guarda simetrica en usp_RegistroHoraMes_Consolidar
   (HU-005), que hoy sobrescribe numHoras aunque la celda tenga detalle
   mensual, dejando cabecera y detalle en desacuerdo.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* Obligatorio: las tablas con indices filtrados rechazan cualquier DML y
   cualquier procedimiento compilado sin estas opciones. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* -------------------------------------------------------------------------
   Tipos tabla para enviar el detalle del modal en una sola llamada
   ------------------------------------------------------------------------- */

IF TYPE_ID('registro.TYPE_REGISTRO_HORAMES_ACT') IS NULL
    CREATE TYPE registro.TYPE_REGISTRO_HORAMES_ACT AS TABLE (
        numLinea         int           NOT NULL,   -- correlativo dentro del envio
        txtActividad     varchar(500)  NULL,
        txtComentarios   varchar(250)  NULL,
        txtObservaciones varchar(250)  NULL,
        numHoras         decimal(5,2)  NOT NULL,
        txtJsonAtributos nvarchar(max) NULL
    );
GO

IF TYPE_ID('registro.TYPE_REGISTRO_HORAMES_ACTTAREA') IS NULL
    CREATE TYPE registro.TYPE_REGISTRO_HORAMES_ACTTAREA AS TABLE (
        numLineaAct      int           NOT NULL,   -- apunta a numLinea del tipo anterior
        txtTarea         varchar(500)  NULL,
        txtObservaciones varchar(250)  NULL,
        numHoras         decimal(5,2)  NOT NULL,
        txtJsonAtributos nvarchar(max) NULL
    );
GO

/* -------------------------------------------------------------------------
   Estado de revision del mes de cada trabajador (columna Validacion, CA-05)

   PENDIENTE  hay horas y ninguna validacion todavia (icono de ojo)
   CONFORME   todos los proyectos con horas fueron aprobados (icono de check)
   OBSERVADO  hay al menos una observacion sin subsanar (icono de equis)
   SUBSANADO  el trabajador respondio y falta revalidar (icono de admiracion)
   ------------------------------------------------------------------------- */

CREATE OR ALTER VIEW registro.VW_REGISTRO_HORAMES_ESTADO
AS
WITH ultima AS (
    SELECT  v.ideRegistroHorames,
            v.flgConforme,
            v.flgSubsanado,
            ROW_NUMBER() OVER (PARTITION BY v.ideRegistroHorames
                               ORDER BY v.ideRegistroHoramesValidacion DESC) AS numOrden
    FROM registro.TMD_REGISTRO_HORAMES_VALIDACION v
)
SELECT  r.ideEmpleado,
        r.numAnio,
        r.numMes,
        CASE
            WHEN MAX(CASE WHEN u.flgConforme = 0 AND ISNULL(u.flgSubsanado, 0) = 0 THEN 1 ELSE 0 END) = 1
                THEN 'OBSERVADO'
            WHEN MAX(CASE WHEN u.flgConforme = 0 AND u.flgSubsanado = 1 THEN 1 ELSE 0 END) = 1
                THEN 'SUBSANADO'
            WHEN MIN(CASE WHEN u.flgConforme = 1 THEN 1 ELSE 0 END) = 1
                THEN 'CONFORME'
            ELSE 'PENDIENTE'
        END AS codEstadoValidacion
FROM registro.TMD_REGISTRO_HORAMES r
LEFT JOIN ultima u ON u.ideRegistroHorames = r.ideRegistroHorames AND u.numOrden = 1
WHERE r.flgEstado = 1
GROUP BY r.ideEmpleado, r.numAnio, r.numMes;
GO

/* -------------------------------------------------------------------------
   Filas de la grilla: trabajadores a cargo del usuario en sesion (CA-02)

   @ideEmpleadoJefe nulo devuelve todos los trabajadores del periodo, que es
   lo que necesita el administrador. Mientras el ERP no cargue la jerarquia,
   las filas sin jefe asignado quedan fuera de la vista de una jefatura.
   ------------------------------------------------------------------------- */

/* -------------------------------------------------------------------------
   Atributos dinamicos configurados para el periodo (CA-03)

   usp_ParametroAtributo_Listar de la HU-004 resuelve por ideParametro; el
   modal solo conoce el anio y el mes, y pedir primero la parametrizacion para
   despues los atributos serian dos viajes por cada apertura del modal.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Parametro_ListarAtributosPorPeriodo
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  a.ideParametroAtributo,
            a.nomAtributo,
            a.ideTipoDato,
            t.codTipoDato,
            t.nomTipodato AS nomTipoDato,
            a.numTamanio
    FROM registro.TMD_PARAMETRO_ATRIBUTO a
    INNER JOIN registro.TMC_PARAMETRO p ON p.ideParametro = a.ideParametro
    INNER JOIN registro.TG_TIPO_DATO   t ON t.ideTipoDato = a.ideTipoDato
    WHERE p.numAnio = @numAnio
      AND p.numMes  = @numMes
      AND p.flgEstado = 1
      AND a.flgEstado = 1
    ORDER BY a.ideParametroAtributo;
END
GO

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarTrabajadores
    @numAnio         int,
    @numMes          int,
    @ideEmpleadoJefe bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  pe.ideEmpleado,
            pe.nomEmpleado,
            pe.codDepartamento,
            pe.nomDepartamento,
            pe.codNivel,
            pe.txtObservaciones,
            e.codEstadoValidacion
    FROM registro.TMD_PERIODO_EMPLEADO pe
    LEFT JOIN registro.VW_REGISTRO_HORAMES_ESTADO e
           ON e.ideEmpleado = pe.ideEmpleado
          AND e.numAnio = pe.numAnio
          AND e.numMes  = pe.numMes
    WHERE pe.numAnio = @numAnio
      AND pe.numMes  = @numMes
      AND pe.flgEstado = 1
      -- La jefatura tambien se ve a si misma: el prototipo la muestra como
      -- primera fila de su departamento, aunque no dependa de nadie.
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
    ORDER BY pe.codDepartamento,
             CASE pe.codNivel WHEN 'JEFE' THEN 1 WHEN 'ADMINISTRATIVO' THEN 2 ELSE 3 END,
             pe.nomEmpleado;
END
GO

/* -------------------------------------------------------------------------
   Columnas de la grilla: proyectos activos del periodo (CA-02)

   Se toman los proyectos de los trabajadores visibles, no todos los del
   periodo: una jefatura no necesita columnas donde su equipo nunca carga.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarProyectos
    @numAnio         int,
    @numMes          int,
    @ideEmpleadoJefe bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
           pp.codProyecto,
           pp.nomProyecto
    FROM registro.TMD_PERIODO_PROYECTO pp
    JOIN registro.TMD_PERIODO_EMPLEADO pe
      ON pe.ideEmpleado = pp.ideEmpleado
     AND pe.numAnio = pp.numAnio
     AND pe.numMes  = pp.numMes
     AND pe.flgEstado = 1
    WHERE pp.numAnio = @numAnio
      AND pp.numMes  = @numMes
      AND pp.flgEstado = 1
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
    ORDER BY pp.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   Celdas de la grilla: horas de cada cruce Trabajador x Proyecto (CA-02)

   Devuelve solo los cruces con horas. El backend arma la matriz y pone 0 en
   los vacios, porque la cantidad de columnas depende del periodo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarHoras
    @numAnio         int,
    @numMes          int,
    @ideEmpleadoJefe bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  r.ideRegistroHorames,
            r.ideEmpleado,
            r.codProyecto,
            r.numHoras
    FROM registro.TMD_REGISTRO_HORAMES r
    JOIN registro.TMD_PERIODO_EMPLEADO pe
      ON pe.ideEmpleado = r.ideEmpleado
     AND pe.numAnio = r.numAnio
     AND pe.numMes  = r.numMes
     AND pe.flgEstado = 1
    WHERE r.numAnio = @numAnio
      AND r.numMes  = @numMes
      AND r.flgEstado = 1
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
    ORDER BY r.ideEmpleado, r.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   Contenido del modal de captura para un trabajador, proyecto y periodo
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ObtenerDetalle
    @ideEmpleado bigint,
    @codProyecto varchar(30),
    @numAnio     int,
    @numMes      int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ideRegistroHorames bigint =
        (SELECT ideRegistroHorames FROM registro.TMD_REGISTRO_HORAMES
         WHERE ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
           AND numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1);

    SELECT  r.ideRegistroHorames,
            r.numHoras,
            r.txtObservaciones,
            r.txtJsonAtributos
    FROM registro.TMD_REGISTRO_HORAMES r
    WHERE r.ideRegistroHorames = @ideRegistroHorames;

    SELECT  a.ideRegistroHoramesAct,
            a.txtActividad,
            a.txtComentarios,
            a.txtObservaciones,
            a.numHoras,
            a.txtJsonAtributos,
            t.ideRegistroHoramesActtarea,
            t.txtTarea,
            t.txtObservaciones AS txtObservacionesTarea,
            t.numHoras         AS numHorasTarea,
            t.txtJsonAtributos AS txtJsonAtributosTarea
    FROM registro.TMD_REGISTRO_HORAMES_ACT a
    LEFT JOIN registro.TMD_REGISTRO_HORAMES_ACTTAREA t
           ON t.ideRegistroHoramesAct = a.ideRegistroHoramesAct AND t.flgEstado = 1
    WHERE a.ideRegistroHorames = @ideRegistroHorames
      AND a.flgEstado = 1
    ORDER BY a.ideRegistroHoramesAct, t.ideRegistroHoramesActtarea;
END
GO

/* -------------------------------------------------------------------------
   Desglose completo del mes de un trabajador (CA-05 y CA-06)

   El modal «Horas registradas» muestra una tabla Actividad / Tarea /
   Observacion / Horas por cada proyecto del trabajador, no solo por uno.
   Se devuelve aplanado y el backend lo agrupa por proyecto.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarDesglose
    @ideEmpleado bigint,
    @numAnio     int,
    @numMes      int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  r.ideRegistroHorames,
            r.codProyecto,
            r.nomProyecto,
            r.numHoras AS numHorasProyecto,
            r.txtObservaciones,
            a.txtActividad,
            t.txtTarea,
            ISNULL(t.txtObservaciones, a.txtObservaciones) AS txtObservacionDetalle,
            ISNULL(t.numHoras, a.numHoras)                 AS numHorasDetalle
    FROM registro.TMD_REGISTRO_HORAMES r
    LEFT JOIN registro.TMD_REGISTRO_HORAMES_ACT a
           ON a.ideRegistroHorames = r.ideRegistroHorames AND a.flgEstado = 1
    LEFT JOIN registro.TMD_REGISTRO_HORAMES_ACTTAREA t
           ON t.ideRegistroHoramesAct = a.ideRegistroHoramesAct AND t.flgEstado = 1
    WHERE r.ideEmpleado = @ideEmpleado
      AND r.numAnio = @numAnio
      AND r.numMes  = @numMes
      AND r.flgEstado = 1
    ORDER BY r.codProyecto, a.ideRegistroHoramesAct, t.ideRegistroHoramesActtarea;
END
GO

/* -------------------------------------------------------------------------
   Guardado del modal (CA-04)

   Cubre las tres variantes del CA-03 segun lo que llegue en los tipos tabla:
     - con tareas       : @tareas trae filas; las horas de la cabecera son la
                          suma de las tareas
     - con actividades  : solo @actividades trae filas; la cabecera suma las
                          actividades
     - variante basica  : ambos vacios; se usa @numHoras y @txtObservaciones

   El detalle anterior se reemplaza por completo con baja logica, con el mismo
   criterio que usa la HU-005 en usp_RegistroHoraDia_Guardar.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_Guardar
    @ideEmpleado      bigint,
    @nomEmpleado      varchar(200),
    @codProyecto      varchar(30),
    @nomProyecto      varchar(200),
    @numAnio          int,
    @numMes           int,
    @numHoras         decimal(5,2) = 0,
    @txtObservaciones varchar(250) = NULL,
    @txtJsonAtributos nvarchar(max) = NULL,
    @txtUsuario       varchar(100),
    @actividades      registro.TYPE_REGISTRO_HORAMES_ACT      READONLY,
    @tareas           registro.TYPE_REGISTRO_HORAMES_ACTTAREA READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo bigint,
            @flgPeriodo int;

    SELECT @idePeriodo = idePeriodo, @flgPeriodo = flgEstado
    FROM registro.TMC_PERIODO
    WHERE numAnio = @numAnio AND numMes = @numMes;

    -- CA-01: solo se registra sobre un periodo activo
    IF @idePeriodo IS NULL OR @flgPeriodo <> 1
        THROW 50020, 'El periodo no existe o se encuentra cerrado.', 1;

    -- CA-01: no se registra en periodos posteriores al mes en curso
    IF DATEFROMPARTS(@numAnio, @numMes, 1) > DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
        THROW 50021, 'No se pueden registrar horas en un periodo futuro.', 1;

    -- CA-05: una vez que la jefatura da conformidad, el mes queda bloqueado
    IF EXISTS (SELECT 1
               FROM registro.VW_REGISTRO_HORAMES_ESTADO
               WHERE ideEmpleado = @ideEmpleado AND numAnio = @numAnio AND numMes = @numMes
                 AND codEstadoValidacion = 'CONFORME')
        THROW 50022, 'El registro ya fue validado por la jefatura y no admite cambios.', 1;

    -- Un trabajador que ya registra por dia en el mes pertenece a la HU-005: su
    -- usp_RegistroHoraMes_Consolidar recalcula numHoras desde las horas diarias
    -- y pisaria lo que se guarde aqui. La modalidad se fija por trabajador y
    -- mes, no por proyecto: basta un dia cargado en cualquiera de ellos.
    IF EXISTS (SELECT 1 FROM registro.TMD_REGISTRO_HORADIA
               WHERE ideEmpleado = @ideEmpleado
                 AND numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1)
        THROW 50027, 'El trabajador ya registra sus horas por dia en este mes; se consolidan desde esa pantalla.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ideRegistroHorames bigint =
            (SELECT ideRegistroHorames FROM registro.TMD_REGISTRO_HORAMES
             WHERE ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
               AND numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1);

        -- CA-04: la cabecera guarda el total consolidado del nivel de detalle recibido
        DECLARE @numHorasTotal decimal(5,2) =
            CASE
                WHEN EXISTS (SELECT 1 FROM @tareas)      THEN (SELECT SUM(numHoras) FROM @tareas)
                WHEN EXISTS (SELECT 1 FROM @actividades) THEN (SELECT SUM(numHoras) FROM @actividades)
                ELSE @numHoras
            END;

        IF @ideRegistroHorames IS NULL
        BEGIN
            INSERT INTO registro.TMD_REGISTRO_HORAMES
                  (idePeriodo, numAnio, numMes, numHoras, codProyecto, nomProyecto,
                   ideEmpleado, nomEmpleado, txtObservaciones, txtJsonAtributos,
                   flgEstado, txtUsuarioCreacion)
            VALUES (@idePeriodo, @numAnio, @numMes, @numHorasTotal, @codProyecto, @nomProyecto,
                   @ideEmpleado, @nomEmpleado, @txtObservaciones, @txtJsonAtributos,
                   1, @txtUsuario);

            SET @ideRegistroHorames = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE registro.TMD_REGISTRO_HORAMES
            SET numHoras                = @numHorasTotal,
                txtObservaciones        = @txtObservaciones,
                txtJsonAtributos        = @txtJsonAtributos,
                fecActualizacion        = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideRegistroHorames = @ideRegistroHorames;

            -- El detalle previo se da de baja logica antes de reinsertar
            UPDATE t
            SET t.flgEstado               = 0,
                t.fecActualizacion        = GETDATE(),
                t.txtUsuarioActualizacion = @txtUsuario
            FROM registro.TMD_REGISTRO_HORAMES_ACTTAREA t
            JOIN registro.TMD_REGISTRO_HORAMES_ACT a ON a.ideRegistroHoramesAct = t.ideRegistroHoramesAct
            WHERE a.ideRegistroHorames = @ideRegistroHorames AND t.flgEstado = 1;

            UPDATE registro.TMD_REGISTRO_HORAMES_ACT
            SET flgEstado               = 0,
                fecActualizacion        = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideRegistroHorames = @ideRegistroHorames AND flgEstado = 1;
        END

        -- Actividades: hay que conservar numLinea para poder colgarles las
        -- tareas. Un INSERT ... OUTPUT no puede leer columnas del origen, por
        -- eso se usa MERGE, que si expone la fila de origen en el OUTPUT.
        DECLARE @mapa TABLE (numLinea int PRIMARY KEY, ideRegistroHoramesAct bigint);

        MERGE registro.TMD_REGISTRO_HORAMES_ACT AS destino
        USING @actividades AS origen
           ON 1 = 0   -- nunca coincide: siempre inserta
        WHEN NOT MATCHED THEN
            INSERT (ideRegistroHorames, txtActividad, txtComentarios, txtObservaciones,
                    numHoras, txtJsonAtributos, flgEstado, txtUsuarioCreacion)
            VALUES (@ideRegistroHorames, origen.txtActividad, origen.txtComentarios,
                    origen.txtObservaciones,
                    CASE WHEN EXISTS (SELECT 1 FROM @tareas t WHERE t.numLineaAct = origen.numLinea)
                         THEN (SELECT SUM(t.numHoras) FROM @tareas t WHERE t.numLineaAct = origen.numLinea)
                         ELSE origen.numHoras END,
                    origen.txtJsonAtributos, 1, @txtUsuario)
        OUTPUT origen.numLinea, inserted.ideRegistroHoramesAct
            INTO @mapa (numLinea, ideRegistroHoramesAct);

        INSERT INTO registro.TMD_REGISTRO_HORAMES_ACTTAREA
              (ideRegistroHoramesAct, txtTarea, txtObservaciones, numHoras,
               txtJsonAtributos, flgEstado, txtUsuarioCreacion)
        SELECT m.ideRegistroHoramesAct, t.txtTarea, t.txtObservaciones, t.numHoras,
               t.txtJsonAtributos, 1, @txtUsuario
        FROM @tareas t
        JOIN @mapa m ON m.numLinea = t.numLineaAct;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @ideRegistroHorames AS ideRegistroHorames;
END
GO

/* -------------------------------------------------------------------------
   Validacion del mes por la jefatura (CA-05)

   Inserta una fila de validacion por cada proyecto con horas del trabajador
   en el periodo. Observar exige comentario y nadie valida sus propias horas.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_Validar
    @ideEmpleado   bigint,
    @numAnio       int,
    @numMes        int,
    @flgConforme   int,
    @txtComentario varchar(250) = NULL,
    @txtUsuario    varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF @flgConforme = 0 AND (@txtComentario IS NULL OR LTRIM(RTRIM(@txtComentario)) = '')
        THROW 50025, 'Observar un registro exige ingresar un comentario.', 1;

    IF NOT EXISTS (SELECT 1 FROM registro.TMD_REGISTRO_HORAMES
                   WHERE ideEmpleado = @ideEmpleado AND numAnio = @numAnio
                     AND numMes = @numMes AND flgEstado = 1)
        THROW 50023, 'No existen horas registradas para el periodo indicado.', 1;

    -- Nadie da conformidad a sus propias horas, aunque tenga perfil de jefatura.
    IF @ideEmpleado = (SELECT TOP (1) pu.ideEmpleado
                       FROM seguridad.TMD_PERFIL_USUARIO pu
                       WHERE pu.txtUsuario = @txtUsuario
                         AND pu.ideEmpleado IS NOT NULL
                         AND pu.flgEstado = 1)
        THROW 50026, 'No puede validar sus propias horas registradas.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO registro.TMD_REGISTRO_HORAMES_VALIDACION
              (ideRegistroHorames, flgConforme, flgSubsanado, txtComentario, txtUsuarioCreacion)
        SELECT r.ideRegistroHorames,
               @flgConforme,
               CASE WHEN @flgConforme = 0 THEN 0 ELSE NULL END,
               @txtComentario,
               @txtUsuario
        FROM registro.TMD_REGISTRO_HORAMES r
        WHERE r.ideEmpleado = @ideEmpleado AND r.numAnio = @numAnio
          AND r.numMes = @numMes AND r.flgEstado = 1;

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
   envian por separado con usp_RegistroHoraMes_Guardar.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_Subsanar
    @ideEmpleado  bigint,
    @numAnio      int,
    @numMes       int,
    @txtRespuesta varchar(250),
    @txtUsuario   varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF @txtRespuesta IS NULL OR LTRIM(RTRIM(@txtRespuesta)) = ''
        THROW 50024, 'La respuesta a la observacion es obligatoria.', 1;

    IF NOT EXISTS (SELECT 1 FROM registro.VW_REGISTRO_HORAMES_ESTADO
                   WHERE ideEmpleado = @ideEmpleado AND numAnio = @numAnio
                     AND numMes = @numMes AND codEstadoValidacion = 'OBSERVADO')
        THROW 50024, 'El registro no tiene observaciones pendientes de subsanar.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Se responde la ultima observacion abierta de cada proyecto del mes
        ;WITH abierta AS (
            SELECT  v.ideRegistroHoramesValidacion,
                    ROW_NUMBER() OVER (PARTITION BY v.ideRegistroHorames
                                       ORDER BY v.ideRegistroHoramesValidacion DESC) AS numOrden
            FROM registro.TMD_REGISTRO_HORAMES_VALIDACION v
            JOIN registro.TMD_REGISTRO_HORAMES r ON r.ideRegistroHorames = v.ideRegistroHorames
            WHERE r.ideEmpleado = @ideEmpleado AND r.numAnio = @numAnio
              AND r.numMes = @numMes AND r.flgEstado = 1
              AND v.flgConforme = 0 AND ISNULL(v.flgSubsanado, 0) = 0
        )
        UPDATE v
        SET v.flgSubsanado            = 1,
            v.txtRespuesta            = @txtRespuesta,
            v.fecRespuesta            = GETDATE(),
            v.txtUsuarioRespuesta     = @txtUsuario,
            v.fecActualizacion        = GETDATE(),
            v.txtUsuarioActualizacion = @txtUsuario
        FROM registro.TMD_REGISTRO_HORAMES_VALIDACION v
        JOIN abierta a ON a.ideRegistroHoramesValidacion = v.ideRegistroHoramesValidacion
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
   Historial cronologico de observaciones y respuestas del mes (CA-05)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarHistorial
    @ideEmpleado bigint,
    @numAnio     int,
    @numMes      int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  v.ideRegistroHoramesValidacion,
            r.codProyecto,
            r.nomProyecto,
            v.flgConforme,
            v.flgSubsanado,
            v.txtComentario,
            v.txtUsuarioCreacion AS txtUsuarioObservacion,
            v.fecCreacion        AS fecObservacion,
            v.txtRespuesta,
            v.txtUsuarioRespuesta,
            v.fecRespuesta
    FROM registro.TMD_REGISTRO_HORAMES_VALIDACION v
    JOIN registro.TMD_REGISTRO_HORAMES r ON r.ideRegistroHorames = v.ideRegistroHorames
    WHERE r.ideEmpleado = @ideEmpleado
      AND r.numAnio = @numAnio
      AND r.numMes  = @numMes
      AND r.flgEstado = 1
    ORDER BY v.fecCreacion, v.ideRegistroHoramesValidacion;
END
GO
