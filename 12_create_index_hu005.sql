/* =========================================================================
   HU-005 / HU-006 - Indices de negocio y de apoyo al registro de horas
   ========================================================================= */

USE [COSTO_LABOR];
GO

-- Opciones exigidas por SQL Server para crear indices filtrados
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* -------------------------------------------------------------------------
   Unicidad que sostiene la consolidacion automatica del CA-04.

   Sin esto, un guardado concurrente puede dejar dos cabeceras para el mismo
   empleado, proyecto y dia, y la suma consolidada queda duplicada. El filtro
   por flgEstado = 1 permite reutilizar la combinacion si la fila se dio de
   baja logica, con el mismo criterio ya aplicado en la HU-004.
   ------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_TMD_REGISTRO_HORADIA_DIA'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORADIA'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_REGISTRO_HORADIA_DIA
        ON registro.TMD_REGISTRO_HORADIA (ideEmpleado ASC, codProyecto ASC, fecLabor ASC)
        WHERE flgEstado = 1;
GO

-- Se indexa por anio y mes, no por idePeriodo, porque esa columna admite NULL
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_TMD_REGISTRO_HORAMES_PERIODO'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORAMES'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_REGISTRO_HORAMES_PERIODO
        ON registro.TMD_REGISTRO_HORAMES (numAnio ASC, numMes ASC, ideEmpleado ASC, codProyecto ASC)
        WHERE flgEstado = 1;
GO

/* -------------------------------------------------------------------------
   Apoyo a las consultas de la grilla y del historial
   ------------------------------------------------------------------------- */

-- Carga de la grilla Proyecto x Dia de un trabajador en un periodo
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_REGISTRO_HORADIA_GRILLA'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORADIA'))
    CREATE NONCLUSTERED INDEX IX_TMD_REGISTRO_HORADIA_GRILLA
        ON registro.TMD_REGISTRO_HORADIA (numAnio ASC, numMes ASC, ideEmpleado ASC, flgEstado ASC)
        INCLUDE (codProyecto, nomProyecto, numDia, fecLabor, numHoras);
GO

-- Filas de la grilla: proyectos asignados al trabajador en el periodo
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_PERIODO_PROYECTO_EMPLEADO'
                 AND object_id = OBJECT_ID('registro.TMD_PERIODO_PROYECTO'))
    CREATE NONCLUSTERED INDEX IX_TMD_PERIODO_PROYECTO_EMPLEADO
        ON registro.TMD_PERIODO_PROYECTO (numAnio ASC, numMes ASC, ideEmpleado ASC, flgEstado ASC)
        INCLUDE (codProyecto, nomProyecto);
GO

-- Historial cronologico de observaciones y respuestas (CA-05)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_REGISTRO_HORADIA_VALIDACION_HIST'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORADIA_VALIDACION'))
    CREATE NONCLUSTERED INDEX IX_TMD_REGISTRO_HORADIA_VALIDACION_HIST
        ON registro.TMD_REGISTRO_HORADIA_VALIDACION (ideRegistroHoradia ASC, fecCreacion ASC);
GO

-- Detalle del modal: actividades y tareas de un registro diario
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_REGISTRO_HORADIA_ACT_CABECERA'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORADIA_ACT'))
    CREATE NONCLUSTERED INDEX IX_TMD_REGISTRO_HORADIA_ACT_CABECERA
        ON registro.TMD_REGISTRO_HORADIA_ACT (ideRegistroHoradia ASC, flgEstado ASC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_REGISTRO_HORADIA_ACTTAREA_ACT'
                 AND object_id = OBJECT_ID('registro.TMD_REGISTRO_HORADIA_ACTTAREA'))
    CREATE NONCLUSTERED INDEX IX_TMD_REGISTRO_HORADIA_ACTTAREA_ACT
        ON registro.TMD_REGISTRO_HORADIA_ACTTAREA (ideRegistroHoradiaAct ASC, flgEstado ASC);
GO
