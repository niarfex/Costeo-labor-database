/* ============================================================================
   HU-003 - Mantenimiento de tipos de usuario y permisos
   Tablas de perfiles, opciones del sistema y sus asignaciones.

   No hay tabla de usuarios ni de contrasenas: la identidad la administra
   Microsoft Entra ID. Aqui solo se guarda la relacion entre un perfil y el
   usuario, referenciado por su correo y por su objectId de Entra.

   Nomenclatura siguiendo el esquema existente:
     TG_  catalogo general      TMC_ maestro cabecera     TMD_ maestro detalle

   La unicidad se resuelve con indices filtrados por flgEstado = 1, igual que
   en 04_create_index.sql: asi un registro dado de baja no bloquea volver a
   usar el mismo codigo o la misma asignacion.
   ============================================================================ */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'seguridad')
    EXEC('CREATE SCHEMA seguridad');
GO

/* ---------------------------------------------------------------------------
   Catalogo de opciones (pantallas) del sistema.
   ideOpcionPadre permite armar el menu en dos niveles: titulo y sub-opcion.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('seguridad.TG_OPCION') IS NULL
CREATE TABLE seguridad.TG_OPCION(
    ideOpcion bigint IDENTITY(1,1) NOT NULL,
    codOpcion varchar(30) NOT NULL,
    nomOpcion varchar(100) NOT NULL,
    txtRuta varchar(200) NULL,
    txtIcono varchar(50) NULL,
    ideOpcionPadre bigint NULL,
    numOrden int NULL,
    flgEstado int NULL,
    fecCreacion datetime NULL,
    txtUsuarioCreacion varchar(100) NULL,
    fecActualizacion datetime NULL,
    txtUsuarioActualizacion varchar(100) NULL,
    CONSTRAINT PK_TG_OPCION PRIMARY KEY CLUSTERED (ideOpcion ASC)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TG_OPCION_fecCreacion')
    ALTER TABLE seguridad.TG_OPCION
        ADD CONSTRAINT DF_TG_OPCION_fecCreacion DEFAULT (GETDATE()) FOR fecCreacion;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TG_OPCION_flgEstado')
    ALTER TABLE seguridad.TG_OPCION
        ADD CONSTRAINT DF_TG_OPCION_flgEstado DEFAULT (1) FOR flgEstado;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_TG_OPCION_PADRE')
    ALTER TABLE seguridad.TG_OPCION
        ADD CONSTRAINT FK_TG_OPCION_PADRE FOREIGN KEY (ideOpcionPadre)
            REFERENCES seguridad.TG_OPCION (ideOpcion);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TG_OPCION_CODIGO'
                 AND object_id = OBJECT_ID('seguridad.TG_OPCION'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TG_OPCION_CODIGO
        ON seguridad.TG_OPCION (codOpcion ASC)
        WHERE flgEstado = 1;
GO

/* ---------------------------------------------------------------------------
   Perfiles del sistema. El codigo es unico, tal como lo pide la HU-003.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('seguridad.TMC_PERFIL') IS NULL
CREATE TABLE seguridad.TMC_PERFIL(
    idePerfil bigint IDENTITY(1,1) NOT NULL,
    codPerfil varchar(30) NOT NULL,
    nomPerfil varchar(100) NOT NULL,
    txtDescripcion varchar(200) NULL,
    flgEstado int NULL,
    fecCreacion datetime NULL,
    txtUsuarioCreacion varchar(100) NULL,
    fecActualizacion datetime NULL,
    txtUsuarioActualizacion varchar(100) NULL,
    CONSTRAINT PK_TMC_PERFIL PRIMARY KEY CLUSTERED (idePerfil ASC)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TMC_PERFIL_fecCreacion')
    ALTER TABLE seguridad.TMC_PERFIL
        ADD CONSTRAINT DF_TMC_PERFIL_fecCreacion DEFAULT (GETDATE()) FOR fecCreacion;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TMC_PERFIL_flgEstado')
    ALTER TABLE seguridad.TMC_PERFIL
        ADD CONSTRAINT DF_TMC_PERFIL_flgEstado DEFAULT (1) FOR flgEstado;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TMC_PERFIL_CODIGO'
                 AND object_id = OBJECT_ID('seguridad.TMC_PERFIL'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMC_PERFIL_CODIGO
        ON seguridad.TMC_PERFIL (codPerfil ASC)
        WHERE flgEstado = 1;
GO

/* ---------------------------------------------------------------------------
   Opciones habilitadas por perfil.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('seguridad.TMD_PERFIL_OPCION') IS NULL
CREATE TABLE seguridad.TMD_PERFIL_OPCION(
    idePerfilOpcion bigint IDENTITY(1,1) NOT NULL,
    idePerfil bigint NOT NULL,
    ideOpcion bigint NOT NULL,
    flgEstado int NULL,
    fecCreacion datetime NULL,
    txtUsuarioCreacion varchar(100) NULL,
    fecActualizacion datetime NULL,
    txtUsuarioActualizacion varchar(100) NULL,
    CONSTRAINT PK_TMD_PERFIL_OPCION PRIMARY KEY CLUSTERED (idePerfilOpcion ASC)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TMD_PERFIL_OPCION_fecCreacion')
    ALTER TABLE seguridad.TMD_PERFIL_OPCION
        ADD CONSTRAINT DF_TMD_PERFIL_OPCION_fecCreacion DEFAULT (GETDATE()) FOR fecCreacion;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_PERFIL_OPCION_PERFIL')
    ALTER TABLE seguridad.TMD_PERFIL_OPCION
        ADD CONSTRAINT FK_PERFIL_OPCION_PERFIL FOREIGN KEY (idePerfil)
            REFERENCES seguridad.TMC_PERFIL (idePerfil);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_PERFIL_OPCION_OPCION')
    ALTER TABLE seguridad.TMD_PERFIL_OPCION
        ADD CONSTRAINT FK_PERFIL_OPCION_OPCION FOREIGN KEY (ideOpcion)
            REFERENCES seguridad.TG_OPCION (ideOpcion);
GO

-- Una opcion no puede repetirse dentro del mismo perfil mientras este vigente
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TMD_PERFIL_OPCION'
                 AND object_id = OBJECT_ID('seguridad.TMD_PERFIL_OPCION'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_PERFIL_OPCION
        ON seguridad.TMD_PERFIL_OPCION (idePerfil ASC, ideOpcion ASC)
        WHERE flgEstado = 1;
GO

/* ---------------------------------------------------------------------------
   Usuarios asignados a cada perfil.

   txtUsuario  : UPN o correo con el que la persona inicia sesion en Entra.
   txtObjectId : identificador de Entra. Se guarda porque es estable aunque a
                 la persona le cambien el correo, y evita perder la asignacion.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('seguridad.TMD_PERFIL_USUARIO') IS NULL
CREATE TABLE seguridad.TMD_PERFIL_USUARIO(
    idePerfilUsuario bigint IDENTITY(1,1) NOT NULL,
    idePerfil bigint NOT NULL,
    txtUsuario varchar(100) NOT NULL,
    txtObjectId varchar(36) NULL,
    txtNombreCompleto varchar(150) NULL,
    flgEstado int NULL,
    fecCreacion datetime NULL,
    txtUsuarioCreacion varchar(100) NULL,
    fecActualizacion datetime NULL,
    txtUsuarioActualizacion varchar(100) NULL,
    CONSTRAINT PK_TMD_PERFIL_USUARIO PRIMARY KEY CLUSTERED (idePerfilUsuario ASC)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_TMD_PERFIL_USUARIO_fecCreacion')
    ALTER TABLE seguridad.TMD_PERFIL_USUARIO
        ADD CONSTRAINT DF_TMD_PERFIL_USUARIO_fecCreacion DEFAULT (GETDATE()) FOR fecCreacion;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_PERFIL_USUARIO_PERFIL')
    ALTER TABLE seguridad.TMD_PERFIL_USUARIO
        ADD CONSTRAINT FK_PERFIL_USUARIO_PERFIL FOREIGN KEY (idePerfil)
            REFERENCES seguridad.TMC_PERFIL (idePerfil);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TMD_PERFIL_USUARIO'
                 AND object_id = OBJECT_ID('seguridad.TMD_PERFIL_USUARIO'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_PERFIL_USUARIO
        ON seguridad.TMD_PERFIL_USUARIO (idePerfil ASC, txtUsuario ASC)
        WHERE flgEstado = 1;
GO

-- Apoyo: al iniciar sesion se busca el perfil de la persona por su correo
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_TMD_PERFIL_USUARIO_USUARIO'
                 AND object_id = OBJECT_ID('seguridad.TMD_PERFIL_USUARIO'))
    CREATE NONCLUSTERED INDEX IX_TMD_PERFIL_USUARIO_USUARIO
        ON seguridad.TMD_PERFIL_USUARIO (txtUsuario ASC, flgEstado ASC);
GO
