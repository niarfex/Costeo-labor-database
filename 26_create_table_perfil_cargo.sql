/* =========================================================================
   26 - HU-003 CA-04 y HU-001 CA-01 (documento de historias v6)

   HU-003 CA-04: listado de cargos por perfil
     seguridad.TMD_PERFIL_CARGO      cargos de BD_SPRING asociados a cada perfil.
                                     Un cargo puede tener mas de un perfil (el
                                     Contador tiene dos), pero la misma pareja
                                     cargo-perfil no se repite. Borrado logico.
     usp_Cargo_ListarSpring          catalogo de cargos con area y departamento,
                                     con la consulta de la HU.
     usp_PerfilCargo_Listar
     usp_PerfilCargo_Reemplazar
     Semilla: los 38 pares cargo-perfil de la tabla del documento. En el Word
     los encabezados Area y Departamento estan invertidos; aqui cada valor va
     en su columna segun BD_SPRING (Area = HR_Division, Departamento =
     HR_Departamento).

   HU-001 CA-01: perfil segun el cargo
     usp_Perfil_ListarPorUsuario     sin perfiles asignados, toma los del cargo
                                     de la persona en BD_SPRING, solo si su
                                     usuario esta activo (Estado = A).

     usp_Usuario_ObtenerSpring       datos de la persona en BD_SPRING: estado,
                                     cargo, departamento y area.

   Codigos de error: 50004 cargo repetido dentro del perfil.

   Permisos: los procedimientos leen BD_SPRING con el login de la aplicacion,
   que necesita lectura en esa base (por ejemplo, db_datareader). Cada entorno
   lo otorga con su propio login; no va en este script.

   Si BD_SPRING no existe en el servidor, el catalogo devuelve vacio y los
   usuarios sin perfil asignado siguen sin perfil, como antes.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* -------------------------------------------------------------------------
   Tabla
   ------------------------------------------------------------------------- */

IF OBJECT_ID('seguridad.TMD_PERFIL_CARGO') IS NULL
CREATE TABLE seguridad.TMD_PERFIL_CARGO(
    idePerfilCargo          bigint IDENTITY(1,1) NOT NULL,
    idePerfil               bigint       NOT NULL,
    numCodigoCargo          int          NOT NULL,
    txtCargo                varchar(200) NULL,
    txtArea                 varchar(200) NULL,
    txtDepartamento         varchar(200) NULL,
    flgEstado               int          NOT NULL CONSTRAINT DF_TMD_PERFIL_CARGO_flgEstado DEFAULT (1),
    fecCreacion             datetime     NULL CONSTRAINT DF_TMD_PERFIL_CARGO_fecCreacion DEFAULT (GETDATE()),
    txtUsuarioCreacion      varchar(100) NULL,
    fecActualizacion        datetime     NULL,
    txtUsuarioActualizacion varchar(100) NULL,
    CONSTRAINT PK_TMD_PERFIL_CARGO PRIMARY KEY CLUSTERED (idePerfilCargo ASC),
    CONSTRAINT FK_PERFIL_CARGO_PERFIL FOREIGN KEY (idePerfil) REFERENCES seguridad.TMC_PERFIL (idePerfil)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TMD_PERFIL_CARGO'
                 AND object_id = OBJECT_ID('seguridad.TMD_PERFIL_CARGO'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_PERFIL_CARGO
        ON seguridad.TMD_PERFIL_CARGO (idePerfil ASC, numCodigoCargo ASC)
        WHERE flgEstado = 1;
GO

-- Al ingresar se buscan los perfiles por el cargo de la persona
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_TMD_PERFIL_CARGO_CARGO'
                 AND object_id = OBJECT_ID('seguridad.TMD_PERFIL_CARGO'))
    CREATE NONCLUSTERED INDEX IX_TMD_PERFIL_CARGO_CARGO
        ON seguridad.TMD_PERFIL_CARGO (numCodigoCargo ASC, flgEstado ASC);
GO

IF TYPE_ID('seguridad.TYPE_PERFIL_CARGO') IS NULL
    CREATE TYPE seguridad.TYPE_PERFIL_CARGO AS TABLE (
        numCodigoCargo  int          NOT NULL,
        txtCargo        varchar(200) NULL,
        txtArea         varchar(200) NULL,
        txtDepartamento varchar(200) NULL
    );
GO

/* -------------------------------------------------------------------------
   Catalogo de cargos de BD_SPRING (consulta del CA-04)

   Va en SQL dinamico para que el procedimiento funcione aunque BD_SPRING no
   este en el servidor: en ese caso devuelve el catalogo vacio.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_Cargo_ListarSpring
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS int) AS Codigo, CAST(NULL AS varchar(200)) AS Cargo,
               CAST(NULL AS varchar(200)) AS Departamento, CAST(NULL AS varchar(200)) AS Area
        WHERE 1 = 0;
        RETURN;
    END

    EXEC sp_executesql N'
        SELECT hre.CodigoPuesto AS Codigo,
               RTRIM(hre.Descripcion) AS Cargo,
               RTRIM(hrdep.Descripcion) AS Departamento,
               RTRIM(hrdiv.DescripcionLarga) AS Area
        FROM BD_SPRING.dbo.HR_PuestoEmpresa hre
        LEFT JOIN BD_SPRING.dbo.HR_Departamento hrdep ON hre.DepartamentoOperacional = hrdep.Departamento
        LEFT JOIN BD_SPRING.dbo.HR_Division hrdiv ON hre.Division = hrdiv.Division
        ORDER BY hre.Descripcion;';
END
GO

/* -------------------------------------------------------------------------
   Cargos de un perfil
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_PerfilCargo_Listar
    @idePerfil bigint
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  idePerfilCargo, numCodigoCargo, txtCargo, txtArea, txtDepartamento
    FROM seguridad.TMD_PERFIL_CARGO
    WHERE idePerfil = @idePerfil
      AND flgEstado = 1
    ORDER BY txtCargo, numCodigoCargo;
END
GO

/* -------------------------------------------------------------------------
   Reemplazo de los cargos de un perfil (CA-04)

   Solo da de baja logica los que se quitaron y agrega los nuevos: los que se
   mantienen conservan su registro y su fecha de alta.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_PerfilCargo_Reemplazar
    @idePerfil  bigint,
    @cargos     seguridad.TYPE_PERFIL_CARGO READONLY,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM seguridad.TMC_PERFIL
                   WHERE idePerfil = @idePerfil AND flgEstado = 1)
        THROW 50003, 'El perfil indicado no existe o fue eliminado.', 1;

    IF EXISTS (SELECT 1 FROM @cargos GROUP BY numCodigoCargo HAVING COUNT(*) > 1)
        THROW 50004, 'El mismo cargo no puede asociarse dos veces al perfil.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE pc
        SET pc.flgEstado               = 0,
            pc.fecActualizacion        = GETDATE(),
            pc.txtUsuarioActualizacion = @txtUsuario
        FROM seguridad.TMD_PERFIL_CARGO pc
        WHERE pc.idePerfil = @idePerfil
          AND pc.flgEstado = 1
          AND NOT EXISTS (SELECT 1 FROM @cargos c WHERE c.numCodigoCargo = pc.numCodigoCargo);

        INSERT INTO seguridad.TMD_PERFIL_CARGO
              (idePerfil, numCodigoCargo, txtCargo, txtArea, txtDepartamento,
               flgEstado, fecCreacion, txtUsuarioCreacion)
        SELECT @idePerfil, c.numCodigoCargo, c.txtCargo, c.txtArea, c.txtDepartamento,
               1, GETDATE(), @txtUsuario
        FROM @cargos c
        WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_CARGO pc
                          WHERE pc.idePerfil = @idePerfil
                            AND pc.numCodigoCargo = c.numCodigoCargo
                            AND pc.flgEstado = 1);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   HU-001 CA-01: perfiles asignados o, en su defecto, los de su cargo
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_ListarPorUsuario
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM seguridad.TMD_PERFIL_USUARIO pu
               INNER JOIN seguridad.TMC_PERFIL p ON p.idePerfil = pu.idePerfil AND p.flgEstado = 1
               WHERE pu.txtUsuario = @txtUsuario AND pu.flgEstado = 1)
    BEGIN
        SELECT p.codPerfil,
               p.nomPerfil
        FROM seguridad.TMD_PERFIL_USUARIO pu
        INNER JOIN seguridad.TMC_PERFIL p ON p.idePerfil = pu.idePerfil AND p.flgEstado = 1
        WHERE pu.txtUsuario = @txtUsuario
          AND pu.flgEstado = 1
        -- El primer perfil asignado es el que queda activo al ingresar.
        ORDER BY pu.idePerfilUsuario;
        RETURN;
    END

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS varchar(30)) AS codPerfil, CAST(NULL AS varchar(100)) AS nomPerfil WHERE 1 = 0;
        RETURN;
    END

    -- Consulta de la HU-001 para ubicar a la persona por su correo; el cargo se
    -- cruza por CodigoPuesto, que es el codigo de la tabla de cargos del CA-04.
    EXEC sp_executesql N'
        SELECT p.codPerfil, p.nomPerfil
        FROM seguridad.TMC_PERFIL p
        WHERE p.flgEstado = 1
          AND EXISTS (
                SELECT 1
                FROM BD_SPRING.dbo.Usuario u
                INNER JOIN BD_SPRING.dbo.PersonaMast pm ON RTRIM(u.Usuario) = RTRIM(pm.CodigoUsuario)
                INNER JOIN BD_SPRING.dbo.EmpleadoMast em ON pm.Persona = em.Empleado
                INNER JOIN seguridad.TMD_PERFIL_CARGO pc
                        ON pc.numCodigoCargo = em.CodigoCargo AND pc.flgEstado = 1
                WHERE LOWER(RTRIM(pm.CorreoElectronico)) = LOWER(RTRIM(@correo))
                  AND RTRIM(u.Estado) = ''A''
                  AND pc.idePerfil = p.idePerfil)
        ORDER BY p.idePerfil;',
        N'@correo varchar(100)', @correo = @txtUsuario;
END
GO

/* -------------------------------------------------------------------------
   HU-001 CA-01: datos de la persona en BD_SPRING

   Consulta de la HU. Un mismo correo puede estar en mas de un usuario (hay
   practicantes que heredan la cuenta): se devuelve primero el activo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_Usuario_ObtenerSpring
    @txtCorreo varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS varchar(20)) AS Usuario, CAST(NULL AS varchar(100)) AS Nombre,
               CAST(NULL AS varchar(100)) AS CorreoElectronico, CAST(NULL AS varchar(1)) AS Estado,
               CAST(NULL AS varchar(200)) AS Area, CAST(NULL AS varchar(200)) AS Departamento,
               CAST(NULL AS varchar(20)) AS Codigo, CAST(NULL AS varchar(200)) AS Cargo,
               CAST(NULL AS int) AS CodigoPuesto
        WHERE 1 = 0;
        RETURN;
    END

    EXEC sp_executesql N'
        SELECT TOP (1)
            RTRIM(u.Usuario) AS Usuario,
            RTRIM(u.Nombre) AS Nombre,
            RTRIM(pm.CorreoElectronico) AS CorreoElectronico,
            RTRIM(u.Estado) AS Estado,
            RTRIM(hrdiv.DescripcionLarga) AS Area,
            RTRIM(hrdep.Descripcion) AS Departamento,
            RTRIM(hre.codigoRTPS) AS Codigo,
            RTRIM(hre.Descripcion) AS Cargo,
            hre.CodigoPuesto
        FROM BD_SPRING.dbo.Usuario u
        INNER JOIN BD_SPRING.dbo.PersonaMast pm ON RTRIM(u.Usuario) = RTRIM(pm.CodigoUsuario)
        LEFT JOIN BD_SPRING.dbo.EmpleadoMast AS em ON pm.Persona = em.Empleado
        LEFT JOIN BD_SPRING.dbo.HR_PuestoEmpresa hre ON hre.CodigoPuesto = em.CodigoCargo
        LEFT JOIN BD_SPRING.dbo.HR_Departamento hrdep ON em.DepartamentoOperacional = hrdep.Departamento
        LEFT JOIN BD_SPRING.dbo.HR_Division AS hrdiv ON em.Division = hrdiv.Division
        WHERE LOWER(RTRIM(pm.CorreoElectronico)) = LOWER(RTRIM(@correo))
        ORDER BY CASE WHEN RTRIM(u.Estado) = ''A'' THEN 0 ELSE 1 END, u.Nombre;',
        N'@correo varchar(100)', @correo = @txtCorreo;
END
GO

/* -------------------------------------------------------------------------
   Semilla del CA-04 (idempotente)
   ------------------------------------------------------------------------- */

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_CARGO
      (idePerfil, numCodigoCargo, txtCargo, txtArea, txtDepartamento, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, s.numCodigoCargo, s.txtCargo, s.txtArea, s.txtDepartamento, 1, @usuario
FROM (VALUES
    (55, N'ASISTENTE ADMINISTRATIVO -GO', N'GERENCIA DE OPERACIONES', N'OPERACIONES', 'TRABAJADOR'),
    (4, N'ASISTENTE DE GERENCIA GG', N'GERENCIA GENERAL', NULL, 'TRABAJADOR'),
    (126, N'ASISTENTE DE GESTIÓN DE OBRAS.', N'GERENCIA DE OPERACIONES', NULL, 'TRABAJADOR'),
    (138, N'ASISTENTE DE GESTIÓN DOCUMENTAL', N'GERENCIA DE ADMINISTRACION Y FINANZAS', NULL, 'TRABAJADOR'),
    (116, N'AUXILIAR ADMINISTRATIVO', N'GERENCIA GENERAL', N'GERENCIA GENERAL', 'TRABAJADOR'),
    (67, N'CONTADOR', N'GERENCIA DE ADMINISTRACION Y FINANZAS', N'FINANZAS Y CONTABILIDAD', 'CONTADOR'),
    (67, N'CONTADOR', N'GERENCIA DE ADMINISTRACION Y FINANZAS', N'FINANZAS Y CONTABILIDAD', 'ADMINISTRADOR'),
    (12, N'ESPECIALISTA DE CALIDAD Y MEJORA DE PROCESOS', N'OFICINA DE PLANEAMIENTO Y MEJORA CONTINUA', N'PLANEAMIENTO Y MEJORA CONTINUA', 'TRABAJADOR'),
    (14, N'ESPECIALISTA DE CONTROL DE GESTION', N'OFICINA DE PLANEAMIENTO Y MEJORA CONTINUA', N'PLANEAMIENTO Y MEJORA CONTINUA', 'TRABAJADOR'),
    (114, N'Especialista de Control Previo', N'GERENCIA DE ADMINISTRACION Y FINANZAS', NULL, 'TRABAJADOR'),
    (15, N'ESPECIALISTA DE LOGISTICA.', N'GERENCIA DE ADMINISTRACION Y FINANZAS', N'ADMINISTRACION Y LOGISTICA', 'TRABAJADOR'),
    (131, N'ESPECIALISTA DE OPERACIONES AMBIENTALES', N'GERENCIA DE OPERACIONES', NULL, 'TRABAJADOR'),
    (135, N'ESPECIALISTA DE PRESUPUESTO E INVERSIONES', N'GERENCIA DE ADMINISTRACION Y FINANZAS', NULL, 'TRABAJADOR'),
    (17, N'ESPECIALISTA DE RELACIONES COMUNITARIAS', N'GERENCIA DE OPERACIONES', N'POST CIERRE Y MANTENIMIENTO', 'TRABAJADOR'),
    (119, N'Especialista de Seguridad, Salud Ocupacional y Medio Ambiente', N'GERENCIA DE OPERACIONES', N'OPERACIONES', 'TRABAJADOR'),
    (27, N'ESPECIALISTA DE TESORERIA', N'GERENCIA DE ADMINISTRACION Y FINANZAS', N'FINANZAS Y CONTABILIDAD', 'TRABAJADOR'),
    (10, N'ESPECIALISTA EN ADMINISTRACION DE PERSONAL', N'GERENCIA GENERAL', N'GESTION HUMANA', 'TRABAJADOR'),
    (53, N'ESPECIALISTA EN DESARROLLO DE PERSONAL', N'GERENCIA GENERAL', N'GESTION HUMANA', 'TRABAJADOR'),
    (125, N'ESPECIALISTA EN GESTIÓN DE OBRAS', N'GERENCIA DE OPERACIONES', NULL, 'TRABAJADOR'),
    (83, N'Especialista en Ingenieria de Proyectos', N'GERENCIA DE OPERACIONES', N'INGENIERIA DE PROYECTOS', 'TRABAJADOR'),
    (21, N'ESPECIALISTA EN INGENIERIA DE PROYECTOS3', N'GERENCIA DE OPERACIONES', N'INGENIERIA DE PROYECTOS', 'TRABAJADOR'),
    (130, N'ESPECIALISTA EN POST CIERRE Y MANTENIMIENTO', N'GERENCIA DE OPERACIONES', NULL, 'TRABAJADOR'),
    (132, N'ESPECIALISTA EN PREVENCIÓN Y GESTIÓN DE CONFLICTOS SOCIALES', N'GERENCIA GENERAL', N'OPERACIONES', 'TRABAJADOR'),
    (136, N'ESPECIALISTA EN SERVICIOS GENERALES Y PATRIMONIO', N'GERENCIA DE ADMINISTRACION Y FINANZAS', N'ADMINISTRACION Y LOGISTICA', 'TRABAJADOR'),
    (26, N'ESPECIALISTA EN SISTEMAS DE INFORMACION', N'GERENCIA DE ADMINISTRACION Y FINANZAS', N'TECNOLOGIA DE LA INFORMACION Y COMUNCACIONES', 'ADMINISTRADOR'),
    (30, N'GERENTE DE OPERACIONES', N'GERENCIA DE OPERACIONES', NULL, 'JEFE'),
    (200, N'GERENTE INVERSION PRIVADA (D) SUP DE INVERSION PRIVADA', NULL, NULL, 'SUPERVISOR'),
    (44, N'JEFE DE DEPARTAMENTO DE INGENIERIA DE PROYECTOS', N'GERENCIA DE OPERACIONES', N'INGENIERIA DE PROYECTOS', 'JEFE'),
    (127, N'JEFE DE DEPARTAMENTO DE POST CIERRE Y MANTENIMIENTO', N'GERENCIA DE OPERACIONES', NULL, 'JEFE'),
    (38, N'JEFE DE DEPARTAMENTO DE TEC. DE LA INFORMACION Y COMUNICACIONES', N'GERENCIA DE ADMINISTRACION Y FINANZAS', N'TECNOLOGIA DE LA INFORMACION Y COMUNCACIONES', 'ADMINISTRADOR'),
    (122, N'JEFE DEL DEPARTAMENTO DE GESTIÓN DE OBRAS', N'GERENCIA DE OPERACIONES', N'GESTION DE OBRAS', 'JEFE'),
    (143, N'SUPERVISOR DE EJECUCION DE INVERSIONES', N'GERENCIA DE OPERACIONES', N'INGENIERIA DE PROYECTOS', 'SUPERVISOR'),
    (124, N'SUPERVISOR DE GESTIÓN DE OBRAS', N'GERENCIA DE OPERACIONES', N'GESTION DE OBRAS', 'SUPERVISOR'),
    (118, N'SUPERVISOR DE GESTIÓN DE PROYECTOS', N'GERENCIA DE OPERACIONES', N'OPERACIONES', 'SUPERVISOR'),
    (96, N'SUPERVISOR DE IMAGEN INSTITUCIONAL Y PROMOCION', NULL, NULL, 'SUPERVISOR'),
    (45, N'SUPERVISOR DE INVERSION PRIVADA', N'GERENCIA DE INVERSION PRIVADA', N'INVERSIÓN PRIVADA', 'SUPERVISOR'),
    (128, N'SUPERVISOR DE PLAN DE CIERRE', N'GERENCIA DE OPERACIONES', NULL, 'SUPERVISOR'),
    (99, N'SUPERVISOR DE RELACIONES COMUNITARIAS', N'GERENCIA DE OPERACIONES', N'OPERACIONES', 'SUPERVISOR')
) AS s(numCodigoCargo, txtCargo, txtArea, txtDepartamento, codPerfil)
INNER JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = s.codPerfil AND pe.flgEstado = 1
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_CARGO pc
                  WHERE pc.idePerfil = pe.idePerfil
                    AND pc.numCodigoCargo = s.numCodigoCargo);
GO
