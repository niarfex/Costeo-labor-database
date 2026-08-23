/* ============================================================================
   Procedimientos almacenados de la HU-003 - Tipos de usuario y permisos.
   Incluye tambien el registro de auditoria de la HU-001.

   Errores de negocio, mismos codigos que 05_create_procedure.sql:
     50001 codigo de perfil duplicado
     50002 usuario duplicado dentro del perfil
     50003 perfil no encontrado
   ============================================================================ */

USE [COSTO_LABOR];
GO

/* Los procedimientos se compilan con estas opciones y las conservan al
   ejecutarse. Es obligatorio porque escriben en tablas con indices filtrados. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   Tipos tabla para enviar el detalle en una sola llamada
   --------------------------------------------------------------------------- */
IF TYPE_ID('seguridad.TYPE_PERFIL_OPCION') IS NULL
    CREATE TYPE seguridad.TYPE_PERFIL_OPCION AS TABLE (
        ideOpcion bigint NOT NULL
    );
GO

IF TYPE_ID('seguridad.TYPE_PERFIL_USUARIO') IS NULL
    CREATE TYPE seguridad.TYPE_PERFIL_USUARIO AS TABLE (
        txtUsuario        varchar(100) NOT NULL,
        txtObjectId       varchar(36)  NULL,
        txtNombreCompleto varchar(150) NULL
    );
GO

/* ============================================================================
   HU-001 - Auditoria
   ============================================================================ */
CREATE OR ALTER PROCEDURE general.usp_Auditoria_Registrar
    @txtUsuario          varchar(30),
    @txtOpcion           varchar(50),
    @txtEvento           varchar(100),
    @txtResultado        varchar(10),
    @txtDireccionIp      varchar(25),
    @ideRegistroAsociado bigint = NULL,
    @fecEvento           datetime = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO general.TG_AUDITORIA
          (txtUsuario, txtOpcion, txtEvento, txtResultado, txtDireccionIp,
           ideRegistroAsociado, fecha_evento)
    VALUES (@txtUsuario, @txtOpcion, @txtEvento, @txtResultado, @txtDireccionIp,
           @ideRegistroAsociado, ISNULL(@fecEvento, GETDATE()));
END
GO

/* ============================================================================
   HU-003 - Catalogo de opciones
   ============================================================================ */
CREATE OR ALTER PROCEDURE seguridad.usp_Opcion_Listar
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ideOpcion, codOpcion, nomOpcion, txtRuta, txtIcono,
            ideOpcionPadre, numOrden
    FROM seguridad.TG_OPCION
    WHERE flgEstado = 1
    ORDER BY ideOpcionPadre, numOrden;
END
GO

-- Cuantas de las opciones recibidas existen y estan vigentes
CREATE OR ALTER PROCEDURE seguridad.usp_Opcion_ContarVigentes
    @opciones  seguridad.TYPE_PERFIL_OPCION READONLY,
    @numTotal  int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @numTotal = COUNT(DISTINCT o.ideOpcion)
    FROM seguridad.TG_OPCION o
    INNER JOIN @opciones d ON d.ideOpcion = o.ideOpcion
    WHERE o.flgEstado = 1;
END
GO

-- Opciones habilitadas para una persona, a traves de los perfiles que tenga
CREATE OR ALTER PROCEDURE seguridad.usp_Opcion_ListarPorUsuario
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
            o.ideOpcion, o.codOpcion, o.nomOpcion, o.txtRuta, o.txtIcono,
            o.ideOpcionPadre, o.numOrden
    FROM seguridad.TMD_PERFIL_USUARIO pu
    INNER JOIN seguridad.TMC_PERFIL        p  ON p.idePerfil  = pu.idePerfil AND p.flgEstado  = 1
    INNER JOIN seguridad.TMD_PERFIL_OPCION po ON po.idePerfil = p.idePerfil  AND po.flgEstado = 1
    INNER JOIN seguridad.TG_OPCION         o  ON o.ideOpcion  = po.ideOpcion AND o.flgEstado  = 1
    WHERE pu.txtUsuario = @txtUsuario
      AND pu.flgEstado = 1
    ORDER BY o.ideOpcionPadre, o.numOrden;
END
GO

/* ============================================================================
   HU-003 - Perfiles
   ============================================================================ */
CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_Listar
    @numPagina        int = 1,
    @numTamanioPagina int = 10
AS
BEGIN
    SET NOCOUNT ON;

    -- Mismo criterio que la HU-004: paginas de 10 y 20 elementos
    IF @numTamanioPagina NOT IN (10, 20) SET @numTamanioPagina = 10;
    IF @numPagina IS NULL OR @numPagina < 1 SET @numPagina = 1;

    SELECT  p.idePerfil,
            p.codPerfil,
            p.nomPerfil,
            p.txtDescripcion,
            p.flgEstado,
            (SELECT COUNT(*) FROM seguridad.TMD_PERFIL_OPCION po
              WHERE po.idePerfil = p.idePerfil AND po.flgEstado = 1)  AS numTotalOpciones,
            (SELECT COUNT(*) FROM seguridad.TMD_PERFIL_USUARIO pu
              WHERE pu.idePerfil = p.idePerfil AND pu.flgEstado = 1)  AS numTotalUsuarios,
            COUNT(*) OVER ()                                          AS numTotalRegistros
    FROM seguridad.TMC_PERFIL p
    WHERE p.flgEstado = 1
    ORDER BY p.nomPerfil
    OFFSET (@numPagina - 1) * @numTamanioPagina ROWS
    FETCH NEXT @numTamanioPagina ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_Obtener
    @idePerfil bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  idePerfil, codPerfil, nomPerfil, txtDescripcion, flgEstado
    FROM seguridad.TMC_PERFIL
    WHERE idePerfil = @idePerfil
      AND flgEstado = 1;
END
GO

-- @idePerfilExcluir permite editar un perfil sin que su propio codigo cuente
CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_ExisteCodigo
    @codPerfil        varchar(30),
    @idePerfilExcluir bigint = NULL,
    @flgExiste        int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @flgExiste = CASE WHEN EXISTS (
            SELECT 1 FROM seguridad.TMC_PERFIL
            WHERE codPerfil = @codPerfil
              AND flgEstado = 1
              AND (@idePerfilExcluir IS NULL OR idePerfil <> @idePerfilExcluir)
        ) THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_ListarPorUsuario
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.codPerfil
    FROM seguridad.TMD_PERFIL_USUARIO pu
    INNER JOIN seguridad.TMC_PERFIL p ON p.idePerfil = pu.idePerfil AND p.flgEstado = 1
    WHERE pu.txtUsuario = @txtUsuario
      AND pu.flgEstado = 1;
END
GO

CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_Registrar
    @codPerfil      varchar(30),
    @nomPerfil      varchar(100),
    @txtDescripcion varchar(200) = NULL,
    @txtUsuario     varchar(100),
    @opciones       seguridad.TYPE_PERFIL_OPCION READONLY,
    @idePerfil      bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM seguridad.TMC_PERFIL
               WHERE codPerfil = @codPerfil AND flgEstado = 1)
        THROW 50001, 'Ya existe un perfil vigente con el codigo indicado.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO seguridad.TMC_PERFIL
              (codPerfil, nomPerfil, txtDescripcion, flgEstado, fecCreacion, txtUsuarioCreacion)
        VALUES (@codPerfil, @nomPerfil, @txtDescripcion, 1, GETDATE(), @txtUsuario);

        SET @idePerfil = SCOPE_IDENTITY();

        INSERT INTO seguridad.TMD_PERFIL_OPCION
              (idePerfil, ideOpcion, flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @idePerfil, ideOpcion, 1, GETDATE(), @txtUsuario
        FROM (SELECT DISTINCT ideOpcion FROM @opciones) d;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_Actualizar
    @idePerfil      bigint,
    @codPerfil      varchar(30),
    @nomPerfil      varchar(100),
    @txtDescripcion varchar(200) = NULL,
    @txtUsuario     varchar(100),
    @opciones       seguridad.TYPE_PERFIL_OPCION READONLY
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM seguridad.TMC_PERFIL
                   WHERE idePerfil = @idePerfil AND flgEstado = 1)
        THROW 50003, 'El perfil indicado no existe o fue eliminado.', 1;

    IF EXISTS (SELECT 1 FROM seguridad.TMC_PERFIL
               WHERE codPerfil = @codPerfil AND flgEstado = 1
                 AND idePerfil <> @idePerfil)
        THROW 50001, 'Ya existe otro perfil vigente con el codigo indicado.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE seguridad.TMC_PERFIL
        SET codPerfil               = @codPerfil,
            nomPerfil               = @nomPerfil,
            txtDescripcion          = @txtDescripcion,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE idePerfil = @idePerfil;

        -- El detalle se reemplaza por completo; las filas previas quedan de baja
        UPDATE seguridad.TMD_PERFIL_OPCION
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE idePerfil = @idePerfil
          AND flgEstado = 1;

        INSERT INTO seguridad.TMD_PERFIL_OPCION
              (idePerfil, ideOpcion, flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @idePerfil, ideOpcion, 1, GETDATE(), @txtUsuario
        FROM (SELECT DISTINCT ideOpcion FROM @opciones) d;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_EliminarLogico
    @idePerfil  bigint,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM seguridad.TMC_PERFIL
                   WHERE idePerfil = @idePerfil AND flgEstado = 1)
        THROW 50003, 'El perfil indicado no existe o ya fue eliminado.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE seguridad.TMC_PERFIL
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE idePerfil = @idePerfil;

        UPDATE seguridad.TMD_PERFIL_OPCION
        SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
        WHERE idePerfil = @idePerfil AND flgEstado = 1;

        UPDATE seguridad.TMD_PERFIL_USUARIO
        SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
        WHERE idePerfil = @idePerfil AND flgEstado = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* ============================================================================
   HU-003 - Detalle del perfil
   ============================================================================ */
CREATE OR ALTER PROCEDURE seguridad.usp_PerfilOpcion_Listar
    @idePerfil bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  o.ideOpcion, o.codOpcion, o.nomOpcion, o.txtRuta, o.txtIcono,
            o.ideOpcionPadre, o.numOrden
    FROM seguridad.TMD_PERFIL_OPCION po
    INNER JOIN seguridad.TG_OPCION o ON o.ideOpcion = po.ideOpcion AND o.flgEstado = 1
    WHERE po.idePerfil = @idePerfil
      AND po.flgEstado = 1
    ORDER BY o.ideOpcionPadre, o.numOrden;
END
GO

CREATE OR ALTER PROCEDURE seguridad.usp_PerfilUsuario_Listar
    @idePerfil bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  idePerfilUsuario, txtUsuario, txtObjectId, txtNombreCompleto
    FROM seguridad.TMD_PERFIL_USUARIO
    WHERE idePerfil = @idePerfil
      AND flgEstado = 1
    ORDER BY txtUsuario;
END
GO

CREATE OR ALTER PROCEDURE seguridad.usp_PerfilUsuario_Reemplazar
    @idePerfil  bigint,
    @usuarios   seguridad.TYPE_PERFIL_USUARIO READONLY,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM seguridad.TMC_PERFIL
                   WHERE idePerfil = @idePerfil AND flgEstado = 1)
        THROW 50003, 'El perfil indicado no existe o fue eliminado.', 1;

    IF EXISTS (SELECT 1 FROM @usuarios GROUP BY txtUsuario HAVING COUNT(*) > 1)
        THROW 50002, 'El mismo usuario no puede asignarse dos veces al perfil.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE seguridad.TMD_PERFIL_USUARIO
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE idePerfil = @idePerfil
          AND flgEstado = 1;

        INSERT INTO seguridad.TMD_PERFIL_USUARIO
              (idePerfil, txtUsuario, txtObjectId, txtNombreCompleto,
               flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @idePerfil, txtUsuario, txtObjectId, txtNombreCompleto,
               1, GETDATE(), @txtUsuario
        FROM @usuarios;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
