/* =========================================================================
   44 - Perfil por cargo asignado en el primer acceso

   Desde el script 26, un usuario sin perfiles asignados recibe los perfiles
   de su cargo en BD_SPRING (seguridad.TMD_PERFIL_CARGO), pero solo al
   listarlos: no quedaban en seguridad.TMD_PERFIL_USUARIO. Como el menu
   (usp_Opcion_ListarPorUsuario) y el vinculo con el trabajador (ideEmpleado)
   se leen de esa tabla, el usuario veia sus perfiles con el menu vacio hasta
   que el administrador lo agregaba a mano al perfil.

   Ahora, la primera vez que se listan los perfiles de un usuario sin ninguno
   asignado, los de su cargo se graban en seguridad.TMD_PERFIL_USUARIO con su
   vinculo al trabajador. Desde ahi el usuario es uno mas: el administrador
   puede quitarlo o cambiarle los perfiles desde la pantalla de perfiles.

   Las filas creadas asi llevan txtUsuarioCreacion = 'SYSTEM_COSTOLABOR'.

   Si BD_SPRING no existe en el servidor, o el cargo no tiene perfiles, el
   usuario sigue sin perfil, como antes.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Asignar los perfiles del cargo a un usuario sin perfiles

   Mismo criterio que el script 26: usuario de SPRING activo (Estado = A) y
   cargo asociado al perfil. Si el correo esta en mas de una persona, se toma
   la de usuario activo con menor codigo, como usp_Empleado_ObtenerSpringPorCorreo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_PerfilUsuario_AsignarPorCargo
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF DB_ID('BD_SPRING') IS NULL
        RETURN;

    BEGIN TRANSACTION;

    -- Las primeras peticiones de la sesion llegan a la vez: solo una asigna.
    DECLARE @recurso nvarchar(255) = N'PerfilPorCargo:' + LOWER(RTRIM(@txtUsuario));
    EXEC sp_getapplock @Resource = @recurso, @LockMode = 'Exclusive', @LockOwner = 'Transaction';

    IF NOT EXISTS (SELECT 1
                   FROM seguridad.TMD_PERFIL_USUARIO pu
                   INNER JOIN seguridad.TMC_PERFIL p ON p.idePerfil = pu.idePerfil AND p.flgEstado = 1
                   WHERE pu.txtUsuario = @txtUsuario AND pu.flgEstado = 1)
    BEGIN
        EXEC sp_executesql N'
            WITH persona AS (
                SELECT TOP (1) pm.Persona, RTRIM(pm.NombreCompleto) AS NombreCompleto, em.CodigoCargo
                FROM BD_SPRING.dbo.Usuario u
                INNER JOIN BD_SPRING.dbo.PersonaMast pm ON RTRIM(u.Usuario) = RTRIM(pm.CodigoUsuario)
                INNER JOIN BD_SPRING.dbo.EmpleadoMast em ON pm.Persona = em.Empleado
                WHERE LOWER(RTRIM(pm.CorreoElectronico)) = LOWER(RTRIM(@correo))
                  AND RTRIM(u.Estado) = ''A''
                ORDER BY pm.Persona
            )
            INSERT INTO seguridad.TMD_PERFIL_USUARIO
                  (idePerfil, txtUsuario, txtNombreCompleto, ideEmpleado,
                   flgEstado, fecCreacion, txtUsuarioCreacion)
            SELECT DISTINCT p.idePerfil, @correo, LEFT(s.NombreCompleto, 150), CAST(s.Persona AS bigint),
                   1, GETDATE(), ''SYSTEM_COSTOLABOR''
            FROM persona s
            INNER JOIN seguridad.TMD_PERFIL_CARGO pc
                    ON pc.numCodigoCargo = s.CodigoCargo AND pc.flgEstado = 1
            INNER JOIN seguridad.TMC_PERFIL p
                    ON p.idePerfil = pc.idePerfil AND p.flgEstado = 1
            -- Como antes del script, el perfil activo al ingresar es el de menor idePerfil.
            ORDER BY p.idePerfil;',
            N'@correo varchar(100)', @correo = @txtUsuario;
    END

    COMMIT TRANSACTION;
END
GO

/* -------------------------------------------------------------------------
   2. Perfiles del usuario

   Reemplaza al del script 26: en lugar de solo listar los perfiles del cargo,
   primero los asigna. Siempre devuelve los asignados.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_ListarPorUsuario
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1
                   FROM seguridad.TMD_PERFIL_USUARIO pu
                   INNER JOIN seguridad.TMC_PERFIL p ON p.idePerfil = pu.idePerfil AND p.flgEstado = 1
                   WHERE pu.txtUsuario = @txtUsuario AND pu.flgEstado = 1)
        EXEC seguridad.usp_PerfilUsuario_AsignarPorCargo @txtUsuario = @txtUsuario;

    SELECT p.codPerfil,
           p.nomPerfil
    FROM seguridad.TMD_PERFIL_USUARIO pu
    INNER JOIN seguridad.TMC_PERFIL p ON p.idePerfil = pu.idePerfil AND p.flgEstado = 1
    WHERE pu.txtUsuario = @txtUsuario
      AND pu.flgEstado = 1
    -- El primer perfil asignado es el que queda activo al ingresar.
    ORDER BY pu.idePerfilUsuario;
END
GO
