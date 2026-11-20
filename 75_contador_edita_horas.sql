/* =========================================================================
   75 - El Contador ve y edita las horas de todos (TEMPORAL)

   Temporal (pruebas de usuarios, 20/11): los usuarios pidieron que el
   perfil CONTADOR pueda ver y editar las horas registradas de todos los
   trabajadores mientras hacen sus pruebas. No es funcionalidad definitiva:
   ellos decidiran si se mantiene o se quita antes de concluir el servicio.

   La parametrizacion del periodo (HU-004) gana un indicador mas, que solo
   el administrador enciende:

     flgContadorEditaHoras  cuando esta en 1, el CONTADOR registra horas por
                            dia y por mes de cualquier trabajador del
                            periodo. Nulo o 0 (el valor por defecto): el
                            backend rechaza su lectura y su escritura.

   1. registro.TMC_PARAMETRO: columna flgContadorEditaHoras (int NULL).
   2. Los cinco procedimientos de la parametrizacion, desde la version del
      script 64, con la columna nueva. Registrar y Actualizar la reciben al
      final y opcional, como flgHorasSinValidacion (script 62).
   3. Las opciones HORAS_DIA y HORAS_MES en el menu del CONTADOR.

   Para quitarlo (despues de retirar el codigo marcado "Temporal" en el
   backend y el frontend):

     UPDATE po SET flgEstado = 0, fecActualizacion = GETDATE(),
                   txtUsuarioActualizacion = 'SYSTEM_COSTOLABOR'
     FROM seguridad.TMD_PERFIL_OPCION po
     JOIN seguridad.TMC_PERFIL pe ON pe.idePerfil = po.idePerfil
     JOIN seguridad.TG_OPCION  op ON op.ideOpcion = po.ideOpcion
     WHERE pe.codPerfil = 'CONTADOR' AND op.codOpcion IN ('HORAS_DIA', 'HORAS_MES');

     UPDATE registro.TMC_PARAMETRO SET flgContadorEditaHoras = 0;

   La columna y el parametro opcional pueden quedarse: apagados no hacen nada.

   Requiere el script 62.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('registro.TMC_PARAMETRO', 'flgHorasSinValidacion') IS NULL
    THROW 50170, 'Falta flgHorasSinValidacion en registro.TMC_PARAMETRO: ejecute antes el script 62.', 1;
GO

/* -------------------------------------------------------------------------
   1. La columna de la parametrizacion

   int NULL, como los demas indicadores. Las filas que ya existen quedan en
   NULL, que el backend trata como apagado.
   ------------------------------------------------------------------------- */

IF COL_LENGTH('registro.TMC_PARAMETRO', 'flgContadorEditaHoras') IS NULL
    ALTER TABLE registro.TMC_PARAMETRO ADD flgContadorEditaHoras int NULL;
GO

/* -------------------------------------------------------------------------
   2. Listado paginado (version del script 64)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Parametro_Listar
    @numPagina        int = 1,
    @numTamanioPagina int = 10
AS
BEGIN
    SET NOCOUNT ON;

    -- HU-004 admite unicamente paginas de 10 y 20 elementos
    IF @numTamanioPagina NOT IN (10, 20) SET @numTamanioPagina = 10;
    IF @numPagina IS NULL OR @numPagina < 1 SET @numPagina = 1;

    SELECT  p.ideParametro,
            p.numAnio,
            p.numMes,
            p.flgRegActividad,
            p.flgRegTareaxActividad,
            p.flgRegComentarioxActividad,
            p.flgRegObservacionxTarea,
            p.flgRegObservacionxProyecto,
            p.flgRegObservacionxPeriodo,
            p.flgRegOtrosAtributos,
            p.flgHorasSinValidacion,
            p.flgContadorEditaHoras,
            -- Resumen mostrado en la columna "Otros atributos" del listado
            (SELECT STRING_AGG(CONCAT(a.nomAtributo, ': ', t.nomTipodato), '; ')
                        WITHIN GROUP (ORDER BY a.ideParametroAtributo)
               FROM registro.TMD_PARAMETRO_ATRIBUTO a
               INNER JOIN registro.TG_TIPO_DATO t ON t.ideTipoDato = a.ideTipoDato
              WHERE a.ideParametro = p.ideParametro
                AND a.flgEstado = 1) AS txtAtributos,
            COUNT(*) OVER () AS numTotalRegistros
    FROM registro.TMC_PARAMETRO p
    WHERE p.flgEstado = 1
    ORDER BY p.numAnio DESC, p.numMes DESC
    OFFSET (@numPagina - 1) * @numTamanioPagina ROWS
    FETCH NEXT @numTamanioPagina ROWS ONLY;
END
GO

/* -------------------------------------------------------------------------
   3. Obtener por identificador (version del script 64)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Parametro_Obtener
    @ideParametro bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ideParametro,
            numAnio,
            numMes,
            flgRegActividad,
            flgRegTareaxActividad,
            flgRegComentarioxActividad,
            flgRegObservacionxTarea,
            flgRegObservacionxProyecto,
            flgRegObservacionxPeriodo,
            flgRegOtrosAtributos,
            flgHorasSinValidacion,
            flgContadorEditaHoras
    FROM registro.TMC_PARAMETRO
    WHERE ideParametro = @ideParametro
      AND flgEstado = 1;
END
GO

/* -------------------------------------------------------------------------
   4. Obtener por periodo (version del script 64)

   Es la que consulta el backend para saber si el Contador registra en el
   periodo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Parametro_ObtenerPorPeriodo
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
           ideParametro,
           numAnio,
           numMes,
           flgRegActividad,
           flgRegTareaxActividad,
           flgRegComentarioxActividad,
           flgRegObservacionxTarea,
           flgRegObservacionxProyecto,
           flgRegObservacionxPeriodo,
           flgRegOtrosAtributos,
           flgHorasSinValidacion,
           flgContadorEditaHoras
    FROM registro.TMC_PARAMETRO
    WHERE numAnio = @numAnio
      AND numMes  = @numMes
      AND flgEstado = 1;
END
GO

/* -------------------------------------------------------------------------
   5. Alta (version del script 64)

   El indicador nuevo va al final y con valor por defecto para no romper a
   quien llame al procedimiento sin el.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Parametro_Registrar
    @numAnio                    int,
    @numMes                     int,
    @flgRegActividad            int,
    @flgRegTareaxActividad      int,
    @flgRegComentarioxActividad int,
    @flgRegObservacionxTarea    int,
    @flgRegObservacionxProyecto int,
    @flgRegObservacionxPeriodo  int,
    @flgRegOtrosAtributos       int,
    @txtUsuario                 varchar(30),
    @atributos                  registro.TYPE_PARAMETRO_ATRIBUTO READONLY,
    @ideParametro               bigint OUTPUT,
    @flgHorasSinValidacion      int = 0,
    @flgContadorEditaHoras      int = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PARAMETRO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1)
        THROW 50001, 'Ya existe una parametrizacion vigente para el periodo indicado.', 1;

    IF EXISTS (SELECT 1 FROM @atributos GROUP BY nomAtributo HAVING COUNT(*) > 1)
        THROW 50002, 'Existen nombres de atributo duplicados en la parametrizacion.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO registro.TMC_PARAMETRO
              (numAnio, numMes, flgRegActividad, flgRegComentarioxActividad, flgRegTareaxActividad,
               flgRegObservacionxTarea, flgRegObservacionxProyecto, flgRegObservacionxPeriodo,
               flgRegOtrosAtributos, flgHorasSinValidacion, flgContadorEditaHoras,
               flgEstado, fecCreacion, txtUsuarioCreacion)
        VALUES (@numAnio, @numMes, @flgRegActividad, @flgRegComentarioxActividad, @flgRegTareaxActividad,
               @flgRegObservacionxTarea, @flgRegObservacionxProyecto, @flgRegObservacionxPeriodo,
               @flgRegOtrosAtributos, ISNULL(@flgHorasSinValidacion, 0), ISNULL(@flgContadorEditaHoras, 0),
               1, GETDATE(), @txtUsuario);

        SET @ideParametro = SCOPE_IDENTITY();

        INSERT INTO registro.TMD_PARAMETRO_ATRIBUTO
              (ideParametro, nomAtributo, ideTipoDato, numTamanio, flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @ideParametro, nomAtributo, ideTipoDato, numTamanio, 1, GETDATE(), @txtUsuario
        FROM @atributos;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   6. Edicion (version del script 64)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Parametro_Actualizar
    @ideParametro               bigint,
    @numAnio                    int,
    @numMes                     int,
    @flgRegActividad            int,
    @flgRegTareaxActividad      int,
    @flgRegComentarioxActividad int,
    @flgRegObservacionxTarea    int,
    @flgRegObservacionxProyecto int,
    @flgRegObservacionxPeriodo  int,
    @flgRegOtrosAtributos       int,
    @txtUsuario                 varchar(30),
    @atributos                  registro.TYPE_PARAMETRO_ATRIBUTO READONLY,
    @flgHorasSinValidacion      int = 0,
    @flgContadorEditaHoras      int = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM registro.TMC_PARAMETRO
                   WHERE ideParametro = @ideParametro AND flgEstado = 1)
        THROW 50003, 'La parametrizacion indicada no existe o fue eliminada.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PARAMETRO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1
                 AND ideParametro <> @ideParametro)
        THROW 50001, 'Ya existe una parametrizacion vigente para el periodo indicado.', 1;

    IF EXISTS (SELECT 1 FROM @atributos GROUP BY nomAtributo HAVING COUNT(*) > 1)
        THROW 50002, 'Existen nombres de atributo duplicados en la parametrizacion.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE registro.TMC_PARAMETRO
        SET numAnio                    = @numAnio,
            numMes                     = @numMes,
            flgRegActividad            = @flgRegActividad,
            flgRegComentarioxActividad = @flgRegComentarioxActividad,
            flgRegTareaxActividad      = @flgRegTareaxActividad,
            flgRegObservacionxTarea    = @flgRegObservacionxTarea,
            flgRegObservacionxProyecto = @flgRegObservacionxProyecto,
            flgRegObservacionxPeriodo  = @flgRegObservacionxPeriodo,
            flgRegOtrosAtributos       = @flgRegOtrosAtributos,
            flgHorasSinValidacion      = ISNULL(@flgHorasSinValidacion, 0),
            flgContadorEditaHoras      = ISNULL(@flgContadorEditaHoras, 0),
            fecActualizacion           = GETDATE(),
            txtUsuarioActualizacion    = @txtUsuario
        WHERE ideParametro = @ideParametro;

        -- El detalle se reemplaza por completo; las filas previas quedan con baja logica
        UPDATE registro.TMD_PARAMETRO_ATRIBUTO
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideParametro = @ideParametro
          AND flgEstado = 1;

        INSERT INTO registro.TMD_PARAMETRO_ATRIBUTO
              (ideParametro, nomAtributo, ideTipoDato, numTamanio, flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @ideParametro, nomAtributo, ideTipoDato, numTamanio, 1, GETDATE(), @txtUsuario
        FROM @atributos;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   7. Registro de horas por dia y por mes en el menu del Contador

   Igual que los scripts 33, 36, 50 y 59: sin filtrar por flgEstado, para no
   devolver la opcion si el administrador se la quita desde Perfiles.
   ------------------------------------------------------------------------- */

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'COSTO_LABOR'),
             ('CONTADOR', 'HORAS_DIA'),
             ('CONTADOR', 'HORAS_MES')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
