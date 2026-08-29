/* =========================================================================
   HU-005 - Vinculo entre el usuario autenticado y el empleado

   PROPUESTA: requiere visto bueno del lider tecnico antes de aplicarse.

   El problema: todas las tablas de registro.* identifican a la persona con
   ideEmpleado (bigint) + nomEmpleado, pero la seguridad identifica al usuario
   con txtUsuario / txtObjectId de Entra ID. No existe tabla de empleados ni
   ninguna columna que una ambos mundos.

   Sin ese vinculo la HU-005 no puede resolver el CA-01 ("mostrando el nombre
   del Trabajador autenticado"), porque no hay forma de saber que ideEmpleado
   le corresponde a quien inicio sesion.

   Se propone la solucion minima: agregar el ideEmpleado donde ya vive la
   identidad del usuario, en lugar de crear una tabla nueva. El valor lo
   provee el ERP SPRING (PersonaMast.Persona / EmpleadoMast.Empleado, ver
   99_obtener_datos_spring.sql).

   PENDIENTE APARTE: la jerarquia jefe -> personal a cargo que pide el CA-01
   para las vistas de la Gerencia de Operaciones y de Inversion Privada
   tampoco existe en el modelo. Hay que definir de donde sale.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* CREATE INDEX exige estas opciones activas. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('seguridad.TMD_PERFIL_USUARIO', 'ideEmpleado') IS NULL
    ALTER TABLE seguridad.TMD_PERFIL_USUARIO ADD ideEmpleado bigint NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_PERFIL_USUARIO_EMPLEADO'
                 AND object_id = OBJECT_ID('seguridad.TMD_PERFIL_USUARIO'))
    CREATE NONCLUSTERED INDEX IX_TMD_PERFIL_USUARIO_EMPLEADO
        ON seguridad.TMD_PERFIL_USUARIO (txtUsuario ASC, flgEstado ASC)
        INCLUDE (ideEmpleado, txtNombreCompleto);
GO

IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE major_id = OBJECT_ID('seguridad.TMD_PERFIL_USUARIO')
                 AND minor_id = COLUMNPROPERTY(OBJECT_ID('seguridad.TMD_PERFIL_USUARIO'), 'ideEmpleado', 'ColumnId')
                 AND name = 'MS_Description')
    EXEC sys.sp_addextendedproperty @name=N'MS_Description',
         @value=N'Codigo del empleado en el ERP SPRING; une la identidad de Entra ID con los registros de horas',
         @level0type=N'SCHEMA', @level0name=N'seguridad',
         @level1type=N'TABLE',  @level1name=N'TMD_PERFIL_USUARIO',
         @level2type=N'COLUMN', @level2name=N'ideEmpleado';
GO
