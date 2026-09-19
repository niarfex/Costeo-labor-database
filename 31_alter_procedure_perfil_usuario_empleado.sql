/* =========================================================================
   31 - Vinculo usuario -> trabajador al asignar perfiles (HU-003 / HU-005)

   usp_PerfilUsuario_Reemplazar reinsertaba a los usuarios sin ideEmpleado:
   el usuario asignado desde la pantalla nunca quedaba vinculado a un
   trabajador, y al volver a guardar un perfil se perdia el vinculo de los
   que ya lo tenian. Ahora se conserva el vinculo existente y, si no hay,
   se toma de BD_SPRING (PersonaMast.Persona del empleado con ese correo).

   Tambien completa el vinculo de las asignaciones activas que no lo tienen.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* Empleado de BD_SPRING por correo; vacio si BD_SPRING no esta disponible. */
CREATE OR ALTER PROCEDURE seguridad.usp_Empleado_ObtenerSpringPorCorreo
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS varchar(100)) AS txtUsuario, CAST(NULL AS bigint) AS ideEmpleado
        WHERE 1 = 0;
        RETURN;
    END

    -- Un correo puede estar en mas de una persona: primero el usuario activo.
    EXEC sp_executesql N'
        SELECT txtUsuario, ideEmpleado
        FROM (
            SELECT LOWER(RTRIM(pm.CorreoElectronico)) AS txtUsuario,
                   CAST(pm.Persona AS bigint) AS ideEmpleado,
                   ROW_NUMBER() OVER (PARTITION BY LOWER(RTRIM(pm.CorreoElectronico))
                                      ORDER BY CASE WHEN RTRIM(u.Estado) = ''A'' THEN 0 ELSE 1 END,
                                               pm.Persona) AS numOrden
            FROM BD_SPRING.dbo.PersonaMast pm
            INNER JOIN BD_SPRING.dbo.EmpleadoMast em ON em.Empleado = pm.Persona
            LEFT JOIN BD_SPRING.dbo.Usuario u ON RTRIM(u.Usuario) = RTRIM(pm.CodigoUsuario)
            WHERE pm.CorreoElectronico LIKE ''%@%''
        ) x
        WHERE numOrden = 1;';
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

    CREATE TABLE #spring (txtUsuario varchar(100) NOT NULL, ideEmpleado bigint NOT NULL);
    INSERT INTO #spring (txtUsuario, ideEmpleado)
    EXEC seguridad.usp_Empleado_ObtenerSpringPorCorreo;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE seguridad.TMD_PERFIL_USUARIO
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE idePerfil = @idePerfil
          AND flgEstado = 1;

        -- El vinculo ya registrado manda sobre el de BD_SPRING.
        INSERT INTO seguridad.TMD_PERFIL_USUARIO
              (idePerfil, txtUsuario, txtObjectId, txtNombreCompleto, ideEmpleado,
               flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @idePerfil, u.txtUsuario, u.txtObjectId, u.txtNombreCompleto,
               COALESCE(previo.ideEmpleado, s.ideEmpleado),
               1, GETDATE(), @txtUsuario
        FROM @usuarios u
        OUTER APPLY (SELECT TOP (1) pu.ideEmpleado
                     FROM seguridad.TMD_PERFIL_USUARIO pu
                     WHERE pu.txtUsuario = u.txtUsuario
                       AND pu.ideEmpleado IS NOT NULL
                     ORDER BY pu.flgEstado DESC, pu.idePerfilUsuario DESC) previo
        LEFT JOIN #spring s ON s.txtUsuario = LOWER(RTRIM(u.txtUsuario));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* Asignaciones activas que quedaron sin vinculo */
CREATE TABLE #spring (txtUsuario varchar(100) NOT NULL, ideEmpleado bigint NOT NULL);
INSERT INTO #spring (txtUsuario, ideEmpleado)
EXEC seguridad.usp_Empleado_ObtenerSpringPorCorreo;

UPDATE pu
SET pu.ideEmpleado = COALESCE(previo.ideEmpleado, s.ideEmpleado)
FROM seguridad.TMD_PERFIL_USUARIO pu
OUTER APPLY (SELECT TOP (1) otro.ideEmpleado
             FROM seguridad.TMD_PERFIL_USUARIO otro
             WHERE otro.txtUsuario = pu.txtUsuario
               AND otro.ideEmpleado IS NOT NULL
             ORDER BY otro.flgEstado DESC, otro.idePerfilUsuario DESC) previo
LEFT JOIN #spring s ON s.txtUsuario = LOWER(RTRIM(pu.txtUsuario))
WHERE pu.flgEstado = 1
  AND pu.ideEmpleado IS NULL
  AND COALESCE(previo.ideEmpleado, s.ideEmpleado) IS NOT NULL;

DROP TABLE #spring;
GO
