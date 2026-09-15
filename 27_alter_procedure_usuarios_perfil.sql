/* =========================================================================
   27 - HU-003 CA-05: listado de usuarios por perfil desde BD_SPRING

   usp_UsuarioSpring_Buscar      busca usuarios activos de BD_SPRING por
                                 nombres, apellidos o documento de identidad.
   usp_PerfilUsuario_Listar      agrega el documento de identidad de cada
                                 usuario asignado, leido de BD_SPRING por su
                                 correo, para la tabla del CA-05.

   Si BD_SPRING no existe en el servidor, la busqueda devuelve vacio y el
   listado sale sin documento, como antes.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* -------------------------------------------------------------------------
   Busqueda en el directorio de BD_SPRING
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_UsuarioSpring_Buscar
    @txtCriterio varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL OR LEN(LTRIM(RTRIM(ISNULL(@txtCriterio, '')))) = 0
    BEGIN
        SELECT CAST(NULL AS varchar(20)) AS Documento, CAST(NULL AS varchar(120)) AS NombreCompleto,
               CAST(NULL AS varchar(50)) AS CorreoElectronico
        WHERE 1 = 0;
        RETURN;
    END

    -- Un mismo correo puede estar en mas de un usuario; basta con uno activo.
    EXEC sp_executesql N'
        SELECT TOP (50) Documento, NombreCompleto, CorreoElectronico
        FROM (
            SELECT RTRIM(pm.Documento) AS Documento,
                   RTRIM(pm.NombreCompleto) AS NombreCompleto,
                   LOWER(RTRIM(pm.CorreoElectronico)) AS CorreoElectronico,
                   ROW_NUMBER() OVER (PARTITION BY LOWER(RTRIM(pm.CorreoElectronico))
                                      ORDER BY pm.Persona) AS numOrden
            FROM BD_SPRING.dbo.Usuario u
            INNER JOIN BD_SPRING.dbo.PersonaMast pm ON RTRIM(u.Usuario) = RTRIM(pm.CodigoUsuario)
            WHERE RTRIM(u.Estado) = ''A''
              AND pm.CorreoElectronico LIKE ''%@%''
              AND (pm.NombreCompleto LIKE ''%'' + @criterio + ''%''
                   OR pm.Nombres LIKE ''%'' + @criterio + ''%''
                   OR pm.ApellidoPaterno LIKE ''%'' + @criterio + ''%''
                   OR pm.ApellidoMaterno LIKE ''%'' + @criterio + ''%''
                   OR pm.Documento LIKE @criterio + ''%''
                   OR pm.DocumentoIdentidad LIKE @criterio + ''%'')
        ) x
        WHERE numOrden = 1
        ORDER BY NombreCompleto;',
        N'@criterio varchar(100)', @criterio = @txtCriterio;
END
GO

/* -------------------------------------------------------------------------
   Usuarios asignados a un perfil, con su documento de identidad
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_PerfilUsuario_Listar
    @idePerfil bigint
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT  idePerfilUsuario, txtUsuario, txtObjectId, txtNombreCompleto,
                CAST(NULL AS varchar(20)) AS txtDocumento
        FROM seguridad.TMD_PERFIL_USUARIO
        WHERE idePerfil = @idePerfil
          AND flgEstado = 1
        ORDER BY txtUsuario;
        RETURN;
    END

    EXEC sp_executesql N'
        SELECT  pu.idePerfilUsuario, pu.txtUsuario, pu.txtObjectId,
                ISNULL(pu.txtNombreCompleto, s.NombreCompleto) AS txtNombreCompleto,
                s.Documento AS txtDocumento
        FROM seguridad.TMD_PERFIL_USUARIO pu
        OUTER APPLY (
            SELECT TOP (1) RTRIM(pm.Documento) AS Documento, RTRIM(pm.NombreCompleto) AS NombreCompleto
            FROM BD_SPRING.dbo.PersonaMast pm
            INNER JOIN BD_SPRING.dbo.Usuario u ON RTRIM(u.Usuario) = RTRIM(pm.CodigoUsuario)
            WHERE LOWER(RTRIM(pm.CorreoElectronico)) = LOWER(pu.txtUsuario)
            ORDER BY CASE WHEN RTRIM(u.Estado) = ''A'' THEN 0 ELSE 1 END, pm.Persona
        ) s
        WHERE pu.idePerfil = @idePerfil
          AND pu.flgEstado = 1
        ORDER BY pu.txtUsuario;',
        N'@idePerfil bigint', @idePerfil = @idePerfil;
END
GO
