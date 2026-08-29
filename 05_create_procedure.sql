/* Procedimientos almacenados de HU-004 - Parametrizacion de campos de registro */
/* Errores de negocio: 50001 periodo duplicado, 50002 atributo duplicado, 50003 no encontrado */

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

-- Tipo tabla usado para enviar el detalle de atributos en una sola llamada
IF TYPE_ID('registro.TYPE_PARAMETRO_ATRIBUTO') IS NULL
    CREATE TYPE registro.TYPE_PARAMETRO_ATRIBUTO AS TABLE (
        nomAtributo varchar(50) NOT NULL,
        ideTipoDato bigint      NOT NULL,
        numTamanio  int         NULL
    );
GO

CREATE OR ALTER PROCEDURE registro.usp_TipoDato_Listar
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ideTipoDato,
            codTipoDato,
            nomTipodato AS nomTipoDato
    FROM registro.TG_TIPO_DATO
    WHERE flgEstado = 1
    ORDER BY ideTipoDato;
END
GO

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
            flgRegOtrosAtributos
    FROM registro.TMC_PARAMETRO
    WHERE ideParametro = @ideParametro
      AND flgEstado = 1;
END
GO

CREATE OR ALTER PROCEDURE registro.usp_ParametroAtributo_Listar
    @ideParametro bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  a.ideParametroAtributo,
            a.ideParametro,
            a.nomAtributo,
            a.ideTipoDato,
            t.codTipoDato,
            t.nomTipodato AS nomTipoDato,
            a.numTamanio
    FROM registro.TMD_PARAMETRO_ATRIBUTO a
    INNER JOIN registro.TG_TIPO_DATO t ON t.ideTipoDato = a.ideTipoDato
    WHERE a.ideParametro = @ideParametro
      AND a.flgEstado = 1
    ORDER BY a.ideParametroAtributo;
END
GO

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
    @ideParametro               bigint OUTPUT
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
               flgRegOtrosAtributos, flgEstado, fecCreacion, txtUsuarioCreacion)
        VALUES (@numAnio, @numMes, @flgRegActividad, @flgRegComentarioxActividad, @flgRegTareaxActividad,
               @flgRegObservacionxTarea, @flgRegObservacionxProyecto, @flgRegObservacionxPeriodo,
               @flgRegOtrosAtributos, 1, GETDATE(), @txtUsuario);

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
    @atributos                  registro.TYPE_PARAMETRO_ATRIBUTO READONLY
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

CREATE OR ALTER PROCEDURE registro.usp_Parametro_EliminarLogico
    @ideParametro bigint,
    @txtUsuario   varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM registro.TMC_PARAMETRO
                   WHERE ideParametro = @ideParametro AND flgEstado = 1)
        THROW 50003, 'La parametrizacion indicada no existe o ya fue eliminada.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE registro.TMC_PARAMETRO
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideParametro = @ideParametro;

        UPDATE registro.TMD_PARAMETRO_ATRIBUTO
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideParametro = @ideParametro
          AND flgEstado = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
