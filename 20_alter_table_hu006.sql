/* =========================================================================
   HU-006 - Unidad organica y jerarquia del registro mensual

   El CA-02 pide que la grilla liste "agrupados por unidad organica a los
   trabajadores asignados al usuario en sesion", con tres columnas fijas:
   Departamento (sigla DGO, DIP), Nivel (JEFE, ADMINISTRATIVO, SUBORDINADO)
   y Trabajador. Ninguna de las dos primeras existe en el modelo, y tampoco
   existe forma de saber que trabajadores dependen de quien.

   PROPUESTA: los tres campos requieren visto bueno del lider tecnico. En el
   sistema real salen del ERP SPRING; aqui se agregan donde ya vive el
   empleado del periodo para no crear un maestro nuevo.

   ideEmpleadoJefe cubre ademas el pendiente que dejo anotado la HU-005 en
   13_alter_usuario_empleado.sql: sin el, usp_RegistroHoraDia_ListarTrabajadores
   devuelve toda la planilla a cualquier jefatura.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* CREATE INDEX exige estas opciones activas. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* -------------------------------------------------------------------------
   1. Unidad organica y nivel jerarquico del trabajador en el periodo

   Se guardan por periodo y no en un maestro aparte porque una persona puede
   cambiar de departamento o de nivel entre un mes y otro, y la grilla de un
   mes cerrado debe seguir mostrando la estructura que tenia entonces.
   ------------------------------------------------------------------------- */

IF COL_LENGTH('registro.TMD_PERIODO_EMPLEADO', 'codDepartamento') IS NULL
    ALTER TABLE registro.TMD_PERIODO_EMPLEADO ADD
        codDepartamento varchar(10)  NULL,
        nomDepartamento varchar(200) NULL,
        codNivel        varchar(20)  NULL,
        ideEmpleadoJefe bigint       NULL;
GO

-- Los tres niveles del CA-02. Se admite NULL mientras el ERP no provea el dato.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = 'CK_TMD_PERIODO_EMPLEADO_NIVEL')
    ALTER TABLE registro.TMD_PERIODO_EMPLEADO
        ADD CONSTRAINT CK_TMD_PERIODO_EMPLEADO_NIVEL
        CHECK (codNivel IS NULL OR codNivel IN ('JEFE', 'ADMINISTRATIVO', 'SUBORDINADO'));
GO

/* -------------------------------------------------------------------------
   2. Indices de la grilla mensual

   La grilla se arma en tres consultas sobre el mismo periodo: los
   trabajadores del jefe en sesion, los proyectos que forman las columnas y
   las horas de cada cruce.
   ------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_PERIODO_EMPLEADO_JEFE'
                 AND object_id = OBJECT_ID('registro.TMD_PERIODO_EMPLEADO'))
    CREATE NONCLUSTERED INDEX IX_TMD_PERIODO_EMPLEADO_JEFE
        ON registro.TMD_PERIODO_EMPLEADO (numAnio ASC, numMes ASC, ideEmpleadoJefe ASC, flgEstado ASC)
        INCLUDE (ideEmpleado, nomEmpleado, codDepartamento, nomDepartamento, codNivel, txtObservaciones);
GO

-- Cruce Trabajador x Proyecto que llena las celdas (CA-02)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_REGISTRO_HORAMES_GRILLA'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORAMES'))
    CREATE NONCLUSTERED INDEX IX_TMD_REGISTRO_HORAMES_GRILLA
        ON registro.TMD_REGISTRO_HORAMES (numAnio ASC, numMes ASC, ideEmpleado ASC, flgEstado ASC)
        INCLUDE (codProyecto, nomProyecto, numHoras);
GO

-- Historial cronologico de observaciones y respuestas (CA-05)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_REGISTRO_HORAMES_VALIDACION_HIST'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORAMES_VALIDACION'))
    CREATE NONCLUSTERED INDEX IX_TMD_REGISTRO_HORAMES_VALIDACION_HIST
        ON registro.TMD_REGISTRO_HORAMES_VALIDACION (ideRegistroHorames ASC, fecCreacion ASC);
GO

-- Detalle del modal: actividades y tareas de un registro mensual
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_REGISTRO_HORAMES_ACT_CABECERA'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORAMES_ACT'))
    CREATE NONCLUSTERED INDEX IX_TMD_REGISTRO_HORAMES_ACT_CABECERA
        ON registro.TMD_REGISTRO_HORAMES_ACT (ideRegistroHorames ASC, flgEstado ASC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_REGISTRO_HORAMES_ACTTAREA_ACT'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORAMES_ACTTAREA'))
    CREATE NONCLUSTERED INDEX IX_TMD_REGISTRO_HORAMES_ACTTAREA_ACT
        ON registro.TMD_REGISTRO_HORAMES_ACTTAREA (ideRegistroHoramesAct ASC, flgEstado ASC);
GO

/* -------------------------------------------------------------------------
   3. Documentacion de las columnas nuevas
   ------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE major_id = OBJECT_ID('registro.TMD_PERIODO_EMPLEADO')
                 AND minor_id = COLUMNPROPERTY(OBJECT_ID('registro.TMD_PERIODO_EMPLEADO'), 'codDepartamento', 'ColumnId')
                 AND name = 'MS_Description')
    EXEC sys.sp_addextendedproperty @name=N'MS_Description',
         @value=N'Sigla de la unidad organica del trabajador en el periodo (DGO, DIP)',
         @level0type=N'SCHEMA', @level0name=N'registro',
         @level1type=N'TABLE',  @level1name=N'TMD_PERIODO_EMPLEADO',
         @level2type=N'COLUMN', @level2name=N'codDepartamento';
GO

IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE major_id = OBJECT_ID('registro.TMD_PERIODO_EMPLEADO')
                 AND minor_id = COLUMNPROPERTY(OBJECT_ID('registro.TMD_PERIODO_EMPLEADO'), 'codNivel', 'ColumnId')
                 AND name = 'MS_Description')
    EXEC sys.sp_addextendedproperty @name=N'MS_Description',
         @value=N'Nivel jerarquico: JEFE, ADMINISTRATIVO o SUBORDINADO. Solo SUBORDINADO admite captura de horas',
         @level0type=N'SCHEMA', @level0name=N'registro',
         @level1type=N'TABLE',  @level1name=N'TMD_PERIODO_EMPLEADO',
         @level2type=N'COLUMN', @level2name=N'codNivel';
GO

IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE major_id = OBJECT_ID('registro.TMD_PERIODO_EMPLEADO')
                 AND minor_id = COLUMNPROPERTY(OBJECT_ID('registro.TMD_PERIODO_EMPLEADO'), 'ideEmpleadoJefe', 'ColumnId')
                 AND name = 'MS_Description')
    EXEC sys.sp_addextendedproperty @name=N'MS_Description',
         @value=N'Jefe del que depende el trabajador en el periodo; delimita que filas ve el usuario en sesion',
         @level0type=N'SCHEMA', @level0name=N'registro',
         @level1type=N'TABLE',  @level1name=N'TMD_PERIODO_EMPLEADO',
         @level2type=N'COLUMN', @level2name=N'ideEmpleadoJefe';
GO
