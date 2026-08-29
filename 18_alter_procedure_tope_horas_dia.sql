/* =========================================================================
   18 - Tope de 24 horas por dia en el registro (HU-005)

   Se rehace usp_RegistroHoraDia_Guardar agregando el error 50016: la suma de
   horas del dia, contando los demas proyectos ya registrados, no supera 24.
   ========================================================================= */

USE COSTO_LABOR;
GO

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

    -- Un dia no supera las 24 horas sumando todos los proyectos del trabajador.
    DECLARE @numHorasDia decimal(38, 2) =
        CASE
            WHEN EXISTS (SELECT 1 FROM @tareas)      THEN (SELECT SUM(numHoras) FROM @tareas)
            WHEN EXISTS (SELECT 1 FROM @actividades) THEN (SELECT SUM(numHoras) FROM @actividades)
            ELSE @numHoras
        END
        + ISNULL((SELECT SUM(r.numHoras)
                  FROM registro.TMD_REGISTRO_HORADIA r
                  WHERE r.ideEmpleado = @ideEmpleado
                    AND r.fecLabor    = @fecLabor
                    AND r.codProyecto <> @codProyecto
                    AND r.flgEstado   = 1), 0);

    IF @numHorasDia > 24
        THROW 50016, 'Las horas del dia no pueden superar 24 sumando todos los proyectos.', 1;

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
